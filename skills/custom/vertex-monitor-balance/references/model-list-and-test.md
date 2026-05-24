# Vertex Monitor 模型 & 连接测试

## 支持的模型（13 个）

所有 Google Gemini 聊天模型，按系列：

| 模型 | 上下文 | 状态 |
|------|--------|------|
| `gemini-3.5-flash` | 1M | 推荐 |
| `gemini-3.1-flash-lite` | 1M | 推荐（默认） |
| `gemini-3.1-pro-preview` | 1M | 预览 |
| `gemini-3.1-pro-preview-customtools` | 1M | 预览 |
| `gemini-3-flash` | 1M | 预览 |
| `gemini-2.5-pro` | 2M | 稳定 |
| `gemini-2.5-flash` | 1M | 稳定 |
| `gemini-2.5-flash-lite` | 1M | 稳定 |
| `gemini-2.5-flash-live-api` | 1M | 稳定 |
| `gemini-2.0-flash` | 1M | 旧版 |
| `gemini-2.0-flash-lite` | 1M | 旧版 |
| `gemini-1.5-pro` | 2M | 旧版 |
| `gemini-1.5-flash` | 1M | 旧版 |

排除：图片/视频生成模型（`*-flash-image`/`*-pro-image`/Veo/Imagen）和需单独部署的 Gemma。

## 连通性测试

```bash
# 快速验证 Vertex AI 连接
curl -s -X POST http://localhost:8899/api/test

# 成功响应
{"ok": true, "model": "gemini-3.1-flash-lite", "response": "OK"}

# 失败响应（含错误详情）
{"ok": false, "model": "gemini-3.1-flash-lite", "error": "..."}
```

Web UI 本期概览卡片底部有 **「🔍 测试连通性」** 按钮，点击即可触发。

## 容器未运行时

```bash
cd ~/Developer/Services/VertexMonitor && docker compose up -d
```
