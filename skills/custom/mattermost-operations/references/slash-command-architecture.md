# Mattermost Slash Command 架构约束与陷阱

> **记录日期：2026-05-20 | 最后验证：2026-05-21 | Mattermost 版本：v11.x**
## 核心约束：Mattermost 拦截所有 `/` 开头消息

**Mattermost 客户端会在本地拦截所有 `/` 开头的消息。** 未注册为 Slash Command 的 `/` 指令会被静默丢弃或显示 "Command not found"，**永远不会通过 WebSocket 传递给 Bot**。

### 这意味着什么

- 想让 `/model` 或 `/new` 在 Mattermost 中可用，**必须**在管理后台注册 Slash Command
- 注册后，Mattermost 将 `/model` 的请求 POST 到指定的 Callback URL（我们的 `/mm-command` 端点）
- 这与 Telegram/Discord 完全不同——那些平台上 `/model` 作为普通消息通过 WebSocket 到达 Gateway

### 常见错误认知

| 错误认知 | 实际行为 |
|---------|---------|
| "删除 Slash Command 注册后，`/model` 会走 WebSocket" | ❌ 删除后 `/model` 被客户端拦截，用户看到 "Command not found" |
| "Gateway 内置 `/model` 处理对 Mattermost 也生效" | ❌ 仅对 Telegram/Discord/WebUI 生效，Mattermost 的 `/model` 永远到不了 Gateway |
| "实现 `send_model_picker` 就能在 Mattermost 上用卡片选模型" | ❌ `send_model_picker` 只在 `/model` 通过 WebSocket 到达时被调用 |

## Slash Command Payload 结构

Mattermost 发送 `application/x-www-form-urlencoded` POST 请求：

```
token=xxx&team_id=xxx&team_domain=xxx&channel_id=xxx&channel_name=xxx
&user_id=xxx&user_name=xxx&command=/model&text=&response_url=xxx
```

### root_id 字段：Thread 上下文

**MM Slash Command payload 包含 `root_id` 字段！** 之前的文档错误地声称"payload 不含 root_id"——实际测试（2026-05-21）确认 payload 中 `root_id` 字段始终存在：

- **Thread 中发送**：`root_id=<root_post_id>`（26 字符）
- **Channel 顶层发送**：`root_id=`（空字符串）

完整 payload 字段列表：

```
token=xxx&team_id=xxx&team_domain=xxx&channel_id=xxx&channel_name=xxx
&user_id=xxx&user_name=xxx&command=/model&text=&response_url=xxx
&root_id=xxx&trigger_id=xxx
```

**直接从 payload 读取 root_id**：

```python
# ✅ 正确做法 — 直接从 payload 读取
root_id = params.get("root_id", "") or None  # Channel 顶层 → None, Thread → root_post_id

# ❌ 错误做法 — API 反查（已废弃）
# root_id = await self._find_user_thread_root_id(channel_id, user_id)
```

**⚠️ 旧代码的弯路**（已废弃）：之前假设 payload 不含 `root_id`，实现了 `_find_user_thread_root_id()` 通过 API 反查用户最近帖子来判断上下文，还添加了 `asyncio.sleep(0.5)` 解决时序问题。这些全部不必要——直接读 `params["root_id"]` 即可。`_find_user_thread_root_id()` 已从 `adapter.py` 中删除。

## Slash Command 响应模式

### 两种 response_type

| 类型 | 可见性 | 用途 |
|------|--------|------|
| `ephemeral` | 仅触发用户可见，自动消失 | 确认提示、错误消息 |
| `in_channel` | 所有人可见，持久保留 | 卡片式交互 |

### 重复消息问题

**问题**：Slash Command 返回 `in_channel` 响应 → 所有人看到一条消息；如果同时还通过 Bot API 发帖 → 又一条消息。两条消息内容重复。

**解决**：Slash Command 返回 `ephemeral`（确认收到），实际卡片通过 **Bot API `_api_post("posts", ...)` 发帖**。

```python
# Slash Command 处理函数返回 ephemeral
return {"response_type": "ephemeral", "text": "🔄 模型选择器已发送"}

# 卡片通过 Bot API 发送到 thread
await self._api_post("posts", {
    "channel_id": channel_id,
    "root_id": root_id,      # thread 上下文
    "message": pretext,
    "props": {"attachments": attachments},
})
```

### 用户头像 vs Bot 头像

