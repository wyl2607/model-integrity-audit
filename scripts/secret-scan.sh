#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$ROOT"

patterns=(
  'sk-[A-Za-z0-9_-]{20,}'
  'Bearer[[:space:]]+[A-Za-z0-9._-]{20,}'
  'relay\.nf\.video'
  'trace_id[[:space:]]*[:=][[:space:]]*["'"'"']?[A-Za-z0-9._-]{8,}'
  '(OPENAI_API_KEY|RELAY_API_KEY|OFFICIAL_OPENAI_API_KEY)[[:space:]]*=[[:space:]]*["'"'"']?(?!your_|\$\{)[^"'"'"'[:space:]$][^"'"'"'[:space:]]{8,}'
)

tracked_re=''
for pattern in "${patterns[@]}"; do
  if [[ -z "$tracked_re" ]]; then
    tracked_re="$pattern"
  else
    tracked_re="$tracked_re|$pattern"
  fi
done

failed=0

if git grep -n -I -P "$tracked_re" -- . ':!scripts/secret-scan.sh' ':!scripts/secret-scan.ps1'; then
  echo "[error] possible secret or private endpoint found in tracked files" >&2
  failed=1
fi

if git ls-files --error-unmatch reports .env .env.local .env.production >/dev/null 2>&1; then
  echo "[error] sensitive local files are tracked by Git" >&2
  git ls-files reports .env .env.local .env.production >&2 || true
  failed=1
fi

if [[ "$failed" -ne 0 ]]; then
  exit 1
fi

echo "secret-scan: ok"
