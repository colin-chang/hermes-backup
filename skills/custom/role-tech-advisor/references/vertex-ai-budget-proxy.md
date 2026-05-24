# Vertex AI 用量追踪 & 预算拦截方案

> 调研时间：2026-05-24。用户订阅 Google Gemini Pro，每月 $10 Vertex AI 赠金，需要用量耗尽时自动停止调用。

## 赠金机制

- 每月需**手动领取**：<https://developers.google.com/program/my-benefits>
- 仅限 Vertex AI 端点（直接 Gemini API 不适用）
- **没有程序化 API** 查询剩余额度
- GCP Billing 报表有数小时滞后（不可用于实时拦截）

## Vertex AI Gemini 定价（on-demand, text-only）

| 模型 | Input / 1M tokens | Output / 1M tokens |
|------|-------------------|---------------------|
| Gemini 1.5 Flash | $0.075 | $0.30 |
| Gemini 1.5 Pro | $1.25 | $5.00 |
| Gemini 2.5 Flash | $0.15 | $0.60 |
| Gemini 2.5 Pro | $1.25 | $10.00 |

> 定价来源：<https://cloud.google.com/vertex-ai/generative-ai/pricing>。图片/音频/视频输入按不同倍率计费，见官方文档。

## Token 计数 API

Vertex AI SDK 提供两级 token 计数：

```python
from vertexai.generative_models import GenerativeModel

model = GenerativeModel("gemini-1.5-flash")

# Pre-call: 仅计算输入 token
count = model.count_tokens(prompt)
print(count.total_tokens)  # int

# Post-call: 精确用量
response = model.generate_content(prompt)
meta = response.usage_metadata
# meta.prompt_token_count     → 输入 token
# meta.candidates_token_count → 输出 token
# meta.total_token_count      → 总和
# meta.traffic_type           → "ON_DEMAND_PRIORITY" (pay-go)
```

参考：<https://docs.cloud.google.com/vertex-ai/generative-ai/docs/multimodal/list-token>

## 推荐方案：自建轻量计费代理

```
你的代码 → Proxy (:8899) → Vertex AI
              │
              └─ cost.json (SQLite 也可)
```

### 两阶段策略

| 阶段 | 时机 | 操作 |
|------|------|------|
| Pre-call | 请求到达 | `count_tokens()` → 估算费用 → 超预算返回 402 |
| Post-call | 响应返回 | 读 `usage_metadata` → 精确扣减 → 持久化 |

### 优势

- ~200 行 Python，零外部依赖
- 精确到每次调用，而非等待 GCP 报表
- 支持月度自动重置
- 暴露 `/usage`、`/health` 端点
- 可逐步演进（加速率限制、多模型定价表、Web Dashboard）

### 月度重置策略

```python
# cost.json 结构
{
  "month": "2026-05",
  "limit": 10.00,
  "spent": 0.0042,
  "calls": 127,
  "last_reset": "2026-05-01T00:00:00"
}
```

每次请求时检查 `month` 是否变化，自动归零 `spent`。

### 备选方案（评估后不推荐）

- **liteLLM Proxy**：重型（需 Docker + Redis + PostgreSQL），单人单项目杀鸡用牛刀
- **GCP Budget Alert + Pub/Sub**：计费延迟数小时，无法实时拦截

## 实现要点

1. **保守估算**：Pre-call 阶段按 `max_output_tokens` 估算输出费用，实际消耗只会更低
2. **原子写入**：`cost.json` 更新使用临时文件 + `os.replace()` 防止并发写损坏
3. **优雅降级**：Vertex AI 不可用时代理返回 502，不清空预算
4. **定价表外置**：`pricing.json` 独立于代码，模型更新时仅改配置
