# 模型完整性审计

语言：[English](README.md) | 中文 | [Deutsch](README.de.md)

Model Integrity Audit 是一个可复用的命令行工具包，用于检查兼容 OpenAI Responses API 的端点是否按预期工作。它会运行可复现的 API 质量检查、模型路由完整性探针、负向控制和模型行为指纹对比，并输出去敏感化的 JSON 与 Markdown 报告。

本项目面向常见 Windows、macOS 和 Linux 环境。仓库中不需要保存真实凭据。请在运行时使用环境变量、本地 `.env` 文件或命令行参数传入配置。

## 检查内容

- 端点是否接受有效的 Responses API 请求。
- 返回结果中的 `model` 字段是否匹配请求模型。
- 无效模型名是否会被拒绝。
- 无效 `reasoning.effort` 是否会返回类似参数校验的错误。
- `gpt-5.5` 是否在 token 和行为指纹上异常接近基线模型。
- 在安装 Codex CLI 时，可选检查 App 与 CLI 路由是否看起来使用同一模型路径。

## 模式

- `quick`：10-30 秒快速置信度检查，覆盖常见 API 与模型路由问题。
- `full`：更深入的多样本、多模型行为指纹审计。

## 项目结构

- `check-api-quality-and-model-integrity.sh`：主 Bash 入口，支持 `quick` 和 `full`。
- `check-api-quality-and-model-integrity.ps1`：Windows PowerShell 主入口包装脚本。
- `scripts/probe-gpt55-authenticity.sh`：专门的 `gpt-5.5` 真伪探针。
- `scripts/probe-gpt55-authenticity.ps1`：Windows PowerShell 探针包装脚本。
- `compare-app-vs-cli-gpt55.sh`：可选的 App/CLI Codex 路由对比。
- `compare-app-vs-cli-gpt55.ps1`：Windows PowerShell App/CLI 对比包装脚本。
- `.env.example`：安全的环境变量占位模板。
- `reports/`：本地输出目录，已被 Git 忽略。

## 安全规则

- 不要提交 `.env`、API key、Bearer token、原始 trace 或生成报告。
- 生成报告写入 `reports/`，该目录默认被 Git 忽略。
- 脚本会尽量输出去敏感化报告，避免写入 API key 或 Bearer token。
- 报告默认隐藏 endpoint。只有在明确需要本地报告显示端点 origin 时，才使用 `--show-endpoint`。
- 创建 PR 前运行 `./scripts/secret-scan.sh` 或 `.\scripts\secret-scan.ps1`。
- 文档和示例只使用占位值，例如 `https://your-relay.example.com/v1`。
- 如果要公开报告，请先检查 Markdown 和 JSON 内容。

## 依赖

主审计脚本需要：

- `bash`
- `curl`
- `jq`
- `rg`，来自 ripgrep
- `awk`
- `sed`
- `perl`

可选依赖：

- `codex` CLI，仅 `compare-app-vs-cli-gpt55.*` 需要。
- 官方 OpenAI API key，仅在需要 relay 与官方端点对比时使用。

## 安装依赖

### Windows

推荐 Windows Terminal 配置：

1. 安装 Git for Windows：`https://git-scm.com/download/win`
2. 使用 Winget 安装 ripgrep 和 jq：

```powershell
winget install BurntSushi.ripgrep.MSVC
winget install jqlang.jq
```

3. 重新打开 Windows Terminal。
4. 在仓库根目录运行 PowerShell 包装脚本。

Git for Windows 通常会提供 `bash`、`curl`、`awk`、`sed` 和 `perl`。如果包装脚本提示缺少命令，安装对应命令后重新打开终端。

### macOS

使用 Homebrew 安装依赖：

```bash
brew install jq ripgrep
```

macOS 自带 Bash、curl、awk、sed 和 perl，本项目可以直接使用系统版本。

### Linux

Debian 或 Ubuntu：

```bash
sudo apt update
sudo apt install -y bash curl jq ripgrep gawk sed perl
```

Fedora：

```bash
sudo dnf install -y bash curl jq ripgrep gawk sed perl
```

Arch Linux：

```bash
sudo pacman -S --needed bash curl jq ripgrep gawk sed perl
```

## 克隆仓库

```bash
git clone https://github.com/wyl2607/model-integrity-audit.git
cd model-integrity-audit
```

macOS 和 Linux 如有需要，给脚本添加执行权限：

```bash
chmod +x *.sh scripts/*.sh
```

## 配置凭据

推荐使用本地 `.env` 文件：

```bash
cp .env.example .env
```

在本地编辑 `.env`：

```bash
RELAY_BASE_URL="https://your-relay.example.com/v1"
RELAY_API_KEY="your_relay_api_key"
```

macOS 或 Linux 加载 `.env`：

```bash
set -a
source .env
set +a
```

PowerShell 中设置环境变量：

```powershell
$env:RELAY_BASE_URL = "https://your-relay.example.com/v1"
$env:RELAY_API_KEY = "your_relay_api_key"
```

也可以运行时直接传入：

```bash
./check-api-quality-and-model-integrity.sh --relay-base-url "https://your-relay.example.com/v1" --relay-api-key "your_relay_api_key" --mode quick
```

在共享机器上，避免把真实凭据写入 shell 历史。

## 快速审计

Windows PowerShell：

```powershell
.\check-api-quality-and-model-integrity.ps1 --mode quick
```

Windows PowerShell 显式传参：

