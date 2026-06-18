# Mattermost 串台：中断 metadata 传播 Bug

## 概述

2026-06-16 发现：当 Hermes 在一个 Mattermost 线程中执行长时间任务时，如果用户在**同一频道的不同线程**中发送消息触发中断，中断消息的 `reply_to`/`root_id` 会覆盖原会话的发送目标，导致后续回复全部发往错误线程。

## 复现条件

1. Hermes 在 Mattermost 频道 `juaoqexasb8g9neidkncfhxrjr` 的线程 A（root: `63dr38uhktbttk4anosuyo1upc`）中处理 MiMo 模型对比查询
2. 涉及多次 web_search / terminal 工具调用，耗时较长（~5 分钟）
3. 用户在**同一频道的线程 B**（root: `cbkh1u55m7dh9kqwjo5igmo9qh`）中发送 GLM 5.2 相关问题
4. 消息触发会话中断（同一 user + 同一 platform = mattermost）
5. 中断后所有 agent reply 发往线程 B 而非线程 A

## 完整日志时间线

### 阶段一：正常处理（线程 A）

```
# gateway.log:399  — MiMo 查询到达
2026-06-16 17:10:19,623 INFO gateway.run: inbound message:
  platform=mattermost user=colin chat=juaoqexasb8g9neidkncfhxrjr
  msg='xiaomi/mimo-v2.5-pro 是什么时间发布的？对比一下它与Deepseek v4 Pro模型在coding能力上和性能上的差异'

# agent.log:1917 — 会话创建
2026-06-16 17:10:19,719 INFO [20260616_171019_e46ea9d7] agent.turn_context:
  session=20260616_171019_e46ea9d7 platform=mattermost history=0

# agent.log:1921-1922 — 首次 send，目标正确
2026-06-16 17:10:30,516 INFO hermes_plugins.mattermost_enhancer.adapter:
  Mattermost: _resolve_root_id — input=63dr38uhktbttk4anosuyo1upc is_root=True
2026-06-16 17:10:30,517 INFO hermes_plugins.mattermost_enhancer.adapter:
  Mattermost: send() threading — reply_to=63dr38uhktbttk4anosuyo1upc
  resolved_root=63dr38uhktbttk4anosuyo1upc reply_mode=thread chat_id=juaoqexasb8g9neidkncfhxrjr
```

### 阶段二：中间状态（仍正确）

```
# agent.log:1943 — metadata fallback，目标仍正确
2026-06-16 17:13:19,669 INFO hermes_plugins.mattermost_enhancer.adapter:
  Mattermost: send() threading from metadata fallback —
  thread_id=63dr38uhktbttk4anosuyo1upc chat_id=juaoqexasb8g9neidkncfhxrjr
```

### 阶段三：中断发生 + 串台（线程 B 的 metadata 污染）

```
# agent.log:1957 — _resolve_root_id 突然指向线程 B！
2026-06-16 17:15:26,881 INFO hermes_plugins.mattermost_enhancer.adapter:
  Mattermost: _resolve_root_id — input=cbkh1u55m7dh9kqwjo5igmo9qh is_root=True
  (root_id='' — CHANNEL-LEVEL post, NOT in an existing Thread)

# agent.log:1958 — API call 被强制中断
2026-06-16 17:15:26,884 INFO run_agent:
  OpenAI client closed (stream_request_complete, shared=False, tcp_force_closed=1)

# agent.log:1959 — send() 使用错误目标
2026-06-16 17:15:26,884 INFO hermes_plugins.mattermost_enhancer.adapter:
  Mattermost: send() threading — reply_to=cbkh1u55m7dh9kqwjo5igmo9qh
  resolved_root=cbkh1u55m7dh9kqwjo5igmo9qh reply_mode=thread chat_id=juaoqexasb8g9neidkncfhxrjr

# agent.log:1960 — Turn 结束
2026-06-16 17:15:27,025 INFO [20260616_171019_e46ea9d7] agent.conversation_loop:
  Turn ended: reason=interrupted_during_api_call api_calls=7/180
```

### 阶段四：后续全部发往错误线程

```
# agent.log:1964 — 仍错误
2026-06-16 17:15:41,664 INFO hermes_plugins.mattermost_enhancer.adapter:
  Mattermost: send() threading — reply_to=cbkh1u55m7dh9kqwjo5igmo9qh ...
# agent.log:1967 — 仍错误
2026-06-16 17:16:07,370 INFO hermes_plugins.mattermost_enhancer.adapter:
  Mattermost: send() threading — reply_to=cbkh1u55m7dh9kqwjo5igmo9qh ...
# agent.log:1974 — 仍错误
2026-06-16 17:16:34,548 INFO hermes_plugins.mattermost_enhancer.adapter:
  Mattermost: send() threading — reply_to=cbkh1u55m7dh9kqwjo5igmo9qh ...
```

## 关键发现

1. **中断消息没有独立的 Gateway inbound 日志** — 17:10:19 到 17:18:39 之间仅两条 inbound：MiMo 查询和用户投诉。GLM 问题通过会话碰撞检测直接注入已激活会话。

2. **`tcp_force_closed=1` 是关键信号** — 表明 API 调用被中断，且中断后的 partial response send 使用了新消息的 metadata。

3. **`_resolve_root_id` 在 17:15:26 突然从 `63dr38uh...` 变为 `cbkh1u55...`** — 说明中断消息携带的 thread metadata 覆盖了原会话的发送目标。

4. **会话 ID 未变**（`20260616_171019_e46ea9d7` 延续）— 但 send 目标变了。说明 metadata 污染发生在 session 实例层面，而非 session_key 层面。

## 根因（已确认）

**🔴 Hermes 自身 Bug，非 Mattermost 插件问题。**

两个 bug 都在 `gateway/run.py`：

1. **Session source 覆盖** (~L7934)：`_handle_message_with_agent` 每次进入都调用 `_cache_session_source(session_key, source)`。中断后重入时 `source` 是中断消息的源（`thread_id=None`，`message_id` 错误），覆盖了原始正确的缓存源。

2. **Thread metadata 丢失** (~L12884)：`_thread_metadata_for_source(source, event_message_id)` 当 `source.thread_id=None` 时返回 `None`，导致 stream consumer 创建时 `metadata=None`，fallback send 只能用错误的 `_initial_reply_to_id`。

## 已实施修复（P60a + P60b）

在 `hermes-patches.sh` 中作为 P60a 和 P60b：

**P60a** — 防止覆盖缓存的 session source：
```python
# 修改前：
self._cache_session_source(session_key, source)

# 修改后：
if not self._get_cached_session_source(session_key):
    self._cache_session_source(session_key, source)
```

**P60b** — 回退到缓存源构造 thread metadata：
```python
_thread_metadata = self._thread_metadata_for_source(source, event_message_id)

# 新增：
if _thread_metadata is None:
    _cached_meta_source = self._get_cached_session_source(session_key)
    if _cached_meta_source is not None:
        _thread_metadata = self._thread_metadata_for_source(
            _cached_meta_source, event_message_id)
```