**问题**：Slash Command 的 `in_channel` 响应以**触发用户**的身份发送（显示用户头像），不是 Bot。

**解决**：使用 Bot API `_api_post("posts", ...)` 发帖 → 显示 Bot 头像和名称。

## Interactive Message 限制

Mattermost 对 Interactive Message 有硬性限制：

| 限制项 | 值 |
|--------|-----|
| 每个 attachment 的 actions 数量 | **最多 5 个** |
| 每个 message 的 attachments 数量 | **最多 5 个** |
| 按钮总数上限 | 5 × 5 = 25 个 |

当模型列表超过 5 个时，需要自动拆分为多个 attachment：

```python
def _split_actions(actions, chunk_size=5):
    return [actions[i:i+chunk_size] for i in range(0, len(actions), chunk_size)]
```

## Hermes 插件架构（mattermost-enhancer）

### 文件结构

```
~/.hermes/plugins/mattermost-enhancer/
├── __init__.py         # register_platform() 覆盖内置 mattermost adapter
├── adapter.py          # MattermostApprovalAdapter — 继承内置 MattermostAdapter
├── callback_server.py  # HTTP callback server 原始实现（已被 adapter._start_callback_server 替代）
├── cards.py            # Interactive Message 卡片渲染（模型选择/会话重置/成功确认/Clarify 提问）
├── models.py           # 模型列表获取 + provider 解析
└── session.py          # session 操作辅助（已部分合并到 adapter）
```

### 覆盖机制

```python
# __init__.py
def register(registry):
    registry.register_platform(
        name="mattermost",
        adapter_factory=lambda cfg: MattermostApprovalAdapter(cfg),
    )
```

Gateway 的 `_create_adapter()` 优先查找 `platform_registry` → 找到插件注册 → 创建 `MattermostApprovalAdapter`（不走内置 if/elif 链）。

### 回调路由

| 路由 | 用途 | 来源 |
|------|------|------|
| `POST /mattermost/callback` | Interactive Message 按钮回调（审批 + 模型切换 + 会话重置 + Clarify 提问） | Mattermost 服务端 |
| `POST /mm-command` | Slash Command 回调（/model + /new） | Mattermost 服务端 |

### session_key 构建规则

对齐 Gateway 的 `build_session_key` 格式：

```python
def _build_session_key(self, channel_id: str, root_id: Optional[str]) -> str:
    key = f"agent:main:mattermost:group:{channel_id}"
    if root_id:
        key += f":{root_id}"
    return key
```

### 模型切换流程

```
用户输入 /model
  → Mattermost 拦截 → POST /mm-command（payload 含 root_id 字段）
  → _route_slash_command() → root_id = params.get("root_id", "") or None
  → _handle_model_command(channel_id, user_id, root_id)
  → _build_session_key() 构建正确 session_key
  → _post_card_in_thread() Bot API 发送模型选择卡片
  → 用户从 select 下拉列表选择模型
  → Mattermost POST /mattermost/callback（context.selected_option = model_id）
  → _handle_model_switch_callback()
  → _switch_session_model()
     → resolve_provider_config() 直读 custom_providers
     → runner._session_model_overrides[session_key] = {model, provider, base_url, api_key, api_mode}
     → runner._evict_cached_agent(session_key)
     → runner._pending_model_notes[session_key] = "Note: model switched..."  ← 让 LLM 知道
  → 卡片更新为切换成功
  → 用户发下条消息 → Gateway 注入 pending_model_note → LLM 正确自报新模型
```

### 会话重置流程

```
用户输入 /new
  → Mattermost 拦截 → POST /mm-command（payload 含 root_id 字段）
  → _route_slash_command() → root_id = params.get("root_id", "") or None
  → _handle_new_command(channel_id, user_id, root_id)
  → _post_card_in_thread() Bot API 发送确认卡片
  → 用户点击 "确认重置"
  → Mattermost POST /mattermost/callback
  → _handle_new_confirm_callback()
  → _reset_session() → 清除 _session_model_overrides + _pending_model_notes + _evict_cached_agent + session store reset
  → 卡片更新为重置成功
```

## Pitfall 合集（Slash Command 相关）

### Pitfall 14：假设 `/model` 会通过 WebSocket 到达 Gateway

**症状**：实现 `send_model_picker` 但在 Mattermost 中输入 `/model` 无任何反应。