```powershell
.\check-api-quality-and-model-integrity.ps1 --mode quick --relay-base-url "https://your-relay.example.com/v1" --relay-api-key "your_relay_api_key"
```

macOS 或 Linux：

```bash
./check-api-quality-and-model-integrity.sh --mode quick
```

macOS 或 Linux 显式传参：

```bash
./check-api-quality-and-model-integrity.sh --mode quick --relay-base-url "https://your-relay.example.com/v1" --relay-api-key "your_relay_api_key"
```

针对较慢端点可以设置网络控制参数：

```bash
./check-api-quality-and-model-integrity.sh --mode quick --connect-timeout 10 --max-time 60 --retries 2
```

报告默认隐藏 endpoint origin。如果只在本地报告中需要显示去敏感化 origin，可添加 `--show-endpoint`。

## 完整审计

Windows PowerShell：

```powershell
.\check-api-quality-and-model-integrity.ps1 --mode full --reasoning-effort medium --samples 5 --baseline gpt-5.4-mini --models "gpt-5.5 gpt-5.4 gpt-5.4-mini gpt-5.3-codex gpt-5.2"
```

macOS 或 Linux：

```bash
./check-api-quality-and-model-integrity.sh \
  --mode full \
  --reasoning-effort medium \
  --samples 5 \
  --baseline gpt-5.4-mini \
  --models "gpt-5.5 gpt-5.4 gpt-5.4-mini gpt-5.3-codex gpt-5.2"
```

## 专门的 GPT-5.5 探针

Windows PowerShell：

```powershell
.\scripts\probe-gpt55-authenticity.ps1 --model gpt-5.5 --samples 6 --reasoning-effort medium
```

macOS 或 Linux：

```bash
./scripts/probe-gpt55-authenticity.sh --model gpt-5.5 --samples 6 --reasoning-effort medium
```

可选官方 API 对比：

```bash
OFFICIAL_OPENAI_API_KEY="your_official_openai_api_key" ./scripts/probe-gpt55-authenticity.sh --model gpt-5.5
```

## App 与 CLI 路由对比

该脚本为可选功能，需要 Codex CLI 和本地 Codex 配置。

Windows PowerShell：

```powershell
.\compare-app-vs-cli-gpt55.ps1
```

macOS 或 Linux：

```bash
./compare-app-vs-cli-gpt55.sh
```

## 输出

报告会写入本地目录：

- `reports/api-quality-model-integrity-quick-<timestamp>.json`
- `reports/api-quality-model-integrity-quick-<timestamp>.md`
- `reports/api-quality-model-integrity-full-<timestamp>.json`
- `reports/api-quality-model-integrity-full-<timestamp>.md`
- `reports/app-vs-cli-gpt55-<timestamp>.json`
- `reports/app-vs-cli-gpt55-<timestamp>.md`

报告默认去敏感化，但公开前仍建议人工检查。

每个 JSON 报告都包含解释性字段：

- `evidence`：带 level、message 和支撑数据的人类可读检查结果。
- `warnings`：从 evidence 中提取的警告信息。
- `failed_controls`：失败或需要复查的控制项。
- `recommendations`：根据当前证据生成的下一步建议。

## 敏感信息扫描

提交或分享结果前运行：

```bash
./scripts/secret-scan.sh
```

Windows PowerShell：

```powershell
.\scripts\secret-scan.ps1
```

该扫描会检查 tracked 文件中的常见 API key、Bearer token、私有 endpoint 示例、trace ID，以及是否误提交了 `.env` 或 `reports/`。

## 离线完整性测试

仓库内置本地 mock Responses API，CI 和贡献者可以在没有真实 API key、没有真实 endpoint 的情况下测试完整审计流程：

```bash
./tests/run_mock_e2e.sh
```

该脚本会启动 `tests/mock_responses_api.py`，针对 `127.0.0.1` 运行 quick audit 和专门探针，验证 endpoint redaction、负向控制，然后清理本地测试服务。

也可以运行失败路径覆盖测试：

```bash
./tests/run_mock_failure_e2e.sh
```

该测试会验证 server error、损坏 JSON、缺失 usage、model mismatch、慢响应等情况会生成 warning 或 failed control，而不是错误地给出 high-confidence success。

## 结果解读

- `likely_real_gpt55_route`：该路由通过了当前实现的行为检查。
- `suspicious_or_unstable`：关键检查失败，或路由表现不稳定。
- `inconclusive`：证据不足，无法给出更强判断。

这些检查是行为证据，不是后端身份的加密学证明。如果用于账单或采购判断，应结合供应商日志、账单导出和独立运维检查。

## 常见问题

- `missing command: jq`：安装 `jq` 后重新打开终端。
- `missing command: rg`：安装 ripgrep 后重新打开终端。
- `relay url/key empty`：设置 `RELAY_BASE_URL` 和 `RELAY_API_KEY`，或传入 `--relay-base-url` 与 `--relay-api-key`。
- PowerShell 阻止脚本执行：使用 `pwsh -NoProfile -ExecutionPolicy Bypass -File .\check-api-quality-and-model-integrity.ps1 --mode quick`。
- Bash 报 `$'\r'` 或语法错误：确认 `.sh` 文件使用 LF 换行。本仓库已通过 `.gitattributes` 强制 `.sh` 使用 LF。
- 端点较慢或请求卡住：使用 `--connect-timeout`、`--max-time` 和 `--retries`。

## License

MIT。见 [LICENSE](LICENSE)。
