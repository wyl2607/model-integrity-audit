#!/usr/bin/env bash
set -euo pipefail

SCRIPT_NAME="$(basename "$0")"

MODEL="gpt-5.5"
SAMPLES=6
REASONING_EFFORT="medium"
CONFIG_FILE="${CODEX_CLI_CONFIG:-$HOME/.codex/config.toml}"
RELAY_BASE_URL=""
RELAY_API_KEY=""
OPENAI_BASE_URL="https://api.openai.com/v1"
OPENAI_API_KEY="${OFFICIAL_OPENAI_API_KEY:-}"
OUT_FILE=""

usage() {
  cat <<'EOF'
Probe whether a relay route for gpt-5.5 behaves like a real OpenAI GPT Responses endpoint.

Usage:
  probe-gpt55-authenticity.sh [options]

Options:
  --model <id>               Model id to probe (default: gpt-5.5)
  --samples <n>              Number of stability probes (default: 6)
  --reasoning-effort <lvl>   Reasoning effort for positive probes (default: medium)
  --config <path>            Codex CLI config path (default: ~/.codex/config.toml)
  --relay-base-url <url>     Relay base URL (default: derive from config model_provider base_url)
  --relay-api-key <key>      Relay API key (default: derive from config env_key env var)
  --openai-base-url <url>    Official base URL (default: https://api.openai.com/v1)
  --openai-api-key <key>     Official OpenAI key for optional A/B compare
  --out <path>               Output JSON report path (default: ./gpt55-probe-report-<ts>.json)
  -h, --help                 Show help

Environment:
  OFFICIAL_OPENAI_API_KEY    Optional official key for cross-check
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

now_ms() {
  perl -MTime::HiRes=time -e 'printf("%.0f\n", time()*1000)'
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

post_json() {
  local url="$1"
  local api_key="$2"
  local body="$3"
  local body_file header_file code start end latency
  body_file="$(mktemp)"
  header_file="$(mktemp)"
  start="$(now_ms)"
  code="$(curl -sS -o "$body_file" -D "$header_file" -w '%{http_code}' "$url" \
    -H "Authorization: Bearer $api_key" \
    -H "Content-Type: application/json" \
    -d "$body")" || code="000"
  end="$(now_ms)"
  latency="$((end - start))"
  printf '%s\t%s\t%s\t%s\n' "$code" "$latency" "$body_file" "$header_file"
}

to_bool() {
  if [[ "$1" == "1" ]]; then
    echo "true"
  else
    echo "false"
  fi
}

passfail() {
  if [[ "$1" == "1" ]]; then
    echo "PASS"
  else
    echo "FAIL"
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --model) MODEL="$2"; shift 2 ;;
    --samples) SAMPLES="$2"; shift 2 ;;
    --reasoning-effort) REASONING_EFFORT="$2"; shift 2 ;;
    --config) CONFIG_FILE="$2"; shift 2 ;;
    --relay-base-url) RELAY_BASE_URL="$2"; shift 2 ;;
    --relay-api-key) RELAY_API_KEY="$2"; shift 2 ;;
    --openai-base-url) OPENAI_BASE_URL="$2"; shift 2 ;;
    --openai-api-key) OPENAI_API_KEY="$2"; shift 2 ;;
    --out) OUT_FILE="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *)
      echo "[error] unknown argument: $1" >&2
      usage
      exit 1
      ;;
  esac
done

require_cmds curl jq rg awk sed perl

if [[ -z "$RELAY_BASE_URL" ]]; then
  if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "[error] config file not found: $CONFIG_FILE" >&2
    exit 1
  fi
  provider="$(extract_root_value "$CONFIG_FILE" "model_provider")"
  if [[ -z "$provider" ]]; then
    provider="codex"
  fi
  RELAY_BASE_URL="$(extract_provider_value "$CONFIG_FILE" "$provider" "base_url")"
  env_key="$(extract_provider_value "$CONFIG_FILE" "$provider" "env_key")"
  if [[ -z "$RELAY_API_KEY" && -n "$env_key" ]]; then
    RELAY_API_KEY="$(printenv "$env_key" || true)"
  fi