**根因**：Mattermost 客户端拦截 `/` 消息，除非注册为 Slash Command。`send_model_picker` 只在 Gateway 内部调用 `handle_model_command()` 时触发，而 Mattermost 的 `/model` 永远到不了这一步。

**修复**：必须注册 Slash Command，通过 `/mm-command` 端点处理。

### Pitfall 15：Slash Command 响应以用户身份发送（显示用户头像）

**症状**：Slash Command 返回 `in_channel` 响应后，消息显示触发用户的头像和名称，而非 Bot。

**根因**：Mattermost 的 Slash Command 响应机制——`in_channel` 类型的响应以触发用户身份发帖。

**修复**：Slash Command 只返回 `ephemeral`（用户可见但自动消失），实际卡片通过 `Bot API _api_post("posts", ...)` 发帖。

### Pitfall 16：Interactive Message 按钮超过 5 个时不渲染

**症状**：13 个模型按钮只有前 5 个可见，其余消失。

**根因**：Mattermost 限制每个 attachment 最多 5 个 actions。

**修复**：cards.py 中 `render_model_selector_card` 自动将按钮按 5 个一组拆分到多个 attachment。

### Pitfall 17：模型切换后实际未生效（session_key 错误）

**症状**：点击模型按钮后显示"切换成功"，但下次对话仍使用旧模型。

**根因**：session_key 构建时 root_id 不正确。MM Slash Command payload 包含 `root_id` 字段——在 Channel 顶层为空，在 Thread 中为 root post ID。必须正确传递 `root_id` 到 `_build_session_key()`，否则 override 写入的 key 与 Gateway 读取的 key 不匹配。

**修复**：直接从 Slash Command payload 读取 `root_id`：

```python
root_id = params.get("root_id", "") or None
session_key = self._build_session_key(channel_id, root_id)
```

**⚠️ Channel 顶层 vs Thread**：root_id=None 时 session_key 不含 thread 后缀，`_post_card_in_thread` 不设置 `root_id`，卡片发到 Channel 顶层（不创建 Thread）。

### Pitfall 18：Callback Server `_handler` 异常吞噬 — 静默空回复

**症状**：curl 测试 callback server 返回空回复（exit code 52），Gateway 日志中无任何错误记录。

**根因**：插件 `adapter.py` 的 `_handler` 函数中 `except Exception: writer.close()` 不记录任何日志，也不返回错误响应。内部处理链中任何异常（如 ImportError、AttributeError）都被完全吞噬。

**修复**：`except` 块中添加 `logger.exception()` + 返回 `{"ephemeral_text": "⚠️ Internal error"}`：

```python
except Exception:
    logger.exception("Unhandled error in callback server handler")
    try:
        err_body = json.dumps({"ephemeral_text": "⚠️ Internal error"}).encode("utf-8")
        err_resp = (
            f"HTTP/1.1 200 OK\r\n"
            f"Content-Type: application/json\r\n"
            f"Content-Length: {len(err_body)}\r\n\r\n"
        ).encode("utf-8") + err_body
        writer.write(err_resp)
        await writer.drain()
    except Exception:
        pass
    writer.close()
```

**诊断方法**：如果 callback server 返回空回复或连接重置，直接查看 `gateway.error.log`：
```bash
tail -20 ~/.hermes/logs/gateway.error.log
```
插件 logger 名为 `hermes_plugins.mattermost_approval.adapter`，异常日志会出现在 error log 中。

### Pitfall 19：插件引用不存在的函数 — 隐藏的 ImportError

**症状**：`/model` 或 `/new` 命令在 MM 中无响应或报"命令失败"，curl 测试 callback server 返回空回复。

**根因**：插件代码中 `from .models import _resolve_provider_for_model` 引用了一个**未实现的函数**。Python 在模块加载时不会报错（延迟导入），而是在函数调用时抛出 `ImportError: cannot import name '_resolve_provider_for_model'`。此异常被 Pitfall 18 的 `_handler` 吞噬。

**修复**：确保所有 `from .xxx import yyy` 中引用的函数/类都已在对应模块中定义。**验证方法**：

```bash
# 在 Gateway venv 中测试插件模块导入
source ~/.hermes/hermes-agent/venv/bin/activate
cd ~/.hermes/hermes-agent
python3 -c "
import sys; sys.path.insert(0, '.')
from hermes_cli.plugins import discover_plugins
discover_plugins()
# 如果有 ImportError，会在此处暴露
"
```

