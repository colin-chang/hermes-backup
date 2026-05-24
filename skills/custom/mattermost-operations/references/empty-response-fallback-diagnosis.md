# Empty Response → Fallback Prior Turn Content 诊断

> 诊断日期：2026-05-24 | 触发会话：20260524_140654

## 症状

用户在 Mattermost Thread 中发消息后：
1. 等待很长时间（5-10 分钟）
2. 最终只收到极短回复（如 39 字符）
3. 回复内容像是从更早对话中截取的片段，与当前问题无关
4. 工具进度指示器持续显示但最终无产出

## 根因链路

```
1. LLM 触发大量 tool calls（52+）
2. 某次 API 调用后 LLM 返回空文本（无 content，无 reasoning）
3. Hermes run_agent 检测到空响应 → emit "Empty response after tool calls — nudging model"
4. Nudge 无效，模型仍无法产出内容
5. Turn 以 fallback_prior_turn_content 结束
6. response_len 极少（如 39 chars）← 这是从更早 assistant 消息中截取的片段
```

## 关键日志特征

### 1. 空响应 nudge
```
INFO run_agent: Empty response after tool calls — nudging model to continue processing
```

### 2. Turn ended 模式（决定性证据）
```
WARNING run_agent: Turn ended with pending tool result (agent may appear stuck).
  reason=fallback_prior_turn_content
  api_calls=52        ← 大量 API 调用
  response_len=39     ← 极少输出
  last_tool=todo       ← 最后一步是工具调用，不是文本响应
```

正常 turn ended：
```
INFO run_agent: Turn ended: reason=text_response(finish_reason=stop)
  response_len=825    ← 正常输出
```

### 3. 前置信号：Stream Drop（ReadTimeout）
如果在此前几分钟出现：
```
WARNING run_agent: Stream drop on attempt 2/3 — retrying
  error_type=ReadTimeout
```
说明 API 连接不稳定，空响应可能是超时后重试的连锁反应。

## 诊断步骤

```bash
# 1. 找到空响应事件
grep -n 'Empty response after tool calls\|fallback_prior_turn_content' ~/.hermes/logs/agent.log | tail -10

# 2. 查看对应 session 的完整 turn 记录
grep 'session=20260524_140654' ~/.hermes/logs/agent.log | grep 'Turn ended'

# 3. 对比正常 turn vs 异常 turn 的差异
#    正常：reason=text_response, response_len > 100
#    异常：reason=fallback_prior_turn_content, response_len < 100

# 4. 检查是否有前序 Stream Drop
grep -B50 'Empty response after tool calls' ~/.hermes/logs/agent.log | grep 'Stream drop\|ReadTimeout'

# 5. 确定触发消息
grep -B100 'Empty response after tool calls' ~/.hermes/logs/agent.log | grep 'conversation turn'
```

## 关联问题：模型自诊螺旋

用户追问「为什么没回复」时，模型可能进入自诊螺旋：
- 疯狂调用 `terminal` 工具读日志文件
- 每轮 API call 7-15 秒，累积大量 token
- 可能烧到 70+ API calls 仍无产出

**识别特征**：
- 同一 session 连续 20+ API calls 全是 `terminal` + `web_search`
- `command` 内容是 `grep`/`cat`/`tail` 诊断命令
- 日志中穿插 `search_files` / `web_search` 查 Hermes 内部机制

**应对**：立即 `/stop`，不要让模型继续自诊。人工诊断更快更准。

## 长期修复方向

1. **调大 `request_timeout_seconds`**——减少 ReadTimeout 触发频率
2. **模型切换**——某些模型（如 `minimax-m2.7`）更容易空响应，`deepseek-v4-pro` 相对稳定
3. **工具调用预算**——限制单 turn 最大 tool calls，防止 52+ 次调用累积到上下文溢出
4. **上游修复**——Hermes 的 `fallback_prior_turn_content` 机制本身是兜底，但应至少输出一条有意义的错误消息告知用户

## 相关文档

- Hermes Agent: `references/stream-timeout-silent-failure.md` — Stream Drop / ReadTimeout 分析
- `references/hermes-cron-pitfalls.md` — Cron 子代理相关陷阱