fi

if [[ -z "$RELAY_API_KEY" ]]; then
  RELAY_API_KEY="${OPENAI_API_KEY:-}"
fi

if [[ -z "$RELAY_BASE_URL" ]]; then
  echo "[error] relay base url is empty. set --relay-base-url or configure base_url in $CONFIG_FILE" >&2
  exit 1
fi

if [[ -z "$RELAY_API_KEY" ]]; then
  echo "[error] relay api key is empty. set --relay-api-key or export the env_key from config" >&2
  exit 1
fi

if ! [[ "$SAMPLES" =~ ^[0-9]+$ ]] || [[ "$SAMPLES" -lt 1 ]]; then
  echo "[error] --samples must be a positive integer" >&2
  exit 1
fi

if ! [[ "$REASONING_EFFORT" =~ ^(none|minimal|low|medium|high|xhigh)$ ]]; then
  echo "[error] --reasoning-effort must be one of: none|minimal|low|medium|high|xhigh" >&2
  exit 1
fi

if [[ -z "$OUT_FILE" ]]; then
  OUT_FILE="$PWD/gpt55-probe-report-$(date -u +%Y%m%dT%H%M%SZ).json"
fi

RESPONSES_URL="${RELAY_BASE_URL%/}/responses"
OPENAI_RESPONSES_URL="${OPENAI_BASE_URL%/}/responses"
ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

score=0

valid_body="$(jq -nc --arg model "$MODEL" '{
  model: $model,
  input: "Return exactly: OK",
  max_output_tokens: 16,
  reasoning: {effort: "'"$REASONING_EFFORT"'"},
  text: {verbosity: "low"}
}')"

IFS=$'\t' read -r valid_code valid_latency valid_body_file valid_hdr_file < <(post_json "$RESPONSES_URL" "$RELAY_API_KEY" "$valid_body")

valid_http_ok=0
if [[ "$valid_code" == "200" ]]; then
  valid_http_ok=1
  score=$((score + 20))
fi

valid_model_match=0
if jq -e --arg model "$MODEL" '.model == $model' "$valid_body_file" >/dev/null 2>&1; then
  valid_model_match=1
  score=$((score + 15))
fi

valid_id_shape=0
if jq -e '.id | type == "string" and startswith("resp_")' "$valid_body_file" >/dev/null 2>&1; then
  valid_id_shape=1
  score=$((score + 10))
fi

invalid_param_body="$(jq -nc --arg model "$MODEL" '{
  model: $model,
  input: "OK",
  max_output_tokens: 8,
  reasoning: {effort: "ultra"}
}')"

IFS=$'\t' read -r bad_code bad_latency bad_body_file bad_hdr_file < <(post_json "$RESPONSES_URL" "$RELAY_API_KEY" "$invalid_param_body")

bad_msg="$(jq -r '.error.message // .message // ""' "$bad_body_file" 2>/dev/null || true)"
invalid_param_ok=0
if [[ "$bad_code" =~ ^(400|422)$ ]] && echo "$bad_msg" | rg -q 'reasoning\.effort|invalid_value|Supported values are'; then
  invalid_param_ok=1
  score=$((score + 20))
fi

unsupported_model="gpt-5.5-probe-invalid"
unsupported_body="$(jq -nc --arg model "$unsupported_model" '{
  model: $model,
  input: "ping",
  max_output_tokens: 8
}')"

IFS=$'\t' read -r miss_code miss_latency miss_body_file miss_hdr_file < <(post_json "$RESPONSES_URL" "$RELAY_API_KEY" "$unsupported_body")

miss_msg="$(jq -r '.error.message // .message // ""' "$miss_body_file" 2>/dev/null || true)"
unsupported_model_rejected=0
if [[ "$miss_code" != "200" ]] && echo "$miss_msg" | rg -qi '不存在|not exist|not found|unknown model|model'; then
  unsupported_model_rejected=1
  score=$((score + 10))
fi