**根因模式**：开发计划中规划了函数但实现时遗漏，导入语句引用了不存在的符号。所有插件内部的 `from .module import func` 都应该有对应的实际定义。

### Pitfall 20：Slash Command URL 通过 Bot API 返回空值（权限不足）

**症状**：通过 `GET /api/v4/commands/{id}` 查询 Slash Command 配置，返回 `url: ""`, `token: ""`, `method: ""`，但命令实际工作正常。

**根因**：Bot token 的角色为 `system_user system_post_all`，不是 `system_admin`。MM API 对非管理员用户屏蔽了 Slash Command 的敏感字段（`url`, `token`）。数据库中实际存储了正确的值，但 API 返回时被过滤。

**修复/验证**：直接查询 PostgreSQL 数据库：

```bash
docker exec mm-postgres psql -U mmuser -d mattermost -c \
  "SELECT Trigger, Method, Url, Token FROM Commands WHERE Trigger IN ('new', 'model');"
```

**更新 Slash Command 配置的替代方案**：当 Bot 缺少 admin 权限时：
1. **System Console**：以管理员身份登录 Web UI → Integrations → Slash Commands 编辑
2. **数据库直接更新**：`docker exec mm-postgres psql -U mmuser -d mattermost -c "UPDATE Commands SET url='http://host.docker.internal:18065/mm-command', method='P' WHERE trigger='model';"`
3. **管理员 token**：获取 `system_admin` 角色用户的 personal access token 来调用 API

### Pitfall 21：Gateway 插件发现异常被 debug 级别日志吞噬

**症状**：插件在 `config.yaml` 中已启用，但 Gateway 启动日志中无任何插件发现记录，运行时使用内置适配器而非插件版本。

**根因**：Gateway 启动时调用 `discover_plugins()` 在 try/except 中，异常只记录 debug 级别日志。如果插件加载失败（如 ImportError），Gateway 正常启动但使用内置适配器，用户无感知。

**诊断方法**：
1. 检查 gateway 日志是否有 "callback server on" 记录（插件版本会显示 `/mm-command` 路由）
2. 手动运行插件发现测试：
   ```bash
   source ~/.hermes/hermes-agent/venv/bin/activate
   python3 -c "
   import logging; logging.basicConfig(level=logging.DEBUG)
   from hermes_cli.plugins import discover_plugins
   discover_plugins()
   "
   ```
3. 对比 `gateway.log` 中的 logger name：内置 = `gateway.platforms.mattermost`，插件 = `hermes_plugins.mattermost_enhancer.adapter`

### Pitfall 22：Slash Command URL 为空时 MM 降级为 WebSocket 消息

**症状**：`/new` 命令"部分工作"——显示重复消息（标题/重置确认出现两遍），回复发到错误 thread，消息以用户身份发送。

**根因**：当 Slash Command 的 `url` 字段为空时，Mattermost 无法发送 HTTP POST 回调。MM 将 `/new` 作为**普通文本消息**通过 WebSocket 发送给 Gateway。Gateway 内置的 `/new` 命令处理器（`_handle_reset_command`）直接执行重置 + 返回 `EphemeralReply`。这导致了：
- **双重显示**：MM 自身的 Slash Command 反馈 + Gateway 内置处理器的 EphemeralReply
- **错误 thread**：内置处理器使用 session 路由逻辑，可能指向不同的 thread
- **用户头像**：通过 WS 路径的消息以用户身份处理

**修复**：确保 Slash Command 的 `url` 和 `method` 正确配置，MM 通过 HTTP POST 路由到插件 callback server，而非通过 WebSocket 降级。

### Pitfall 47：按钮 action_id 含特殊字符 — 回调报「找不到该页面」

**症状**：点击交互卡片按钮后，Mattermost 显示 "对不起，我们找不到该页面"。按钮无响应，卡片停留在原位。

**根因**：Mattermost Interactive Message 的 `action.id` 字段**只能包含字母数字**。下划线（`_`）、连字符（`-`）等特殊字符会导致 MM 无法路由回调。

- ❌ `clarify_abc123_0` → MM 报 "找不到该页面"
- ❌ `clarify-abc123` → 同样报错
- ✅ `clarifyabc12300` → 正常触发回调

**修复**：所有 action_id 使用纯字母数字，不用任何分隔符。与 Pitfall 4（Slash Command `action.id` 限制）同一根源——Mattermost 对 action id 字段有字符集限制。

