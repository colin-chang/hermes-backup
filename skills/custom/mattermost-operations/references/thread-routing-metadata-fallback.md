# 并发 Thread 串台修复 (P36)

## 问题描述
在 Mattermost Thread 模式下，当多个 Agent 并发发送消息时，消息偶发性地落到频道主聊天流而非指定的 Thread，导致 Thread 对话内容在频道中混淆。

## 根因分析
在 `adapter.py` 的 `send()` 方法中，存在逻辑缺陷：

```python
# 修复前
if reply_to and self._reply_mode == "thread":     # ← 匹配 reply_to
    root_id = await self._resolve_root_id(reply_to) # ← 高并发下易超时/失败返回 None
    if root_id:
        payload["root_id"] = root_id
    else:
        logger.warning(...) # ← ⚠️ 仅记录日志，未 fallback！
elif ... metadata.get("thread_id"):                  # ← if 匹配了 reply_to，此分支永远走不到
    payload["root_id"] = str(metadata["thread_id"])
```

当 `_resolve_root_id` 失败（返回 None）时，`send()` 直接跳过 `root_id` 字段的设置，Mattermost 默认将其视为频道级帖子。并发压力大时 API 调用失败率上升，导致该 Bug 被频繁触发。

## 修复方案
将 if-elif 结构改为嵌套 if-else，确保即使 API 调用失败，依然能 fallback 到 `metadata.thread_id`：

```python
if reply_to and self._reply_mode == "thread":
    root_id = await self._resolve_root_id(reply_to)
    if root_id:
        payload["root_id"] = root_id
    elif metadata and metadata.get("thread_id"):
        # 降级使用 metadata 中的 thread_id
        payload["root_id"] = str(metadata["thread_id"])
    else:
        # 兜底：不设置 root_id，以频道消息发出
        logger.warning(...)
```
