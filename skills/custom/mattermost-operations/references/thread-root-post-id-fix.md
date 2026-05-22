# P38: Thread 根帖/回复 thread_id 为空导致进度消息落到频道或 session 分裂

> 诊断日期：2026-05-22 | 修复状态：✅ 已增强修复（需重启 Gateway） | hermes-patches.sh: patch #11
> 增强日期：2026-05-22 — 新增 API 反查防御 Thread 回复中 root_id 异常为空的场景

## 问题表现

在 Mattermost CRT Thread 中执行长时间任务时，类似 `⏳ Still working... (6 min elapsed — iteration 10/180)` 的进度通知消息直接出现在频道主聊天流，而非当前 Thread。用户在 Thread 中等结果，进度信息却跑到频道里。

## 根因

**Gateway `mattermost.py` L769：**

```python
thread_id = post.get("root_id") or None
```

Mattermost CRT 模式下，Thread **根帖**（第一条消息）的 WebSocket 事件中 `root_id` 是空字符串 `""`。Python 的 `"" or None` 求值为 `None`。

整个影响链：
1. `source.thread_id` = None
2. `_progress_thread_id` = None → `_status_thread_metadata` = None
3. `_notify_adapter.send(..., metadata=None)` — 通知消息不带 metadata
4. 插件的 `send()` 的 `elif` 分支（metadata.thread_id fallback）无法匹配
5. 消息不带 `root_id` → Mattermost 将其作为频道级帖子发送

**为什么 Thread 回复不受影响：** 正常情况下，回复消息的 `root_id` 指向根帖 ID（非空），`or None` 保留原始值，`source.thread_id` 正确。

**⚠️ 边界场景 — Thread 回复 root_id 意外为空：** 此前排查中发现，极少数情况下 Thread 内的回复消息 WebSocket 事件中 `root_id` 也为空字符串（Mattermost 异常）。此场景下老版 P38 改为 `elif reply_mode == "thread": thread_id = post_id`，但 `post_id` 是回复消息自己的 ID 而非 Thread 根帖 ID → 回复消息的 session key 与 Thread 中其他消息不一致 → **上下文分裂**。

**为什么 P36/P37 没覆盖此场景：** P36 修复了 `_resolve_root_id` 失败时的 metadata fallback，P37 修复了 `send_exec_approval` 丢失 metadata。但 P38 的根本问题是 `source.thread_id` 在根帖场景下根本没被设置——metadata 在源头就是 None。

## 日志验证

```
Mattermost: tool progress routing — source.thread_id=None event_message_id='...'
```

Thread 根帖的日志中 `source.thread_id=None`，而 Thread 回复中 `source.thread_id='r8narqx...'`。

## 修复

**文件：** `gateway/platforms/mattermost.py` L768-789

```python
# 修复前
thread_id = post.get("root_id") or None

# 修复后（增强版 v2）
_raw_root = post.get("root_id")
if _raw_root:
    thread_id = _raw_root
elif self._reply_mode == "thread":
    # root_id="" can mean either a genuine thread-root post OR a
    # reply whose root_id was lost (Mattermost WebSocket anomaly).
    # Ask the REST API before blindly trusting the WebSocket event.
    try:
        post_data = await self._api_get(f"posts/{post_id}")
        api_root = post_data.get("root_id") if post_data else None
        if isinstance(api_root, str) and api_root:
            thread_id = api_root       # API 返回了真正的 root_id
        else:
            thread_id = post_id        # 确认是根帖
    except Exception:
        thread_id = post_id            # API 失败时 fallback
else:
    thread_id = None
```

只在 CRT 模式（`reply_mode=thread`）时触发，flat 模式行为不变。`elif` 分支不再盲目假设 `post_id` 就是 Thread ID，而是先通过 REST API 查询确认。`_api_get` 返回 `{}` 或抛异常时 fallback 到 `post_id`，不阻塞消息处理。

**`hermes-patches.sh` 注册：** patch #11，check grep: `_raw_root = post.get`