**影响范围**：所有动态生成 action_id 的场景（如 clarify 卡片每个选项按钮的 id）。固定 id（如 `cmdmodelselect`、`cmdnewconfirm`）不受影响。

## 卡片更新机制与消息重复

### Interactive Message update 响应格式

当用户点击按钮后，callback server 返回 `{"update": {...}}` 来更新原始卡片消息。MM 的渲染规则：

| 字段 | 渲染行为 |
|------|---------|
| `update.message` | 显示为消息正文 |
| `update.props.attachments` | 额外渲染为附件卡片（含 pretext、text、color 等） |

**关键**：如果 `message` 和 `props.attachments` 包含相同/重叠的内容，用户会看到**两遍**。

### 错误示例（导致重复显示）

```python
# _handle_new_confirm_callback 返回:
return {
    "update": {
        "message": "✅ 会话已重置\n对话上下文已清空，新会话已创建",  # ← 正文
        "props": render_reset_success_card(),  # ← 附件又有 "✅ 会话已重置" + "新会话已创建..."
    },
}
```

用户看到：正文显示 "✅ 会话已重置\n对话上下文已清空，新会话已创建"，附件卡片又显示 pretext="✅ 会话已重置" + text="新会话已创建，对话上下文已清空。"

### 正确做法

**方案 A**：`message` 留空或只放简短确认，完整内容放 `props`：
```python
return {"update": {"message": "", "props": card}}
```

**方案 B**：只在 `message` 中放内容，`props` 为空：
```python
return {"update": {"message": "✅ 会话已重置\n对话上下文已清空，新会话已创建", "props": {}}}
```

### Pitfall 23：switch_model 路由 custom_provider 模型到错误 provider

**症状**：模型切换卡片显示"切换成功"，但下次对话仍使用默认模型。日志中 `target_provider` 为 `openrouter` 而非期望的 `zenmux`，`api_key` 为空。

**根因**：`hermes_cli.model_switch.switch_model()` 的解析链不知道 `custom_providers` 的模型映射关系。`deepseek/deepseek-v4-pro` 的 `deepseek/` 前缀被识别为 openrouter 的 vendor slug，而非用户实际使用的 custom_provider（如 `zenmux`）。即使传入 `explicit_provider`，`switch_model()` 的内部路由逻辑仍可能产生错误的 `api_key`。

**最终修复**：**完全绕过 `switch_model()`**，直接从 `custom_providers` 配置构建 session override：

```python
from .models import resolve_provider_config
prov_cfg = resolve_provider_config(provider_name)  # 直接读 custom_providers

if prov_cfg:
    runner._session_model_overrides[session_key] = {
        "model": model_id,
        "provider": prov_cfg["provider"],      # e.g. "zenmux"
        "base_url": prov_cfg["base_url"],      # e.g. "https://zenmux.ai/api/v1"
        "api_key": prov_cfg["api_key"],         # 从 ${ENV_VAR} 解析后的实际值
        "api_mode": prov_cfg["api_mode"],       # e.g. "chat_completions"
    }
    runner._evict_cached_agent(session_key)     # ← 必须！否则缓存的 Agent 不刷新
```

`resolve_provider_config()` 直接遍历 `custom_providers`，按 `name` 字段匹配（**不是** `slug` — config.yaml 用 `name`），解析 `${ENV_VAR}` 格式的 api_key，返回完整的连接配置。仅在 provider 不在 `custom_providers` 中时才回退到 `switch_model()`。

**⚠️ `custom_providers` 字段名是 `name` 不是 `slug`**：`cp.get("slug")` 返回空！必须用 `cp.get("name", "")`。

### Pitfall 24：Bot API 帖子 message + props 双重显示

**症状**：卡片标题（如"🆕 创建新会话"）出现两遍——正文一遍 + 附件卡片一遍。

**根因**：`_post_card_in_thread()` 把 pretext 同时写入 `message` 和 `props.attachments`。Mattermost 渲染帖子时**同时显示** `message`（正文）和 `props.attachments`（附件），内容重叠即重复。同样的问题也出现在 callback update 响应中。

**修复**：两个位置都要处理：

1. **Bot API 发帖**：`message` 留空，所有可见内容只在 `props.attachments` 中：
```python
payload = {
    "channel_id": channel_id,
    "message": "",  # ← 留空！避免与 props 重复
    "props": {"attachments": attachments},
}
```

