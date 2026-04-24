#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$SCRIPT_DIR"

MODE="quick"
QUICK_TARGET_SECONDS=30
SAMPLES=3
REASONING_EFFORT="medium"
MODELS=("gpt-5.5" "gpt-5.4" "gpt-5.4-mini" "gpt-5.3-codex" "gpt-5.2")
QUICK_MODELS=("gpt-5.5" "gpt-5.4" "gpt-5.4-mini")
MODEL_BASELINE="gpt-5.4-mini"
CONFIG_FILE="${CODEX_CLI_CONFIG:-$HOME/.codex/config.toml}"
RELAY_BASE_URL=""
RELAY_API_KEY=""
OUT_DIR="${PROJECT_ROOT}/reports"
TIMESTAMP="$(date -u +%Y%m%dT%H%M%SZ)"
JSON_OUT=""
MD_OUT=""

usage() {
  cat <<'EOF'
Run API quality + model anti-spoof checks (sanitized).

Usage:
  check-api-quality-and-model-integrity.sh [options]

Options:
  --mode <quick|full>       quick: 10-30s confidence check; full: full fingerprint check (default: quick)
  --samples <n>             Samples per model in full mode (default: 3)
  --reasoning-effort <lvl>  Reasoning effort for benchmark calls (default: medium)
  --models "<a b c>"        Model list for full mode
  --quick-models "<a b c>"  Model list for quick mode (default: gpt-5.5 gpt-5.4 gpt-5.4-mini)
  --baseline <model>        Baseline model for similarity checks (default: gpt-5.4-mini)
  --relay-base-url <url>    Relay base URL (default from ~/.codex/config.toml)
  --relay-api-key <key>     Relay API key (default from ~/.codex/auth.json or OPENAI_API_KEY)
  --config <path>           CLI config path (default: ~/.codex/config.toml)
  --out-dir <path>          Report output directory (default: <project>/reports)
  -h, --help                Show help
EOF
}

require_cmds() {
  local missing=0
  for c in "$@"; do
    if ! command -v "$c" >/dev/null 2>&1; then
      echo "[error] missing command: $c" >&2
      missing=1
    fi
  done
  if [[ "$missing" -ne 0 ]]; then
    exit 1
  fi
}

extract_root_value() {
  local file="$1"
  local key="$2"
  rg -n "^[[:space:]]*${key}[[:space:]]*=" "$file" \
    | head -n1 \
    | sed -E 's/^[^"]*"([^"]+)".*/\1/' || true
}

extract_provider_value() {
  local file="$1"
  local provider="$2"
  local key="$3"
  awk -v section="[model_providers.${provider}]" -v target="$key" '
    /^\[/ { in_section = ($0 == section) }
    in_section && $0 ~ "^[[:space:]]*" target "[[:space:]]*=" {
      if (match($0, /"[^"]+"/)) {
        value = substr($0, RSTART + 1, RLENGTH - 2)
        print value
        exit
      }
    }
  ' "$file"
}

now_ms() {
  perl -MTime::HiRes=time -e 'printf("%.0f\n", time()*1000)'
}

post_json() {
  local url="$1"
  local api_key="$2"
  local body="$3"
  local body_file
  local code
  local start
  local end
  local latency

  body_file="$(mktemp)"
  start="$(now_ms)"
  code="$(curl -sS -o "$body_file" -w '%{http_code}' "$url" \
    -H "Authorization: Bearer $api_key" \
    -H "Content-Type: application/json" \
    -d "$body")" || code="000"
  end="$(now_ms)"
  latency="$((end - start))"
  printf '%s\t%s\t%s\n' "$code" "$latency" "$body_file"
}

sanitize_url() {
  local raw="$1"
  echo "$raw" | sed -E 's#(https?://[^/]+).*#\1#'
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --mode) MODE="$2"; shift 2 ;;
    --samples) SAMPLES="$2"; shift 2 ;;
    --reasoning-effort) REASONING_EFFORT="$2"; shift 2 ;;
    --models) IFS=' ' read -r -a MODELS <<< "$2"; shift 2 ;;
    --quick-models) IFS=' ' read -r -a QUICK_MODELS <<< "$2"; shift 2 ;;
    --baseline) MODEL_BASELINE="$2"; shift 2 ;;
    --relay-base-url) RELAY_BASE_URL="$2"; shift 2 ;;
    --relay-api-key) RELAY_API_KEY="$2"; shift 2 ;;
    --config) CONFIG_FILE="$2"; shift 2 ;;
    --out-dir) OUT_DIR="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *)
      echo "[error] unknown argument: $1" >&2
      usage
      exit 1
      ;;
  esac
