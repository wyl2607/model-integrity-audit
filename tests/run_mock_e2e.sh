#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PORT="${MOCK_RESPONSES_PORT:-8765}"
BASE_URL="http://127.0.0.1:${PORT}/v1"
OUT_DIR="${ROOT}/reports/mock-e2e"
LOG_FILE="$(mktemp)"
QUICK_STDOUT="$(mktemp)"
PROBE_STDOUT="$(mktemp)"
SERVER_PID=""

cleanup() {
  if [[ -n "$SERVER_PID" ]] && kill -0 "$SERVER_PID" >/dev/null 2>&1; then
    kill "$SERVER_PID" >/dev/null 2>&1 || true
    wait "$SERVER_PID" >/dev/null 2>&1 || true
  fi
  rm -f "$LOG_FILE" "$QUICK_STDOUT" "$PROBE_STDOUT"
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

bash "$ROOT/check-api-quality-and-model-integrity.sh" \
  --mode quick \
  --relay-base-url "$BASE_URL" \
  --relay-api-key "test_mock_key" \
  --out-dir "$OUT_DIR" \
  --connect-timeout 2 \
  --max-time 10 \
  --retries 0 >"$QUICK_STDOUT"

quick_json="$(awk -F= '/^json_report=/{print $2}' "$QUICK_STDOUT")"

jq -e '.target.endpoint == "<redacted-endpoint>"' "$quick_json" >/dev/null
jq -e '.quick_assessment.controls.invalid_model_rejected == true' "$quick_json" >/dev/null
jq -e '.quick_assessment.controls.invalid_reasoning_param_checked == true' "$quick_json" >/dev/null
jq -e '[.quick_assessment.per_model[] | select(.http_code == "200" and .model_echo_ok == true)] | length >= 3' "$quick_json" >/dev/null

probe_json="$OUT_DIR/probe.json"
bash "$ROOT/scripts/probe-gpt55-authenticity.sh" \
  --relay-base-url "$BASE_URL" \
  --relay-api-key "test_mock_key" \
  --samples 2 \
  --out "$probe_json" \
  --connect-timeout 2 \
  --max-time 10 \
  --retries 0 >"$PROBE_STDOUT"

jq -e '.relay.responses_url == "<redacted-endpoint>"' "$probe_json" >/dev/null
jq -e '.checks.valid_http_ok == true' "$probe_json" >/dev/null
jq -e '.checks.invalid_param_ok == true' "$probe_json" >/dev/null
jq -e '.checks.unsupported_model_rejected == true' "$probe_json" >/dev/null

echo "mock-e2e: ok"