2. **Callback update 响应**：只在 `message` 或 `props` 之一放内容：
```python
# 方案 A：message 放内容，props 清空
return {"update": {"message": "✅ 会话已重置", "props": {}}}

# 方案 B：message 留空，内容放 props（适用于需要卡片格式时）
return {"update": {"message": "", "props": card}}
```

### Pitfall 25：模型选择器用 select 下拉列表替代多行按钮

**症状**：13+ 模型按钮分成 3 行 attachment，排列混乱，用户难以定位目标模型。

**根因**：Mattermost 限制每 attachment 最多 5 个 button action，13 个模型需要 3 个 attachment。按钮名含 provider 前缀（如 `deepseek/deepseek-v4-pro`），无分类。

**修复**：使用 Mattermost 的 `select` 类型 action（下拉列表），所有模型在一个下拉框中：

```python
def _make_select(action_id, name, options, context, callback_url):
    return {
        "id": action_id,
        "name": name,
        "type": "select",       # ← 下拉列表
        "options": options,      # [{"text": "显示名", "value": "model_id"}, ...]
        "integration": {
            "url": callback_url,
            "context": context,  # 共享 context（不含 model_id）
        },
    }
```

选项格式：
- 完整 provider/model 格式：`zenmux/minimax-m2.7`
- 当前模型标记 ★ 前缀：`★ zenmux/minimax-m2.7`
- `name` 字段作为 placeholder（未展开时的显示文本）：`"当前: zenmux/minimax-m2.7"`
- 按 provider 排列，同一 provider 的模型连续

**优势**：1 个 attachment + 1 个 action，不再受 5 按钮限制；UI 更整洁。

**⚠️ 配套修改**：select 的回调格式与 button 不同（见 P28）。

### Pitfall 26：模型切换 api_key 为空时 override 不生效

**症状**：`switch_model()` 返回 `success=True`，`_session_model_overrides` 中写入了 override，但下次对话仍使用默认模型。

**根因**：Gateway 的 `_resolve_gateway_model()` 检查 override 时，要求 `api_key` 非空才应用 override。当 `switch_model()` 路由到错误 provider 时，`api_key` 为空，override 被写入但永远不生效。

**最终修复**：与 P23 合并——绕过 `switch_model()`，直接从 `custom_providers` 配置构建 override，确保 `api_key` 始终有值。

**诊断方法**：如果模型切换后仍使用默认模型，检查：
```python
override = runner._session_model_overrides.get(session_key, {})
print(f"provider: {override.get('provider')}")   # 应为 "zenmux"，不是 "openrouter"
print(f"api_key: {len(override.get('api_key', ''))}")  # 应 > 0
```

### Pitfall 27：Slash Command HTTP 响应以用户身份显示（用户头像）

**症状**：`/model` 或 `/new` 命令后，"🔄 模型选择器已发送"或"🆕 会话重置确认已发送"消息显示触发用户的头像和名称，而非 Bot。

**根因**：Mattermost 的 Slash Command HTTP 响应机制——无论 `response_type` 是 `ephemeral` 还是 `in_channel`，响应消息都以触发用户身份显示。这是 MM 的设计限制，无法通过 `response_type` 控制。

**修复**：Slash Command 处理函数返回空 `{}`（完全无可见响应），所有可见内容通过 Bot API `_api_post("posts", ...)` 发帖到 thread：
```python
async def _handle_model_command(self, channel_id, user_id):
    # ... 构建 card ...
    await self._post_card_in_thread(channel_id, root_id, card)  # Bot API 发帖 → Bot 头像
    return {}  # 空 ephemeral — MM 不显示任何内容
```

### Pitfall 28：select 下拉列表回调用 selected_option 非 model_id

**症状**：select 下拉列表选择模型后，回调返回 "Missing model_id or session context"，切换失败。

**根因**：Mattermost 的 select 类型 action 回调格式与 button 不同：
- **button 回调**：`context.model_id` 包含按钮关联的模型 ID（在卡片构建时注入）
- **select 回调**：`context.selected_option` 包含用户选择的 option value（MM 自动添加），**没有** `context.model_id`

```python
# ❌ 只读 model_id（select 回调中没有此字段）
model_id = context.get("model_id", "")

# ✅ 兼容 select 和 button 两种模式
model_id = context.get("selected_option", "") or context.get("model_id", "")
```

