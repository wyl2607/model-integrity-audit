# API 质量与模型真伪审计（Sanitized）

本项目用于对兼容 OpenAI Responses API 的路由做可复跑审计，目标是判断“模型行为是否与声明一致”，并输出不含敏感字段的报告。

支持两种模式：

- `quick`：10-30 秒快速置信度检查
- `full`：逐模型深度行为指纹审计

## 项目结构

- `check-api-quality-and-model-integrity.sh`：主入口（quick/full）
- `scripts/probe-gpt55-authenticity.sh`：`gpt-5.5` 深度探针
- `compare-app-vs-cli-gpt55.sh`：App/CLI 路由对比（可选）
- `reports/`：输出目录（默认忽略，不提交）

## 快速开始

```bash
git clone <your-repo-url>
cd model-integrity-audit
chmod +x *.sh scripts/*.sh
```

配置环境变量（推荐）：

```bash
cp .env.example .env
# 编辑 .env 后:
set -a
source .env
set +a
```

运行 quick：

```bash
./check-api-quality-and-model-integrity.sh --mode quick
```

运行 full：

```bash
./check-api-quality-and-model-integrity.sh \
  --mode full \
  --reasoning-effort medium \
  --samples 5 \
  --baseline gpt-5.4-mini \
  --models "gpt-5.5 gpt-5.4 gpt-5.4-mini gpt-5.3-codex gpt-5.2"
```

## 输出

- `reports/api-quality-model-integrity-quick-<timestamp>.json|.md`
- `reports/api-quality-model-integrity-full-<timestamp>.json|.md`

报告默认为去敏感化结果，不包含 API Key、Bearer Token、trace_id。

## 说明

- 该审计是行为证据，不是后端身份的加密学证明。
- 若用于成本结算判断，请结合实际账单导出做交叉核对。

## License

MIT（见 `LICENSE`）。
