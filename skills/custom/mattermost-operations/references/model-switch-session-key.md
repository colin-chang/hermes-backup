# /model 模型切换 — Session Key 机制与排障

## 机制概览

```
用户 /model → Enhancer _handle_model_command → 渲染卡片
用户点击模型 → _handle_model_switch_callback → _switch_session_model
                                            ↓
                              runner._session_model_overrides[session_key] = {...}
                                            ↓
下一条消息 → Gateway _resolve_session_agent_runtime → 读取 override → 应用模型
```

**关键**：Enhancer 和 Gateway 必须使用**完全相同的 session_key**，override 才能被读到。

## Session Key 构成

```
agent:main:mattermost:{chat_type}:{channel_id}[:{thread_id}]
```

`chat_type` 由 Mattermost 频道类型决定：

| MM Channel Type | chat_type |
|:---:|:---:|
| `"O"` (公开频道) | `channel` |
| `"G"` (群组消息) | `group` |
| `"P"` (私有频道) | `group` |
| `"D"` (私信) | `dm` |

Gateway 通过 `build_session_key()` 自动获取 `chat_type`（从 `SessionSource.chat_type`）。

## 已知陷阱：_build_session_key 硬编码

**Bug** (v2.4.3 及之前)：Enhancer 的 `_build_session_key` 硬编码 `"group"`：

```python
# ❌ 旧代码
key = f"agent:main:mattermost:group:{channel_id}"
```

这导致公开频道（type `"O"`）的 key 为 `...:group:...`，而 Gateway 查询时使用 `...:channel:...`，永远匹配不上。

**修复** (v2.4.4+)：改为异步调用 `get_chat_info()` 动态获取频道类型：

```python
# ✅ 新代码
chat_type = self._channel_type_cache.get(channel_id)
if chat_type is None:
    info = await self.get_chat_info(channel_id)
    chat_type = info.get("type", "channel")
    self._channel_type_cache[channel_id] = chat_type
key = f"agent:main:mattermost:{chat_type}:{channel_id}"
```

## 排障步骤

1. **确认 override 是否写入**
```bash
grep "Model switched" ~/.hermes/logs/gateway.log | tail -5
# 应看到: Model switched: session=... → minimax/minimax-m3 ... override_verified=YES
```

2. **对比 session key**
```bash
# Enhancer 存储的 key
grep "Model switched" ~/.hermes/logs/gateway.log | grep -oP 'session=\K[^ ]+'

# Gateway 实际使用的 key（从 response ready 行看）
grep "response ready" ~/.hermes/logs/gateway.log | grep -oP 'session \K[^:]+'
```

3. **如果 key 不匹配**：
   - 检查 `_build_session_key` 是否使用了正确的 `chat_type`
   - 确认 Gateway 已重启（插件 hot-reload 需要重启）

## 相关代码路径

| 组件 | 文件 | 关键函数 |
|------|------|---------|
| Gateway 构建 key | `gateway/session.py:600` | `build_session_key()` |
| Gateway 查询 override | `gateway/run.py:2642` | `_resolve_session_agent_runtime()` |
| Enhancer 构建 key | `adapter.py:444` | `_build_session_key()` |
| Enhancer 存储 override | `adapter.py:957` | `_switch_session_model()` |
| 频道类型映射 | `plugins/platforms/mattermost/adapter.py:40` | `_CHANNEL_TYPE_MAP` |
