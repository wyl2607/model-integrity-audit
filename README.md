# Model Integrity Audit

Language: English | [中文](README.zh-CN.md) | [Deutsch](README.de.md)

Model Integrity Audit is a reusable command-line toolkit for testing whether an OpenAI Responses API-compatible endpoint behaves as expected. It runs repeatable API quality checks, model-route integrity probes, negative controls, and model fingerprint comparisons, then writes sanitized JSON and Markdown reports.

The project is designed for common Windows, macOS, and Linux environments. It never needs real credentials in the repository. Use environment variables, a local `.env`, or command-line arguments at runtime.

## What It Checks

- Whether the endpoint accepts valid Responses API requests.
- Whether the returned `model` field matches the requested model.
- Whether invalid model names are rejected.
- Whether invalid `reasoning.effort` values are rejected with validation-style errors.
- Whether `gpt-5.5` looks suspiciously similar to a baseline model by token and behavior fingerprints.
- Whether App and CLI Codex routes appear to use the same model path, when Codex CLI is available.

## Modes

- `quick`: A fast 10-30 second confidence check for common API and model-route issues.
- `full`: A deeper multi-sample fingerprint audit across one or more models.

## Repository Layout

- `check-api-quality-and-model-integrity.sh`: Main Bash entrypoint for `quick` and `full` audits.
- `check-api-quality-and-model-integrity.ps1`: Windows PowerShell wrapper for the main audit.
- `scripts/probe-gpt55-authenticity.sh`: Focused `gpt-5.5` authenticity probe.
- `scripts/probe-gpt55-authenticity.ps1`: Windows PowerShell wrapper for the focused probe.
- `compare-app-vs-cli-gpt55.sh`: Optional App vs CLI Codex route comparison.
- `compare-app-vs-cli-gpt55.ps1`: Windows PowerShell wrapper for App vs CLI comparison.
- `docs/report-schema.md`: JSON report field contract and consumer guidance.
- `docs/model-integrity-methodology.md`: Explanation of model integrity controls and limitations.
- `examples/reports/`: Sanitized example reports for quick review and downstream integration.
- `.env.example`: Safe placeholder environment template.
- `reports/`: Local output directory, ignored by Git.

## Security Rules

- Do not commit `.env`, API keys, bearer tokens, raw traces, or generated reports.
- Generated reports are written to `reports/`, which is ignored by Git.
- The scripts sanitize report output and avoid writing API keys or bearer tokens.
- Report endpoints are redacted by default. Use `--show-endpoint` only when you intentionally want the endpoint origin in local reports.
- Run `./scripts/secret-scan.sh` or `.\scripts\secret-scan.ps1` before opening a PR.
- Use placeholder values in documentation and examples, such as `https://your-relay.example.com/v1`.
- If you publish results, review the Markdown and JSON reports first.

## Requirements

Required for the main audit:

- `bash`
- `curl`
- `jq`
- `rg` from ripgrep
- `awk`
- `sed`
- `perl`

Optional:

- `codex` CLI, only for `compare-app-vs-cli-gpt55.*`.
- An official OpenAI API key, only if you want optional relay-vs-official comparison.

## Install Dependencies

### Windows

Recommended Windows Terminal setup:

1. Install Git for Windows: `https://git-scm.com/download/win`
2. Install ripgrep and jq with Winget:

```powershell
winget install BurntSushi.ripgrep.MSVC
winget install jqlang.jq
```

3. Reopen Windows Terminal.
4. Run the PowerShell wrapper from the repository root.

Git for Windows provides `bash`, `curl`, `awk`, `sed`, and `perl` in typical installations. If a wrapper reports a missing command, install that command and reopen the terminal.

### macOS

Install dependencies with Homebrew:

```bash
brew install jq ripgrep
```

macOS already includes Bash, curl, awk, sed, and perl. You can use the system versions for this project.

### Linux

Debian or Ubuntu:

```bash
sudo apt update
sudo apt install -y bash curl jq ripgrep gawk sed perl
```

Fedora:

```bash
sudo dnf install -y bash curl jq ripgrep gawk sed perl
```

Arch Linux:

```bash
sudo pacman -S --needed bash curl jq ripgrep gawk sed perl
```

## Clone

```bash
git clone https://github.com/wyl2607/model-integrity-audit.git
cd model-integrity-audit
```

On macOS and Linux, make the scripts executable if needed:

```bash
chmod +x *.sh scripts/*.sh
```

## Configure Credentials

The safest approach is to use a local `.env` file copied from `.env.example`:

```bash
cp .env.example .env
```

Edit `.env` locally:

```bash
RELAY_BASE_URL="https://your-relay.example.com/v1"
RELAY_API_KEY="your_relay_api_key"
```

Load it on macOS or Linux:

```bash
set -a
source .env
set +a
```

Load it in PowerShell:

```powershell
$env:RELAY_BASE_URL = "https://your-relay.example.com/v1"
$env:RELAY_API_KEY = "your_relay_api_key"
```

You can also pass credentials directly at runtime:

```bash
./check-api-quality-and-model-integrity.sh --relay-base-url "https://your-relay.example.com/v1" --relay-api-key "your_relay_api_key" --mode quick
```

Avoid putting real values into shell history on shared machines.

## Quick Audit

Windows PowerShell:

```powershell
.\check-api-quality-and-model-integrity.ps1 --mode quick
```

Windows PowerShell with explicit values:

```powershell
.\check-api-quality-and-model-integrity.ps1 --mode quick --relay-base-url "https://your-relay.example.com/v1" --relay-api-key "your_relay_api_key"
```

macOS or Linux:

```bash
./check-api-quality-and-model-integrity.sh --mode quick
```