done

require_cmds curl jq rg awk sed perl

if [[ "$MODE" != "quick" && "$MODE" != "full" ]]; then
  echo "[error] --mode must be quick or full" >&2
  exit 1
fi

if ! [[ "$SAMPLES" =~ ^[0-9]+$ ]] || [[ "$SAMPLES" -lt 1 ]]; then
  echo "[error] --samples must be positive integer" >&2
  exit 1
fi

if ! [[ "$REASONING_EFFORT" =~ ^(none|minimal|low|medium|high|xhigh)$ ]]; then
  echo "[error] --reasoning-effort must be one of: none|minimal|low|medium|high|xhigh" >&2
  exit 1
fi

if [[ -z "$RELAY_BASE_URL" ]]; then
  if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "[error] config file not found: $CONFIG_FILE" >&2
    exit 1
  fi
  provider="$(extract_root_value "$CONFIG_FILE" "model_provider")"
  [[ -z "$provider" ]] && provider="codex"
  RELAY_BASE_URL="$(extract_provider_value "$CONFIG_FILE" "$provider" "base_url")"
fi

if [[ -z "$RELAY_API_KEY" && -f "$HOME/.codex/auth.json" ]]; then
  RELAY_API_KEY="$(jq -r '.OPENAI_API_KEY // empty' "$HOME/.codex/auth.json")"
fi
if [[ -z "$RELAY_API_KEY" ]]; then
  RELAY_API_KEY="${OPENAI_API_KEY:-}"
fi

if [[ -z "$RELAY_BASE_URL" || -z "$RELAY_API_KEY" ]]; then
  echo "[error] relay url/key empty; provide --relay-base-url and --relay-api-key" >&2
  exit 1
fi

mkdir -p "$OUT_DIR"
JSON_OUT="${OUT_DIR}/api-quality-model-integrity-${MODE}-${TIMESTAMP}.json"
MD_OUT="${OUT_DIR}/api-quality-model-integrity-${MODE}-${TIMESTAMP}.md"

RESPONSES_URL="${RELAY_BASE_URL%/}/responses"
SANITIZED_ENDPOINT="$(sanitize_url "$RESPONSES_URL")"

