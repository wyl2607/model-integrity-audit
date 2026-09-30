#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PORT="${MOCK_RESPONSES_FULL_PORT:-8766}"
BASE_URL="http://127.0.0.1:${PORT}/v1"
OUT_DIR="${ROOT}/reports/mock-full-e2e"
LOG_FILE="$(mktemp)"
FULL_STDOUT="$(mktemp)"
SERVER_PID=""

cleanup() {
  if [[ -n "$SERVER_PID" ]] && kill -0 "$SERVER_PID" >/dev/null 2>&1; then
    kill "$SERVER_PID" >/dev/null 2>&1 || true
    wait "$SERVER_PID" >/dev/null 2>&1 || true
  fi
  rm -f "$LOG_FILE" "$FULL_STDOUT"
}
trap cleanup EXIT

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "[error] missing command: $1" >&2
    exit 1
  fi
}

require_cmd python3
require_cmd curl
require_cmd jq
require_cmd rg

rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR"

python3 "$ROOT/tests/mock_responses_api.py" "$PORT" >"$LOG_FILE" 2>&1 &
SERVER_PID="$!"

for _ in $(seq 1 30); do
  if curl -fsS "http://127.0.0.1:${PORT}/health" >/dev/null 2>&1; then
    break
  fi
  sleep 0.2
done

if ! curl -fsS "http://127.0.0.1:${PORT}/health" >/dev/null 2>&1; then
  echo "[error] mock server did not start" >&2
  cat "$LOG_FILE" >&2 || true
  exit 1
fi

audit_exit_code=0
bash "$ROOT/check-api-quality-and-model-integrity.sh" \
  --mode full \
  --relay-base-url "$BASE_URL" \
  --relay-api-key "test_mock_key" \
  --models "gpt-5.5 gpt-5.6-luna" \
  --baseline "gpt-5.6-luna" \
  --samples 2 \
  --out-dir "$OUT_DIR" \
  --connect-timeout 2 \
  --max-time 10 \
  --retries 0 >"$FULL_STDOUT" 2>&1 || audit_exit_code=$?

if [[ "$audit_exit_code" -ne 0 ]]; then
  echo "[error] check-api-quality-and-model-integrity.sh exited with code $audit_exit_code (expected 0)" >&2
  cat "$FULL_STDOUT" >&2 || true
  exit 1
fi

full_json="$(awk -F= '/^json_report=/{print $2}' "$FULL_STDOUT")"
full_md="${full_json%.json}.md"

if [[ -z "$full_json" || ! -f "$full_json" ]]; then
  echo "[error] JSON report was not generated" >&2
  cat "$FULL_STDOUT" >&2 || true
  exit 1
fi

test -s "$full_json"
test -s "$full_md"

jq -e '.target | type == "object"' "$full_json" >/dev/null
jq -e '.target.endpoint == "<redacted-endpoint>"' "$full_json" >/dev/null
jq -e '.target.baseline_model == "gpt-5.6-luna"' "$full_json" >/dev/null
jq -e '.target.samples_per_model == 2' "$full_json" >/dev/null
jq -e '.mode == "full"' "$full_json" >/dev/null
jq -e '.report_type == "api_quality_and_model_integrity"' "$full_json" >/dev/null
jq -e '.sanitized == true' "$full_json" >/dev/null

jq -e '.gpt55_authenticity_probe | type == "object"' "$full_json" >/dev/null
jq -e '.gpt55_authenticity_probe.scoring.verdict == "likely_real_openai_gpt_route"' "$full_json" >/dev/null
jq -e '.gpt55_authenticity_probe.scoring.score >= 75' "$full_json" >/dev/null
jq -e '.gpt55_authenticity_probe.scoring.confidence == "high"' "$full_json" >/dev/null

jq -e '.model_results | type == "array" and length == 2' "$full_json" >/dev/null
jq -e 'all(.model_results[]; .model and .success_runs == .total_runs and .total_runs == 2 and .avg_total_tokens > 0 and .invalid_param_enum_check == 1 and .baseline_similarity.baseline_model == "gpt-5.6-luna")' "$full_json" >/dev/null
jq -e '[.model_results[] | select(.model == "gpt-5.5" and .success_runs == 2 and .baseline_similarity.mini_like_similarity == false)] | length == 1' "$full_json" >/dev/null
jq -e '[.model_results[] | select(.model == "gpt-5.6-luna" and .success_runs == 2 and .baseline_similarity.mini_like_similarity == true)] | length == 1' "$full_json" >/dev/null

jq -e '.evidence | type == "array" and length >= 4' "$full_json" >/dev/null
jq -e '.evidence[] | select(.check == "gpt55_probe_verdict" and .verdict == "likely_real_openai_gpt_route")' "$full_json" >/dev/null
jq -e '.evidence[] | select(.check == "model_success_rates" and .failed_model_count == 0)' "$full_json" >/dev/null
jq -e '.evidence[] | select(.check == "invalid_reasoning_param" and .failed_model_count == 0)' "$full_json" >/dev/null
jq -e '.evidence[] | select(.check == "baseline_similarity" and .mini_like_model_count == 0)' "$full_json" >/dev/null
jq -e '.warnings | type == "array" and length == 0' "$full_json" >/dev/null
jq -e '.failed_controls | type == "array" and length == 0' "$full_json" >/dev/null
jq -e '.recommendations | type == "array" and length >= 1' "$full_json" >/dev/null

! rg -q '127\.0\.0\.1|test_mock_key' "$full_json" "$full_md"

echo "mock-full-e2e: ok"
