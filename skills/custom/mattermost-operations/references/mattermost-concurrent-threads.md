# Mattermost 同频道多 Thread 并发分析

> 最后更新：2026-05-28 | 基准版本：Hermes v0.14.x

## 问题

用户在同一个 Mattermost 频道中同时发起两个 Thread 执行耗时任务，观察到 Thread A 的
长时间任务会阻塞 Thread B 的对话执行。

## 代码路径追踪

### 1. WebSocket 事件接收（串行）

```
Mattermost adapter _ws_loop → for raw_msg in ws:
  await _handle_ws_event(event)  ← 串行，每次只处理一条
```

代码位置：`plugins/platforms/mattermost/adapter.py:692`

### 2. _handle_ws_event → handle_message

```python
# adapter.py:882
await self.handle_message(msg_event)
```

`handle_message` 是 `_BasePlatformAdapter.handle_message()`（`gateway/platforms/base.py:3278`）。

### 3. handle_message 立即返回（非阻塞）

```python
# base.py:3463 — 当 session 未激活时
self._start_session_processing(event, session_key)
```

```python
# base.py:3117 — spawn 后台 task
task = asyncio.create_task(self._process_message_background(event, session_key))
```

**关键：`handle_message()` 只 spawn 一个 `asyncio.create_task`，立即返回。**
Thread A 的 agent 在后台 task 中运行，不影响后续 WebSocket 消息处理。

### 4. Session Key 隔离

```python
# session.py:652-653
if source.thread_id:
    key_parts.append(source.thread_id)  # 无条件追加
```

不同 Thread 的 session key **确实不同**：
- Thread A: `agent:main:mattermost:group:<channel>:<root_A>`
- Thread B: `agent:main:mattermost:group:<channel>:<root_B>`

因此 `_running_agents` 中是不同的条目，不会互相阻塞。

### 5. Gateway _handle_message 隔离

`gateway/run.py:7059`:
```python
if _quick_key in self._running_agents:
    # 已有 agent → interrupt/steer/queue
else:
    # 无 agent → 创建新 agent
```

不同 `_quick_key`（不同 thread_id）走不同的分支，不会互相干扰。

## 结论

**Hermes 架构设计支持同频道多 Thread 并发处理。** 不存在架构层面的阻塞。

## 可能原因

如果确实观察到阻塞现象，最可能的原因是：

| # | 可能原因 | 说明 |
|---|---------|------|
| 1 | **AI Provider 并发限制** | `custom:zenmux` 等自定义 provider 可能限制并发请求数 |
| 2 | **`_handle_ws_event` 同步耗时** | 附件下载（`adapter.py:814`）在 await 期间阻塞事件循环的本次迭代 |
| 3 | **Mattermost WebSocket 带宽** | 大量 typing 指示器 / 流式编辑挤占带宽 |
| 4 | **模型推理排队** | 同一 provider/model 多个请求在后端排队 |

## 排查命令

```bash
# 观察并发消息处理
tail -f ~/.hermes/logs/hermes.log | grep -E "inbound message|_running_agents|spawn|create_task"

# 检查 provider 并发限制
grep -A5 "custom:zenmux\|concurrency\|max_parallel\|rate_limit" ~/.hermes/config.yaml
```