if [[ "$MODE" == "quick" ]]; then
  started_ms="$(now_ms)"
  quick_rows='[]'
  quick_prompt='Quick fingerprint: explain LRU vs LFU in 3 bullets + 1 line verdict. Mention warm-up bias.'

  for m in "${QUICK_MODELS[@]}"; do
    req="$(jq -nc --arg model "$m" --arg prompt "$quick_prompt" '{
      model: $model,
      input: $prompt,
      max_output_tokens: 180,
      reasoning: {effort: "'"$REASONING_EFFORT"'"},
      text: {verbosity: "low"}
    }')"
    IFS=$'\t' read -r code latency body_file < <(post_json "$RESPONSES_URL" "$RELAY_API_KEY" "$req")
    model_echo=0
    out_tok=0
    reason_tok=0
    total_tok=0
    err=""
    if [[ "$code" == "200" ]]; then
      if jq -e --arg model "$m" '.model == $model' "$body_file" >/dev/null 2>&1; then
        model_echo=1
      fi
      out_tok="$(jq -r '.usage.output_tokens // 0' "$body_file" 2>/dev/null || echo 0)"
      reason_tok="$(jq -r '.usage.output_tokens_details.reasoning_tokens // 0' "$body_file" 2>/dev/null || echo 0)"
      total_tok="$(jq -r '.usage.total_tokens // 0' "$body_file" 2>/dev/null || echo 0)"
    else
      err="$(jq -r '.error.message // .message // ""' "$body_file" 2>/dev/null || true)"
    fi

    row="$(jq -nc \
      --arg model "$m" \
      --arg code "$code" \
      --argjson latency_ms "$latency" \
      --argjson model_echo "$model_echo" \
      --argjson output_tokens "$out_tok" \
      --argjson reasoning_tokens "$reason_tok" \
      --argjson total_tokens "$total_tok" \
      --arg error "$err" \
      '{
        model:$model,
        http_code:$code,
        latency_ms:$latency_ms,
        model_echo_ok:($model_echo==1),
        output_tokens:$output_tokens,
        reasoning_tokens:$reasoning_tokens,
        total_tokens:$total_tokens,
        error:$error
      }')"
    quick_rows="$(jq -c --argjson row "$row" '. + [$row]' <<< "$quick_rows")"
    rm -f "$body_file"
  done

  # Negative control: invalid model should fail
  bad_model="gpt-5.5-not-real-probe"
  bad_req="$(jq -nc --arg model "$bad_model" '{model:$model,input:"ping",max_output_tokens:16}')"
  IFS=$'\t' read -r bad_code _ bad_file < <(post_json "$RESPONSES_URL" "$RELAY_API_KEY" "$bad_req")
  bad_msg="$(jq -r '.error.message // .message // ""' "$bad_file" 2>/dev/null || true)"
  bad_model_rejected=0
  if [[ "$bad_code" != "200" ]] && echo "$bad_msg" | rg -qi '不存在|not exist|unknown|not found|model'; then
    bad_model_rejected=1
  fi
  rm -f "$bad_file"

  # Invalid reasoning effort should return enum-style validation error
  bad_param_req="$(jq -nc '{model:"gpt-5.5",input:"OK",max_output_tokens:16,reasoning:{effort:"ultra"}}')"
  IFS=$'\t' read -r bad_param_code _ bad_param_file < <(post_json "$RESPONSES_URL" "$RELAY_API_KEY" "$bad_param_req")
  bad_param_msg="$(jq -r '.error.message // .message // ""' "$bad_param_file" 2>/dev/null || true)"
  bad_param_enum_ok=0
  if [[ "$bad_param_code" =~ ^(400|422)$ ]] && echo "$bad_param_msg" | rg -q 'Supported values are|reasoning\.effort|invalid_value'; then
    bad_param_enum_ok=1
  fi
  rm -f "$bad_param_file"

  # Quick confidence scoring
  score=0
  success_200_count="$(jq '[.[] | select(.http_code=="200")] | length' <<< "$quick_rows")"
  echo_ok_count="$(jq '[.[] | select(.model_echo_ok==true)] | length' <<< "$quick_rows")"
  if [[ "$success_200_count" -ge 2 ]]; then score=$((score+30)); fi
  if [[ "$echo_ok_count" -ge 2 ]]; then score=$((score+20)); fi
  if [[ "$bad_model_rejected" -eq 1 ]]; then score=$((score+20)); fi
  if [[ "$bad_param_enum_ok" -eq 1 ]]; then score=$((score+20)); fi

  # Does gpt-5.5 look suspiciously like mini in this quick run?
  g55="$(jq -c '.[] | select(.model=="gpt-5.5")' <<< "$quick_rows")"
  mini="$(jq -c --arg m "$MODEL_BASELINE" '.[] | select(.model==$m)' <<< "$quick_rows")"
  looks_like_mini=false
  mini_similarity_note="insufficient data"
  if [[ -n "$g55" && -n "$mini" ]]; then
    out_delta="$(jq -n --argjson a "$g55" --argjson b "$mini" 'if ($b.output_tokens|tonumber)>0 then (((($a.output_tokens-$b.output_tokens)|tonumber)|if .<0 then -. else . end)/($b.output_tokens|tonumber)) else 1 end')"
    reason_delta="$(jq -n --argjson a "$g55" --argjson b "$mini" 'if ($b.reasoning_tokens|tonumber)>0 then (((($a.reasoning_tokens-$b.reasoning_tokens)|tonumber)|if .<0 then -. else . end)/($b.reasoning_tokens|tonumber)) else 1 end')"
    if awk -v o="$out_delta" -v r="$reason_delta" 'BEGIN { exit !((o <= 0.20) && (r <= 0.25)) }'; then
      looks_like_mini=true
      mini_similarity_note="gpt-5.5 is close to baseline on quick token fingerprint"
      score=$((score-15))
    else
      looks_like_mini=false
      mini_similarity_note="gpt-5.5 differs from baseline on quick token fingerprint"
      score=$((score+10))
    fi
  fi

  # cost hint: relative cost proxy via total tokens in same task
  cost_proxy="$(jq -c 'map({model,total_tokens})' <<< "$quick_rows")"

  elapsed_ms="$(( $(now_ms) - started_ms ))"
  confidence="low"
  if [[ "$score" -ge 75 ]]; then
    confidence="high"
  elif [[ "$score" -ge 55 ]]; then
    confidence="medium"
  fi

  verdict="inconclusive"
  if [[ "$score" -ge 75 ]]; then
    verdict="likely_real_gpt55_route"
  elif [[ "$score" -le 40 ]]; then
    verdict="suspicious_or_unstable"
  fi

  jq -n \
    --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg mode "$MODE" \
    --arg endpoint "$SANITIZED_ENDPOINT" \
    --argjson target_seconds "$QUICK_TARGET_SECONDS" \
    --argjson elapsed_ms "$elapsed_ms" \
    --arg baseline_model "$MODEL_BASELINE" \
    --arg verdict "$verdict" \
    --arg confidence "$confidence" \
    --argjson score "$score" \
    --argjson bad_model_rejected "$( [[ "$bad_model_rejected" -eq 1 ]] && echo true || echo false )" \
    --argjson bad_param_enum_ok "$( [[ "$bad_param_enum_ok" -eq 1 ]] && echo true || echo false )" \
    --argjson looks_like_mini "$looks_like_mini" \
    --arg mini_similarity_note "$mini_similarity_note" \
    --argjson quick_rows "$quick_rows" \
    --argjson cost_proxy "$cost_proxy" \
    '{
      timestamp:$timestamp,
      report_type:"api_quality_and_model_integrity",
      mode:$mode,
      sanitized:true,
      target:{
        endpoint:$endpoint,
        quick_target_seconds:$target_seconds
      },
      quick_assessment:{
        elapsed_ms:$elapsed_ms,
        score:$score,
        confidence:$confidence,
        verdict:$verdict,
        controls:{
          invalid_model_rejected:$bad_model_rejected,
          invalid_reasoning_param_checked:$bad_param_enum_ok
        },
        gpt55_vs_baseline:{
          baseline_model:$baseline_model,
          looks_like_baseline_mini:$looks_like_mini,
          note:$mini_similarity_note
        },
        per_model:$quick_rows,
        token_cost_proxy:$cost_proxy
      }
    }' > "$JSON_OUT"

  jq -r '
    . as $root
    | ([
      "# API Quality Quick Report (Sanitized)",
      "",
      "- Endpoint: `" + $root.target.endpoint + "`",
      "- Runtime: " + (($root.quick_assessment.elapsed_ms/1000)|floor|tostring) + "s",
      "- Score: " + ($root.quick_assessment.score|tostring) + "/100",
      "- Confidence: `" + $root.quick_assessment.confidence + "`",
      "- Verdict: `" + $root.quick_assessment.verdict + "`",
      "- GPT-5.5 looks like baseline mini: `" + ($root.quick_assessment.gpt55_vs_baseline.looks_like_baseline_mini|tostring) + "`",
      "",
      "## Per Model",
      "",
      "| Model | HTTP | Latency(ms) | Output tok | Reason tok | Total tok | Echo ok |",
      "|---|---:|---:|---:|---:|---:|---|"
    ]
    + (
      $root.quick_assessment.per_model
      | map(
          "| `" + .model + "` | " + .http_code + " | " + (.latency_ms|tostring) + " | " + (.output_tokens|tostring) + " | " + (.reasoning_tokens|tostring) + " | " + (.total_tokens|tostring) + " | " + (.model_echo_ok|tostring) + " |"
        )
    )
    + [
      "",
      "## Note",
      "",
      "- Token cost proxy compares relative token usage only, not billing unit price.",
      "- For full model-feature verification, run with `--mode full`."
    ]) | join("\n")
  ' "$JSON_OUT" > "$MD_OUT"