sample_success=0
reasoning_seen=0
latency_total=0

for i in $(seq 1 "$SAMPLES"); do
  probe_body="$(jq -nc --arg model "$MODEL" --arg nonce "probe-$i-$(date +%s)" '{
    model: $model,
    input: ("Return exactly: OK " + $nonce),
    max_output_tokens: 16,
    reasoning: {effort: "'"$REASONING_EFFORT"'"},
    text: {verbosity: "low"}
  }')"
  IFS=$'\t' read -r p_code p_latency p_body_file p_hdr_file < <(post_json "$RESPONSES_URL" "$RELAY_API_KEY" "$probe_body")
  latency_total=$((latency_total + p_latency))

  if [[ "$p_code" == "200" ]] && jq -e --arg model "$MODEL" '.model == $model' "$p_body_file" >/dev/null 2>&1; then
    sample_success=$((sample_success + 1))
    if jq -e '.usage.output_tokens_details.reasoning_tokens // -1 | tonumber >= 0' "$p_body_file" >/dev/null 2>&1; then
      reasoning_seen=$((reasoning_seen + 1))
    fi
  fi

  rm -f "$p_body_file" "$p_hdr_file"
done

sample_ratio="$(awk -v ok="$sample_success" -v n="$SAMPLES" 'BEGIN { if (n==0) printf "0.000"; else printf "%.3f", ok/n }')"
reasoning_ratio="$(awk -v seen="$reasoning_seen" -v ok="$sample_success" 'BEGIN { if (ok==0) printf "0.000"; else printf "%.3f", seen/ok }')"
avg_latency_ms="$(awk -v t="$latency_total" -v n="$SAMPLES" 'BEGIN { if (n==0) printf "0"; else printf "%.0f", t/n }')"

if awk -v r="$sample_ratio" 'BEGIN { exit !(r >= 0.90) }'; then
  score=$((score + 20))
elif awk -v r="$sample_ratio" 'BEGIN { exit !(r >= 0.70) }'; then
  score=$((score + 10))
fi

if awk -v r="$reasoning_ratio" 'BEGIN { exit !(r >= 0.70) }'; then
  score=$((score + 5))
fi

official_compare_enabled=0
official_valid_code=""
official_bad_code=""
official_valid_match=0
official_bad_match=0
official_compare_score=0
official_compare_note="official key not provided"

if [[ -n "$OPENAI_API_KEY" ]]; then
  official_compare_enabled=1
  IFS=$'\t' read -r official_valid_code _ official_valid_body_file official_valid_hdr_file < <(post_json "$OPENAI_RESPONSES_URL" "$OPENAI_API_KEY" "$valid_body")
  IFS=$'\t' read -r official_bad_code _ official_bad_body_file official_bad_hdr_file < <(post_json "$OPENAI_RESPONSES_URL" "$OPENAI_API_KEY" "$invalid_param_body")

  if [[ "$valid_code" == "$official_valid_code" ]]; then
    official_valid_match=1
    official_compare_score=$((official_compare_score + 10))
  fi

  official_bad_msg="$(jq -r '.error.message // .message // ""' "$official_bad_body_file" 2>/dev/null || true)"
  if [[ "$official_bad_code" =~ ^(400|422)$ ]] && echo "$official_bad_msg" | rg -q 'reasoning\.effort|invalid_value|Supported values are'; then
    official_bad_match=1
    official_compare_score=$((official_compare_score + 10))
  fi

  official_compare_note="official compare attempted"
  rm -f "$official_valid_body_file" "$official_valid_hdr_file" "$official_bad_body_file" "$official_bad_hdr_file"
fi

confidence="low"
if [[ "$score" -ge 85 ]]; then
  confidence="high"
elif [[ "$score" -ge 65 ]]; then
  confidence="medium"
fi

verdict="inconclusive_or_suspicious"
if [[ "$valid_http_ok" -eq 1 && "$valid_model_match" -eq 1 && "$invalid_param_ok" -eq 1 && "$unsupported_model_rejected" -eq 1 ]]; then
  if awk -v r="$sample_ratio" 'BEGIN { exit !(r >= 0.80) }'; then
    verdict="likely_real_openai_gpt_route"
  fi
