# Vertex Monitor 代理 — SSE 流式兼容修复

## 症状

Hermes 使用 `custom:vertex` provider（指向 `http://localhost:8897/v1`）时：
- agent.log 显示 `Empty response (no content or reasoning)` 连续 3 次重试
- 然后 fallback 到备用 provider（Ollama），若备用也挂则完全失败
- TCP 连接正常关闭（`tcp_force_closed=0`），HTTP 状态码 200
- 直接 curl 非流式请求正常返回内容

## 根因

```
Hermes stream:true → Vertex Monitor 代理 → 返回 JSONResponse (纯 JSON)
                                                    ↓
                              Hermes 流式客户端期望 SSE data: {...}\n\n
                              解析纯 JSON → 空内容 → "Empty response"
```

**关键细节：**

1. Hermes 全局 `streaming.enabled: true` → 所有 provider 都发 `stream: true`
2. Vertex Monitor 代理已正确处理 litellm 侧：`llm_kwargs["stream"] = False`（proxy.py:223）
3. 但 HTTP 响应仍用 `JSONResponse`，而非流式客户端期待的 SSE 格式
4. Hermes 的 "stream not supported" 降级机制只在**收到错误响应**时触发（run_agent.py:8768 — 检查 error message 中是否含 "stream" + "not supported"）
5. 代理返回 HTTP 200 + 格式错误的 body → 降级不触发 → 静默失败

## 修复方案

**文件：** `VertexMonitor/proxy.py`

在 `chat_completions` 端点中：
1. 读取客户端请求中的 `stream` 字段
2. 若客户端请求流式（`stream: true`）：
   - 保持 `stream=False` 传给 litellm（litellm 返回完整 `ModelResponse`）
   - 将完整响应拆为 SSE 流式块：`delta` chunk → `finish` chunk → `[DONE]`
   - 使用 FastAPI `StreamingResponse`，`media_type="text/event-stream"`
3. 非流式请求保持原有 `JSONResponse` 行为

**SSE 块格式：**

```
data: {"id":"chatcmpl-xxx","object":"chat.completion.chunk","choices":[{"index":0,"delta":{"content":"..."},"finish_reason":null}]}

data: {"id":"chatcmpl-xxx","object":"chat.completion.chunk","choices":[{"index":0,"delta":{},"finish_reason":"stop"}],"usage":{...},"_budget":{...}}

data: [DONE]
```

## 诊断步骤（可复用）

当 Hermes 出现 "Empty response" 错误时：

1. **确认代理存活**：`curl http://localhost:8897/health`
2. **非流式直连测试**：`curl ... -d '{"stream":false,...}' → 验证代理本身正常`
3. **流式直连测试**：`curl -N ... -d '{"stream":true,...}' → 检查是否返回 SSE 格式`
4. **检查 agent.log**：`grep "Empty response" errors.log` → 确认是流式解析问题
5. **检查 Hermes 流式配置**：`config.yaml → streaming.enabled` 和 `display.streaming`
6. **检查代理日志**：`docker logs vertex-monitor --tail 50` → 确认 POST /v1/chat/completions 返回 200

## 通用模式

任何本地代理/Ollama 兼容服务接入 Hermes 时，若 Hermes 全局 `streaming: true`：
- 代理**必须**支持 SSE 流式格式（`text/event-stream`，`data: {...}\n\n`）
- 不支持流式的代理会导致 "Empty response"，且不触发 Hermes 的自动降级
- 临时绕过：`config.yaml → display.streaming: false`（全局关闭）
- 正确修复：在代理中实现 SSE 包装（本文件）
