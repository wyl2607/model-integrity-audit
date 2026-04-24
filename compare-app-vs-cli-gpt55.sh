#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT_DIR="${1:-$SCRIPT_DIR/reports}"
mkdir -p "$OUT_DIR"
TS="$(date -u +%Y%m%dT%H%M%SZ)"
OUT_JSON="$OUT_DIR/app-vs-cli-gpt55-${TS}.json"
OUT_MD="$OUT_DIR/app-vs-cli-gpt55-${TS}.md"

run_route() {
  local route="$1"
  local codex_home="$2"
  local json_file msg_file start end elapsed rc
  json_file="$(mktemp)"
  msg_file="$(mktemp)"
  start=$(perl -MTime::HiRes=time -e 'printf("%.0f", time()*1000)')
  set +e
  CODEX_HOME="$codex_home" codex exec \
    --skip-git-repo-check \
    --json \
    --output-last-message "$msg_file" \
    "Return strict JSON with keys route,ok,notes. route must be \"$route\". Keep notes under 12 words." > "$json_file" 2>&1
  rc=$?
  set -e
  end=$(perl -MTime::HiRes=time -e 'printf("%.0f", time()*1000)')
  elapsed=$((end-start))

  # Try to infer model + usage from event stream when present
  model="$(rg -o '"model":"[^"]+"' "$json_file" | head -n1 | sed -E 's/.*"model":"([^"]+)".*/\1/' || true)"
  usage_line="$(rg -o '"usage":\\{[^\\}]+\\}' "$json_file" | tail -n1 || true)"

  jq -nc \
    --arg route "$route" \
    --arg codex_home "$codex_home" \
    --argjson exit_code "$rc" \
    --argjson elapsed_ms "$elapsed" \
    --arg model "${model:-}" \
    --arg usage "${usage_line:-}" \
    --arg output "$(cat "$msg_file" 2>/dev/null || true)" \
    --arg logs_tail "$(tail -n 80 "$json_file" | tr '\n' '\r')" \
    '{
      route:$route,
      codex_home:$codex_home,
      exit_code:$exit_code,
      elapsed_ms:$elapsed_ms,
      model_hint:$model,
      usage_hint:$usage,
      output_last_message:$output,
      logs_tail_crlf:$logs_tail
    }'

  rm -f "$json_file" "$msg_file"
}

app_row="$(run_route "app" "$HOME/.codex-desktop")"
cli_row="$(run_route "cli" "$HOME/.codex")"

jq -n \
  --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --argjson app "$app_row" \
  --argjson cli "$cli_row" \
  '{
    timestamp:$timestamp,
    report_type:"app_vs_cli_gpt55",
    sanitized:true,
    app:$app,
    cli:$cli
  }' > "$OUT_JSON"

jq -r '
  [
    "# App vs CLI gpt-5.5 Compare (Sanitized)",
    "",
    "| Route | Exit | Elapsed(ms) | Model hint |",
    "|---|---:|---:|---|",
    "| app | " + (.app.exit_code|tostring) + " | " + (.app.elapsed_ms|tostring) + " | " + ((.app.model_hint // "")|tostring) + " |",
    "| cli | " + (.cli.exit_code|tostring) + " | " + (.cli.elapsed_ms|tostring) + " | " + ((.cli.model_hint // "")|tostring) + " |",
    "",
    "## App last message",
    "",
    "```text",
    (.app.output_last_message // ""),
    "```",
    "",
    "## CLI last message",
    "",
    "```text",
    (.cli.output_last_message // ""),
    "```",
    "",
    "## Notes",
    "",
    "- If app route fails with network/backend errors, compare cannot be completed in current environment.",
    "- Use JSON file for raw sanitized logs tail."
  ] | join("\n")
' "$OUT_JSON" > "$OUT_MD"

echo "json_report=$OUT_JSON"
echo "md_report=$OUT_MD"