**配套修改**：
1. `_inject_model_context()` 需区分 action 类型：select 的 context 是共享的，只注入 `session_key`（不注入 `model_id`/`provider_name`，因为每个选项不同）
2. 回调处理时，若 `provider_name` 为空（select 模式），通过 `_resolve_provider_for_model(model_id)` 自动补全

### Pitfall 30：LLM 自报模型错误 — 模型切换实际生效但 LLM 不知道

**症状**：`/model` 切换后显示"✅ 模型已切换: minimax-m2.7 → deepseek-v4-pro"，但用户问"当前模型是什么"时 LLM 回答仍为 minimax-m2.7。用户误认为切换失败，但实际上 API 调用已使用 deepseek-v4-pro。

**根因**：Gateway 的 `_resolve_session_agent_runtime()` 正确读取了 `_session_model_overrides` 并将 override 传给 AIAgent，LLM **确实在用新模型推理**。但 LLM 的自我认知（"我是 XX 模型"）来自系统提示中的配置信息，而非运行时 override。Gateway 内置的 `/model` 命令通过 `_pending_model_notes` 机制解决此问题——在模型切换后，向 session 注册一条 note，Gateway 在处理下一条消息时自动将此 note 前置注入到用户消息中：

```
[Note: model was just switched from minimax/minimax-m2.7 to deepseek/deepseek-v4-pro via zenmux. Adjust your self-identification accordingly.]

<用户实际消息>
```

**但插件的 `_switch_session_model()` 绕过了 Gateway 内置的 `/model` 处理路径**，直接写入 `_session_model_overrides`，**没有设置 `_pending_model_notes`**，导致 LLM 永远不知道自己被切换了。

**修复**：在 `_switch_session_model()` 中，写入 override 后同时设置 `_pending_model_notes`：

```python
# 注入 model note — 让 LLM 知道自己被切换了
if not hasattr(runner, "_pending_model_notes"):
    runner._pending_model_notes = {}

_verify = runner._session_model_overrides.get(session_key, {})
_new_provider = _verify.get("provider", provider_name)
runner._pending_model_notes[session_key] = (
    f"[Note: model was just switched from {old_model} to {model_id} "
    f"via {_new_provider}. "
    f"Adjust your self-identification accordingly.]"
)
```

**⚠️ `prov_cfg` 在 switch_model 回退路径中为 None**：`_pending_model_notes` 的注入必须在两条路径汇合之后，且从 `_session_model_overrides` 读取 provider（而非从 `prov_cfg`），否则回退路径会触发 `None.get()` 异常。

**诊断方法**：当用户报告"模型切换后仍用旧模型"时，先检查 API 调用日志而非 LLM 自报信息：
```bash
# 查看实际 API 调用使用的模型（这是真实证据）
grep 'API call\|model=' ~/.hermes/logs/agent.log | grep -E 'model=(deepseek|minimax)' | tail -5

# 检查 Gateway 是否读取了 override（需临时将 debug 改为 info）
grep 'Session model override' ~/.hermes/logs/agent.log | tail -3
```

**诊断技巧**：Gateway 的 `_resolve_session_agent_runtime()` 中 override 读取日志默认为 `debug` 级别，不会出现在日志文件中。临时将其改为 `info` 可以验证 override 是否被读取。修改后务必改回 `debug`。

### Pitfall 29：日志截断 [:60] 误判 session_key 不匹配

**症状**：日志显示插件 session_key 以 `:twcry` 结尾（5 字符 root_id），而 Gateway 以 `:twcryzndejf15px8cuhy43sx4a` 结尾（26 字符），误认为 session_key 不匹配导致 override 不生效。

**根因**：日志语句使用 `session_key[:60]` 截断显示。`agent:main:mattermost:group:<26字符channel_id>:<26字符root_id>` 总长 81 字符，截断为 60 后 root_id 只剩 5 字符，看起来和 Gateway 的完整 key 不一致。**实际上存储的 override key 是完整的**，只是日志显示被截断。

