# 跨 Thread 串台防御 (P57)

## 问题描述

2026-05-27 真实发生：Agent 在当前 Thread A 中处理用户消息，最终回复却出现在**完全不同的 Thread B** 中。Thread B 是另一个独立会话，用户体感为「回复串台」。

## 根因分析

`_resolve_root_id()` 在 API 正常时返回正确的 root_id，但 **Gateway 层传入的 `reply_to`（即 `event_message_id`）可能指向错误 Thread 的帖子**。当 WebSocket 频繁断线重连或 session 路由错位时，`source.event_message_id` 可能携带其他 Thread 的消息 ID。

此时 `_resolve_root_id(reply_to)` 仍然会忠实地返回一个有效的 root_id——只是这个 root_id 属于**另一个 channel**。Mattermost API 接受这个 root_id 并正常投递，消息就串到了错误的 Thread 中。

```
Thread A (本应在此回复)          Thread B (实际收到回复)
┌─────────────────────┐          ┌─────────────────────┐
│ User: "排查问题..."   │          │ User: "检查插件..."   │
│                      │          │                      │
│ 回复没出现            │          │ Agent 回复出现在这     │
└─────────────────────┘          └─────────────────────┘
         ↑                                ↑
    reply_to 指向了              _resolve_root_id 返回了
    Thread B 的 event_id         Thread B 的 root_id
```

## 防御方案：channel_id 校验

在 `send()` 方法的 `_resolve_root_id` 分支增加 channel 归属校验：

```python
if reply_to and self._reply_mode == "thread":
    root_id = await self._resolve_root_id(reply_to)
    if root_id:
        # 防御：验证 root_id 确实属于当前 channel
        root_post = await self._api_get(f"posts/{root_id}")
        if root_post and root_post.get("channel_id") != chat_id:
            logger.error(
                "Mattermost: root_id channel mismatch — aborting thread routing! "
                "root=%s root_channel=%s expected_channel=%s",
                root_id, root_post.get("channel_id"), chat_id,
            )
            root_id = None  # 拒绝路由到错误 channel 的 root_id
```

### 成本评估

- 每个 Thread 内回复多一次 `GET /posts/{root_id}` API 调用
- `_resolve_root_id` 内部本身就会调用 `GET /posts/{reply_to}` 一次
- 增加一次调用约 50-200ms 延迟，对用户体验影响微小
- 防御收益远大于微小延迟成本

## 已实施

**未实施。** 2026-05-27 仅诊断定位，未写入生产代码。此文档记录根因和修复方案，待用户批准后 apply。

## 与 P36 的区别

| | P36 (metadata fallback) | P57 (channel validation) |
|---|---|---|
| 根因 | `_resolve_root_id` 失败返回 None，丢掉 thread 上下文 | `_resolve_root_id` 成功但返回了错误 channel 的 root_id |
| 影响 | 消息落到频道级（不在任何 Thread 中） | 消息出现在错误的 Thread 中 |
| 修复 | if-elif 转 嵌套 if，fallback 到 metadata.thread_id | 验证 root_id 的 channel_id 匹配当前 chat_id |