else
  probe_json_tmp="$(mktemp)"
  "${PROJECT_ROOT}/scripts/probe-gpt55-authenticity.sh" \
    --model "gpt-5.5" \
    --samples "$SAMPLES" \
    --reasoning-effort "$REASONING_EFFORT" \
    --relay-base-url "$RELAY_BASE_URL" \
    --relay-api-key "$RELAY_API_KEY" \
    --out "$probe_json_tmp" >/dev/null

  PROMPT='Benchmark task: compare LRU vs LFU for bursty global feed traffic. Output 6 bullets + 1 verdict; include write-amplification, warm-up bias, long-tail hit-rate.'

  bench_model() {
    local model="$1"
    local ok=0
    local lat_sum=0
    local out_tok_sum=0
    local reason_tok_sum=0
    local total_tok_sum=0
    local txt_len_sum=0
    local codes_json='[]'
    local errs_json='[]'

    for i in $(seq 1 "$SAMPLES"); do
      body="$(jq -nc --arg m "$model" --arg p "$PROMPT" '{
        model:$m,input:$p,max_output_tokens:320,reasoning:{effort:"'"$REASONING_EFFORT"'"},text:{verbosity:"high"}
      }')"
      IFS=$'\t' read -r code latency body_file < <(post_json "$RESPONSES_URL" "$RELAY_API_KEY" "$body")
      codes_json="$(jq -c --arg c "$code" '. + [$c]' <<< "$codes_json")"
      if [[ "$code" == "200" ]]; then
        ok=$((ok+1))
        lat_sum=$((lat_sum+latency))
        out_tok="$(jq -r '.usage.output_tokens // 0' "$body_file" 2>/dev/null || echo 0)"
        reason_tok="$(jq -r '.usage.output_tokens_details.reasoning_tokens // 0' "$body_file" 2>/dev/null || echo 0)"
        total_tok="$(jq -r '.usage.total_tokens // 0' "$body_file" 2>/dev/null || echo 0)"
        txt_len="$(jq -r '(.output_text // ([.output[]?.content[]?.text // ""] | join("\n"))) | tostring | length' "$body_file" 2>/dev/null || echo 0)"
        out_tok_sum=$((out_tok_sum+out_tok))
        reason_tok_sum=$((reason_tok_sum+reason_tok))
        total_tok_sum=$((total_tok_sum+total_tok))
        txt_len_sum=$((txt_len_sum+txt_len))
      else
        em="$(jq -r '.error.message // .message // ""' "$body_file" 2>/dev/null || true)"
        errs_json="$(jq -c --arg e "$em" '. + [$e]' <<< "$errs_json")"
      fi
      rm -f "$body_file"
    done

    bad_body="$(jq -nc --arg m "$model" '{model:$m,input:"OK",max_output_tokens:16,reasoning:{effort:"ultra"}}')"
    IFS=$'\t' read -r bad_code _ bad_file < <(post_json "$RESPONSES_URL" "$RELAY_API_KEY" "$bad_body")
    bad_msg="$(jq -r '.error.message // .message // ""' "$bad_file" 2>/dev/null || true)"
    bad_enum_ok=0
    if [[ "$bad_code" =~ ^(400|422)$ ]] && echo "$bad_msg" | rg -q 'Supported values are|reasoning\.effort|invalid_value'; then
      bad_enum_ok=1
    fi
    rm -f "$bad_file"

    avg_latency=0; avg_output=0; avg_reason=0; avg_total=0; avg_text_len=0; reason_ratio="0.000"
    if [[ "$ok" -gt 0 ]]; then
      avg_latency=$((lat_sum/ok))
      avg_output=$((out_tok_sum/ok))
      avg_reason=$((reason_tok_sum/ok))
      avg_total=$((total_tok_sum/ok))
      avg_text_len=$((txt_len_sum/ok))
      if [[ "$out_tok_sum" -gt 0 ]]; then
        reason_ratio="$(awk -v r="$reason_tok_sum" -v o="$out_tok_sum" 'BEGIN{printf "%.3f", r/o}')"
      fi
    fi

    jq -nc \
      --arg model "$model" \
      --argjson success_runs "$ok" \
      --argjson total_runs "$SAMPLES" \
      --argjson avg_latency_ms "$avg_latency" \
      --argjson avg_output_tokens "$avg_output" \
      --argjson avg_reasoning_tokens "$avg_reason" \
      --argjson avg_total_tokens "$avg_total" \
      --argjson avg_text_len "$avg_text_len" \
      --arg reasoning_to_output_ratio "$reason_ratio" \
      --argjson invalid_param_enum_check "$bad_enum_ok" \
      --argjson run_http_codes "$codes_json" \
      --argjson run_error_messages "$errs_json" \
      '{
        model:$model,
        success_runs:$success_runs,
        total_runs:$total_runs,
        avg_latency_ms:$avg_latency_ms,
        avg_output_tokens:$avg_output_tokens,
        avg_reasoning_tokens:$avg_reasoning_tokens,
        avg_total_tokens:$avg_total_tokens,
        avg_text_len:$avg_text_len,
        reasoning_to_output_ratio:$reasoning_to_output_ratio,
        invalid_param_enum_check:$invalid_param_enum_check,
        run_http_codes:$run_http_codes,
        run_error_messages:$run_error_messages
      }'
  }

  rows='[]'
  for m in "${MODELS[@]}"; do
    row="$(bench_model "$m")"
    rows="$(jq -c --argjson row "$row" '. + [$row]' <<< "$rows")"
  done

  baseline_row="$(jq -c --arg b "$MODEL_BASELINE" '.[] | select(.model == $b)' <<< "$rows")"
  if [[ -z "$baseline_row" ]]; then
    echo "[error] baseline model not found in --models: $MODEL_BASELINE" >&2
    exit 1
  fi

  rows_with_similarity="$(jq -c \
    --argjson base "$baseline_row" '
    map(
      . as $r
      | ($base.avg_output_tokens // 0) as $b_out
      | ($base.avg_reasoning_tokens // 0) as $b_reason
      | ($base.reasoning_to_output_ratio | tonumber) as $b_ratio
      | ($r.reasoning_to_output_ratio | tonumber) as $r_ratio
      | (if $b_out > 0 then ((($r.avg_output_tokens - $b_out)|if .<0 then -. else . end)/$b_out) else 1 end) as $out_delta
      | (if $b_reason > 0 then ((($r.avg_reasoning_tokens - $b_reason)|if .<0 then -. else . end)/$b_reason) else 1 end) as $reason_delta
      | ((($r_ratio - $b_ratio)|if .<0 then -. else . end)) as $ratio_delta
      | . + { baseline_similarity: {
          baseline_model: $base.model,
          output_token_delta_pct: ($out_delta*100),
          reasoning_token_delta_pct: ($reason_delta*100),
          ratio_delta_abs: $ratio_delta,
          mini_like_similarity: (($out_delta<=0.25) and ($reason_delta<=0.30) and ($ratio_delta<=0.12))
        }}
    )' <<< "$rows")"

  jq -n \
    --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg mode "$MODE" \
    --arg endpoint "$SANITIZED_ENDPOINT" \
    --arg baseline_model "$MODEL_BASELINE" \
    --arg prompt "$PROMPT" \
    --argjson gpt55_probe "$(cat "$probe_json_tmp")" \
    --argjson model_results "$rows_with_similarity" \
    '{
      timestamp:$timestamp,
      report_type:"api_quality_and_model_integrity",
      mode:$mode,
      sanitized:true,
      notes:"No API keys/tokens/trace IDs included.",
      target:{
        endpoint:$endpoint,
        baseline_model:$baseline_model,
        samples_per_model:($model_results[0].total_runs // 0),
        prompt:$prompt
      },
      gpt55_authenticity_probe:$gpt55_probe,
      model_results:$model_results
    }' > "$JSON_OUT"

  jq -r '
    . as $root
    | ([
      "# API Quality Full Report (Sanitized)",
      "",
      "- Endpoint: `" + $root.target.endpoint + "`",
      "- Baseline model: `" + $root.target.baseline_model + "`",
      "- Samples/model: " + ($root.target.samples_per_model|tostring),
      "- GPT-5.5 probe verdict: `" + $root.gpt55_authenticity_probe.scoring.verdict + "` (" + ($root.gpt55_authenticity_probe.scoring.score|tostring) + "/100)",
      "",
      "## Model Fingerprint",
      "",
      "| Model | Success | Avg latency(ms) | Avg output tok | Avg reasoning tok | Ratio(reason/output) | Mini-like? |",
      "|---|---:|---:|---:|---:|---:|---|"
    ]
    + (
      $root.model_results
      | map(
          "| `" + .model + "` | " +
          ((.success_runs|tostring)+"/"+(.total_runs|tostring)) + " | " +
          (.avg_latency_ms|tostring) + " | " +
          (.avg_output_tokens|tostring) + " | " +
          (.avg_reasoning_tokens|tostring) + " | " +
          (.reasoning_to_output_ratio|tostring) + " | " +
          (if .baseline_similarity.mini_like_similarity then "yes" else "no" end) + " |"
        )
    )
    + [
      "",
      "## Notes",
      "",
      "- Behavioral evidence, not cryptographic identity proof.",
      "- For pricing trust, combine with billing export reconciliation."
    ]) | join("\n")
  ' "$JSON_OUT" > "$MD_OUT"

  rm -f "$probe_json_tmp"
fi

echo "json_report=$JSON_OUT"
echo "md_report=$MD_OUT"