**修复**：去掉日志中的 `[:60]` 截断，显示完整 session_key：
```python
# ❌ 截断导致误判
logger.info("Model switched: session=%s", session_key[:60])

# ✅ 完整显示
logger.info("Model switched: session=%s", session_key)
### Pitfall 34：插件迁移后双重 callback server 启动 — 端口冲突导致 DM 审批失效

**症状**：插件化迁移完成后，DM 审批卡片不再弹出，Gateway 日志中出现 `OSError: [Errno 48] Address already in use` 或 callback server 启动失败。

**根因**：源文件 `mattermost.py` 仍保留 patch 7c 的残留——`connect()` 中调用了 `await self._start_callback_server()`。插件覆写 `connect()` 时调用 `super().connect()` 触发源文件的 callback 启动，然后插件自己也调用 `await self._start_callback_server()`，导致同一端口启动两次。

**调用链**：
```
插件 connect()
  → super().connect()           # 源文件 connect() (patch 7c 残留)
    → _start_callback_server()  # 第 1 次 — 成功绑定端口 18065
  ← 返回 True
  → _start_callback_server()    # 第 2 次 — 端口冲突！
```

**修复**：先回滚源文件至上游（`git show a91a57fa5:gateway/platforms/mattermost.py`），再让插件独立处理所有逻辑。插件保持 `connect()` 中 `super().connect()` + 自己的 `_start_callback_server()`，源文件不干涉。

**迁移检查清单**（每次将 patch 从源文件迁移到插件后）：
1. `grep "Hermes Patch" gateway/platforms/mattermost.py` — 应返回 0 匹配
2. `grep "_callback_server\|_resolve_root_id\|send_exec_approval" gateway/platforms/mattermost.py` — 应返回 0 匹配
3. 源文件行数应与上游一致（`git show a91a57fa5:gateway/platforms/mattermost.py | wc -l`）
4. `bash -n hermes-patches.sh` — 语法检查
5. 重启 Gateway 后 `grep "callback server on" gateway.log` — 应只有一条日志

### Pitfall 35：`patch` 工具在 heredoc/f-string 大块删除时损坏文件

**症状**：使用 `patch(mode='replace')` 删除 `hermes-patches.sh` 中上百行的 `_do_patch` 块时，工具只删除了匹配的前几行，将剩余的 Python heredoc 代码裸露为非法 shell 脚本。

**根因**：`patch` 工具的 fuzzy matching 在遇到含 `\n`、`'''` triple-quote、f-string 花括号（`{variable}`）的文本时，escape 处理产生偏移，只匹配并删除了部分内容。

**修复**：使用 `execute_code` + Python 的 line-based slicing 删除大块内容：

```python
with open('hermes-patches.sh') as f:
    lines = f.readlines()
# 精确删除 L524-L1015（patch 7 block）
del lines[523:1015]
with open('hermes-patches.sh', 'w') as f:
    f.writelines(lines)
```

**关键原则**：对于 shell 脚本的大块修改（>20 行），**永远优先用 `execute_code` + line slicing**，不用 `patch` 工具。

**症状**：在 Channel 顶层输入 `/model`，卡片被发到最近的 Thread 中；session_key 包含错误的 thread 后缀。

**根因**：旧代码假设 MM Slash Command payload 不含 `root_id`，实现了 `_find_user_thread_root_id()` 通过 API 反查用户最近帖子来判断上下文。反查逻辑有多个缺陷：
1. 只遍历有 `root_id` 的帖子 → 跳过 Channel 顶层的帖子 → 总是路由到 Thread
2. HTTP 回调时序问题 → API 返回旧帖子 → 上下文判断错误
3. 回退搜索 Bot 帖子 → 进一步加剧误判

**实际发现**：MM Slash Command payload **原生包含 `root_id` 字段**！在 Thread 中发送时 `root_id=<root_post_id>`，在 Channel 顶层发送时 `root_id=`（空字符串）。不需要任何 API 反查。

**修复**：直接从 payload 读取 `root_id`，删除 `_find_user_thread_root_id()`：

```python
# ✅ 直接从 payload 读取
root_id = params.get("root_id", "") or None  # Channel → None, Thread → root_post_id

# 传递给 handler
if command == "model":
    return await self._handle_model_command(channel_id, user_id, root_id)
elif command == "new":
    return await self._handle_new_command(channel_id, user_id, root_id)
```

**⚠️ `_post_card_in_thread` 的行为**：`root_id=None` 时不设置 `payload["root_id"]`，帖子发到 Channel 顶层（不创建 Thread）。`root_id` 非空时帖子发到对应 Thread。

**⚠️ `_build_session_key` 的行为**：`root_id=None` 时 session_key 为 `agent:main:mattermost:group:<channel_id>`（无 thread 后缀）。
