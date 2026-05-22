# P39：网关重启导致会话历史丢失（用户感知为「串台」）

## 级别

**非插件 Bug — Gateway 会话持久化问题。**

## 症状

- 用户在 Thread 中跟 Agent 完成了一段对话（Agent 做了多轮工具调用）
- Hermes Gateway 重启（任何原因：手动重启、脚本 `apply` 后交互式重启、崩溃恢复）
- 用户回到同一个 Thread 继续对话，Agent 回复「答非所问」「记不得刚才说了什么」
- 用户体感：「串台了」「加载了错误的上下文」

## 根因

Hermes Gateway 重启时，**内存中的会话 conversation history 会被清空**。

重启后，用户在同一 Thread 中发消息：
- `session_key` 命中（chat_id + thread_id 不变）
- 但 `conversation turn` 日志显示 `history=0`——没有保留之前的对话记录
- Agent 只能靠 `session_search` 从历史 transcript 中拼凑上下文，容易找错或遗漏

## 与 P36（并发 Thread 串台）的区别

| 特性 | P36 串台 | P39 会话丢失 |
|------|---------|------------|
| 消息路由 | 落到错误的 chat/thread | 路由正确 |
| `history=N` | N > 0（有历史，但是错误线程的历史） | N = 0（完全空） |
| 根因 | `send()` if-elif 结构 + `_resolve_root_id` 失败 | Gateway 重启清空内存 |
| 修复方 | 插件 `adapter.py` | 需要 Gateway 会话持久化机制 |

## 诊断方法

### 步骤 1：定位重启时间

```bash
grep 'Gateway running' ~/.hermes/logs/agent.log
```

输出示例：
```
2026-05-22 17:10:26,080 INFO gateway.run: Gateway running with 1 platform(s)
```

### 步骤 2：找到「串台」发生的 conversation turn

```bash
grep 'conversation turn.*history=0' ~/.hermes/logs/agent.log | tail -10
```

输出示例：
```
2026-05-22 17:17:24,639 INFO [...] conversation turn: session=20260522_170334_4da16f23 ... history=0 msg='总结下刚才改了什么'
```

### 步骤 3：对比时间线

- 如果 `history=0` 的 turn 发生在重启时间 **之后**，而该 session 的上一个 turn 发生在重启 **之前** → P39
- 如果 `history > 0` 但上下文内容错误（不属于当前 Thread）→ P36

### 步骤 4（可选）：验证 session 的上一个 turn

```bash
grep '20260522_170334_4da16f23.*conversation turn' ~/.hermes/logs/agent.log
```

如果重启前后都有同一个 session 的 turn，但 history 从 >0 重置为 0 → 确认 P39。

## 日志追踪示例

```
17:03:35  Turn #1 开始  [session=abcd, history=0]  ← 正常新会话
17:03~10  API calls #1~#14...                       ← Agent 在工作
17:10:22  最后一笔 API 调用完成
17:10:26  ⚠️ Gateway 重启
17:17:24  Turn #2 开始  [session=abcd, history=0]  ← ❌ 上下文丢失
```

17:17:24 的 Turn #2 本应有 Turn #1 的上下文（history 应该 > 0），但因为重启后内存清空，变成了 `history=0`。

## 影响范围

- 所有在 Gateway 重启前活跃的会话
- 重启后第一次对话均以 `history=0` 开始
- 用户体感为「Agent 失忆」，在不同 Thread 中表现略有不同：
  - 单 Thread：Agent 不记得刚才让你做了什么
  - 多 Thread（如本例）：在 Thread A 做完工作，去 Thread B 聊别的话题，回到 Thread A 时 Agent 失忆，用户感觉「串台」

## 缓解措施

1. **Gateway 重启前，主动告知用户**：「重启后当前对话的上下文会丢失，如果需要继续请记录关键信息」
2. **Turn 开始时检测 `history=0`**：如果 session 已存在但 history 为 0，Agent 应在回复中说明「我好像重启后丢失了上下文，需要回顾一下之前的对话」
3. **长期：Gateway 会话持久化**：在 `sessions/` 目录中保存 conversation history，重启后恢复
