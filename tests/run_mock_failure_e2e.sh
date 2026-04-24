#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BASE_PORT="${MOCK_FAILURE_BASE_PORT:-8860}"
TMP_DIR="$(mktemp -d)"
SERVER_PID=""

cleanup() {
  if [[ -n "$SERVER_PID" ]] && kill -0 "$SERVER_PID" >/dev/null 2>&1; then
    kill "$SERVER_PID" >/dev/null 2>&1 || true
    wait "$SERVER_PID" >/dev/null 2>&1 || true
  fi
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "[error] missing command: $1" >&2
    exit 1
  fi
}

stop_server() {
  if [[ -n "$SERVER_PID" ]] && kill -0 "$SERVER_PID" >/dev/null 2>&1; then
    kill "$SERVER_PID" >/dev/null 2>&1 || true
    wait "$SERVER_PID" >/dev/null 2>&1 || true
  fi
  SERVER_PID=""
}

start_server() {
  local mode="$1"
  local port="$2"
  local log_file="$TMP_DIR/${mode}.log"
  MOCK_RESPONSES_MODE="$mode" python3 "$ROOT/tests/mock_responses_api.py" "$port" >"$log_file" 2>&1 &
  SERVER_PID="$!"

  for _ in $(seq 1 30); do
    if curl -fsS "http://127.0.0.1:${port}/health" >/dev/null 2>&1; then
      return
    fi
    sleep 0.2
  done

  echo "[error] mock server did not start for mode=$mode" >&2
  cat "$log_file" >&2 || true
  exit 1
}

run_quick() {
  local mode="$1"
  local port="$2"
  local out_dir="$TMP_DIR/out-${mode}"
  local stdout_file="$TMP_DIR/${mode}.stdout"
  local stderr_file="$TMP_DIR/${mode}.stderr"
  mkdir -p "$out_dir"
  if ! bash "$ROOT/check-api-quality-and-model-integrity.sh" \
    --mode quick \
    --relay-base-url "http://127.0.0.1:${port}/v1" \
    --relay-api-key "test_mock_key" \
    --out-dir "$out_dir" \
    --connect-timeout 1 \
    --max-time 2 \
    --retries 0 >"$stdout_file" 2>"$stderr_file"; then
    cat "$stderr_file" >&2 || true
    return 1
  fi
  awk -F= '/^json_report=/{print $2}' "$stdout_file"
}

require_cmd python3
require_cmd curl
require_cmd jq

mode_index=0
for mode in server_error malformed_json missing_usage model_mismatch timeout; do
  port=$((BASE_PORT + mode_index))
  mode_index=$((mode_index + 1))
  start_server "$mode" "$port"
  report="$(run_quick "$mode" "$port")"
  stop_server

  jq -e '.target.endpoint == "<redacted-endpoint>"' "$report" >/dev/null
  jq -e '.quick_assessment.verdict == "suspicious_or_unstable" or .quick_assessment.confidence != "high"' "$report" >/dev/null
  jq -e '.quick_assessment.evidence | length >= 4' "$report" >/dev/null
  jq -e '.quick_assessment.warnings | length >= 1' "$report" >/dev/null
  jq -e '.quick_assessment.failed_controls | length >= 1' "$report" >/dev/null
done

echo "mock-failure-e2e: ok"
