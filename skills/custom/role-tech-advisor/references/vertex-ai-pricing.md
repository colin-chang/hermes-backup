# Vertex AI Gemini 定价参考

> 以下为 Vertex AI on-demand (pay-as-you-go) text-only 定价。  
> 定价由 liteLLM SDK 自动维护，此文件仅作离线参考。  
> 官方页面：<https://cloud.google.com/vertex-ai/generative-ai/pricing>

## 常用模型价格（text-only）

| 模型 | Input / 1M tokens | Output / 1M tokens | Input / 1K | Output / 1K |
|------|-------------------|---------------------|------------|-------------|
| gemini-1.5-flash | $0.075 | $0.30 | $0.000075 | $0.00030 |
| gemini-1.5-pro | $1.25 | $5.00 | $0.00125 | $0.00500 |
| gemini-2.5-flash | $0.15 | $0.60 | $0.00015 | $0.00060 |
| gemini-2.5-pro | $1.25 | $10.00 | $0.00125 | $0.01000 |
| gemini-3.1-flash-lite | ~$0.10 | ~$0.40 | ~$0.00010 | ~$0.00040 |

## 消费估算

以 gemini-3.1-flash-lite 为例：
- $10 ≈ 100M input tokens 或 25M output tokens
- 短对话（~100 prompt + ~200 completion）：每次 ≈ $0.00009
- 长对话（~2000 prompt + ~1000 completion）：每次 ≈ $0.0006

## 计费注意事项

- **trafficType**：响应中 `usageMetadata.trafficType` 区分 ON_DEMAND_PRIORITY vs FLEX，价格不同
- **liteLLM 自动处理**：`completion_cost()` 读取 `trafficType` 自动选择正确阶梯价
- **图像/音频/视频**：按模态分别计价，text-only 为上述价格
- **grounding (Google Search)**：额外计费，$35/1K grounded queries