macOS or Linux with explicit values:

```bash
./check-api-quality-and-model-integrity.sh --mode quick --relay-base-url "https://your-relay.example.com/v1" --relay-api-key "your_relay_api_key"
```

Network controls are available when running against slower endpoints:

```bash
./check-api-quality-and-model-integrity.sh --mode quick --connect-timeout 10 --max-time 60 --retries 2
```

Reports redact endpoint origins by default. To include the sanitized origin in a local-only report, add `--show-endpoint`.

## Full Audit

Windows PowerShell:

```powershell
.\check-api-quality-and-model-integrity.ps1 --mode full --reasoning-effort medium --samples 5 --baseline gpt-5.4-mini --models "gpt-5.5 gpt-5.4 gpt-5.4-mini gpt-5.3-codex gpt-5.2"
```

macOS or Linux:

```bash
./check-api-quality-and-model-integrity.sh \
  --mode full \
  --reasoning-effort medium \
  --samples 5 \
  --baseline gpt-5.4-mini \
  --models "gpt-5.5 gpt-5.4 gpt-5.4-mini gpt-5.3-codex gpt-5.2"
```

## Focused GPT-5.5 Probe

Windows PowerShell:

```powershell
.\scripts\probe-gpt55-authenticity.ps1 --model gpt-5.5 --samples 6 --reasoning-effort medium
```

macOS or Linux:

```bash
./scripts/probe-gpt55-authenticity.sh --model gpt-5.5 --samples 6 --reasoning-effort medium
```

Optional official API comparison:

```bash
OFFICIAL_OPENAI_API_KEY="your_official_openai_api_key" ./scripts/probe-gpt55-authenticity.sh --model gpt-5.5
```

## App vs CLI Route Comparison

This optional script requires the Codex CLI and local Codex configuration.

Windows PowerShell:

```powershell
.\compare-app-vs-cli-gpt55.ps1
```

macOS or Linux:

```bash
./compare-app-vs-cli-gpt55.sh
```

## Output

Reports are written locally:

- `reports/api-quality-model-integrity-quick-<timestamp>.json`
- `reports/api-quality-model-integrity-quick-<timestamp>.md`
- `reports/api-quality-model-integrity-full-<timestamp>.json`
- `reports/api-quality-model-integrity-full-<timestamp>.md`
- `reports/app-vs-cli-gpt55-<timestamp>.json`
- `reports/app-vs-cli-gpt55-<timestamp>.md`

Reports are sanitized by design, but you should still review them before sharing.

Each JSON report includes explainability fields:

- `evidence`: human-readable checks with levels, messages, and supporting values.
- `warnings`: warning messages extracted from evidence.
- `failed_controls`: controls that failed or need review.
- `recommendations`: next steps based on the observed evidence.

See `docs/report-schema.md` for the JSON field contract and `examples/reports/` for sanitized report examples.

See `docs/model-integrity-methodology.md` for the reasoning behind positive controls, negative controls, model echo, usage visibility, and baseline similarity.

## Secret Scan

Before committing or sharing results, run:

```bash
./scripts/secret-scan.sh
```

Windows PowerShell:

```powershell
.\scripts\secret-scan.ps1
```

The scan checks tracked files for common API key patterns, bearer tokens, private endpoint examples, trace IDs, and accidentally tracked `.env` or `reports/` files.

## Offline Integrity Test

The repository includes a local mock Responses API so CI and contributors can test the audit flow without real API keys or real endpoints:

```bash
./tests/run_mock_e2e.sh
```

This starts `tests/mock_responses_api.py`, runs the quick audit and focused probe against `127.0.0.1`, verifies endpoint redaction, validates negative controls, and then removes the local test server.

Failure-path coverage is also available:

```bash
./tests/run_mock_failure_e2e.sh
```

This verifies that server errors, malformed JSON, missing usage data, model mismatches, and slow responses produce warnings or failed controls instead of high-confidence success.

## Interpreting Results

- `likely_real_gpt55_route`: The route passed the implemented behavioral checks.
- `suspicious_or_unstable`: The route failed important checks or looked unstable.
- `inconclusive`: There was not enough evidence to make a stronger call.

Use `verdict`, `score`, `warnings`, and `failed_controls` together. A high score means the endpoint behavior matched the implemented controls during that run; it is not a cryptographic proof of backend identity.

Review signals can have several causes:

- Missing `usage` can mean the relay hides metadata, not necessarily that the model is fake.
- Model echo mismatches can come from proxy normalization, aliasing, or a wrong route.
- Timeout, malformed JSON, or server errors are reliability signals and should usually be rerun before making a strong conclusion.
- Similarity to a baseline model is behavioral evidence and should be interpreted with the negative controls and HTTP evidence.

For billing, procurement, or incident response decisions, combine the report with provider logs, billing exports, official endpoint comparisons, and independent operational checks.

## Troubleshooting

- `missing command: jq`: Install `jq` and reopen the terminal.
- `missing command: rg`: Install ripgrep and reopen the terminal.
- `relay url/key empty`: Set `RELAY_BASE_URL` and `RELAY_API_KEY`, or pass `--relay-base-url` and `--relay-api-key`.
- PowerShell blocks script execution: run with `pwsh -NoProfile -ExecutionPolicy Bypass -File .\check-api-quality-and-model-integrity.ps1 --mode quick`.
- Bash reports `$'\r'` or syntax errors: ensure `.sh` files use LF line endings. The repository includes `.gitattributes` to enforce this.
- Slow or hanging endpoints: use `--connect-timeout`, `--max-time`, and `--retries`.

## License

MIT. See [LICENSE](LICENSE).