fi

jq -n \
  --arg timestamp "$ts" \
  --arg relay_base_url "$RELAY_BASE_URL" \
  --arg responses_url "$RESPONSES_URL" \
  --arg model "$MODEL" \
  --argjson samples "$SAMPLES" \
  --argjson score "$score" \
  --arg confidence "$confidence" \
  --arg verdict "$verdict" \
  --argjson valid_http_ok "$(to_bool "$valid_http_ok")" \
  --argjson valid_model_match "$(to_bool "$valid_model_match")" \
  --argjson valid_id_shape "$(to_bool "$valid_id_shape")" \
  --argjson invalid_param_ok "$(to_bool "$invalid_param_ok")" \
  --argjson unsupported_model_rejected "$(to_bool "$unsupported_model_rejected")" \
  --argjson sample_success "$sample_success" \
  --argjson reasoning_seen "$reasoning_seen" \
  --argjson sample_ratio "$sample_ratio" \
  --argjson reasoning_ratio "$reasoning_ratio" \
  --argjson avg_latency_ms "$avg_latency_ms" \
  --argjson official_compare_enabled "$(to_bool "$official_compare_enabled")" \
  --arg official_base_url "$OPENAI_BASE_URL" \
  --arg official_valid_code "$official_valid_code" \
  --arg official_bad_code "$official_bad_code" \
  --argjson official_valid_match "$(to_bool "$official_valid_match")" \
  --argjson official_bad_match "$(to_bool "$official_bad_match")" \
  --argjson official_compare_score "$official_compare_score" \
  --arg official_compare_note "$official_compare_note" \
  '{
    timestamp: $timestamp,
    probe: "gpt55-authenticity",
    relay: {
      base_url: $relay_base_url,
      responses_url: $responses_url,
      model: $model
    },
    checks: {
      valid_http_ok: $valid_http_ok,
      valid_model_match: $valid_model_match,
      valid_id_shape: $valid_id_shape,
      invalid_param_ok: $invalid_param_ok,
      unsupported_model_rejected: $unsupported_model_rejected
    },
    sampling: {
      samples: $samples,
      success: $sample_success,
      sample_ratio: $sample_ratio,
      reasoning_seen: $reasoning_seen,
      reasoning_ratio: $reasoning_ratio,
      avg_latency_ms: $avg_latency_ms
    },
    scoring: {
      score: $score,
      confidence: $confidence,
      verdict: $verdict
    },
    official_compare: {
      enabled: $official_compare_enabled,
      base_url: $official_base_url,
      valid_code: $official_valid_code,
      bad_param_code: $official_bad_code,
      valid_code_match_with_relay: $official_valid_match,
      bad_param_behavior_match: $official_bad_match,
      compare_score: $official_compare_score,
      note: $official_compare_note
    }
  }' > "$OUT_FILE"

echo "== gpt-5.5 authenticity probe =="
echo "relay responses url : $RESPONSES_URL"
echo "model               : $MODEL"
echo "valid call          : $(passfail "$valid_http_ok") (http=$valid_code)"
echo "model echo          : $(passfail "$valid_model_match")"
echo "id shape            : $(passfail "$valid_id_shape")"
echo "bad param check     : $(passfail "$invalid_param_ok") (http=$bad_code)"
echo "invalid model check : $(passfail "$unsupported_model_rejected") (http=$miss_code)"
echo "sample success      : $sample_success/$SAMPLES (ratio=$sample_ratio, avg_latency_ms=$avg_latency_ms)"
echo "reasoning seen      : $reasoning_seen/$sample_success (ratio=$reasoning_ratio)"
echo "score               : $score/100 ($confidence)"
echo "verdict             : $verdict"
echo "report              : $OUT_FILE"

rm -f "$valid_body_file" "$valid_hdr_file" "$bad_body_file" "$bad_hdr_file" "$miss_body_file" "$miss_hdr_file"
