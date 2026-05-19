# Mattermost 统一插件开发计划

> 关联文档：[hermes-patches-migration-plan.md](./hermes-patches-migration-plan.md) — 上游 PR 迁移总路线图
>
> 创建时间：2026-05-19 | 状态：规划中

## 1. 目标

将当前 `hermes-patches.sh` 中的 DM 审批逻辑（patches 7a-7d, ~400 行）迁移为 Hermes Platform Plugin，
并在此基础上扩展 `/model`（切换模型）和 `/new`（重置会话）的 Interactive Message 卡片交互。

**最终愿景：零源码修改，一个插件覆盖所有 Mattermost 自定义能力。**

## 2. 架构概览

```
┌──────────────────────────────────────────────────────────────────┐
│                    Mattermost 服务端                               │
│                                                                  │
│  System Console → 自定义 Slash 指令                               │
│    /model → POST http://host:18065/mm-command                    │
│    /new   → POST http://host:18065/mm-command                    │
│                                                                  │
│  Interactive Message 按钮回调（DM 审批 + /model + /new）          │
│    → POST http://host:18065/mm-callback                          │
└──────────────────────────────┬───────────────────────────────────┘
                               │
                               ▼
┌──────────────────────────────────────────────────────────────────┐
│             Hermes Plugin: mattermost-approval                    │
│                                                                  │
│  plugin.yaml: kind=platform, min_hermes_version=2.0.0            │
│                                                                  │
│  __init__.py:                                                    │
│    register_platform(name="mattermost", priority=100)            │
│    → 覆盖内置 MattermostAdapter                                   │
│                                                                  │
│  adapter.py:                                                     │
│    MattermostApprovalAdapter(MattermostAdapter)                  │
│      ├ connect()    → super() + _start_callback_server()         │
│      ├ disconnect() → _stop_callback_server() + super()          │
│      ├ send_exec_approval() → 渲染 DM 审批卡片                    │
│      └ _resolve_root_id() → CRT Thread root_id 修正              │
│                                                                  │
│  callback_server.py (aiohttp, port 18065):                       │
│    POST /mm-callback → _handle_approval_callback()               │
│    POST /mm-command  → _handle_slash_command()                   │
│                         ├ command=model → 渲染模型选择卡片         │
│                         └ command=new   → 渲染确认卡片            │
│                                                                  │
│  cards.py:                                                       │
│    render_approval_card()           → 4 按钮（审批）              │
│    render_model_selector_card()     → N 按钮（模型列表）          │
│    render_new_session_confirm_card()→ 2 按钮（确认/取消）         │
│                                                                  │
│  models.py:                                                      │
│    get_available_models()  → 从 config.yaml + providers 获取     │
│    validate_model_id()     → 合法性校验                          │
│    get_current_model()     → 获取当前 session 模型               │
└──────────────────────────────────────────────────────────────────┘
```

## 3. 插件目录结构

```
~/.hermes/plugins/mattermost-approval/
├── plugin.yaml              # 插件元数据
├── __init__.py              # 入口：register_platform()
├── adapter.py               # MattermostApprovalAdapter 类
├── callback_server.py       # HTTP callback 服务器（aiohttp）
├── cards.py                 # Interactive Message 卡片渲染
├── models.py                # 模型列表管理
├── session.py               # Session 定位与操作
└── references/
    └── api-contracts.md     # Mattermost Slash Command / Interactive Message API 契约
```

## 4. 接口契约

### 4.1 Mattermost 自定义 Slash 指令 POST

```
POST /mm-command
Content-Type: application/x-www-form-urlencoded

token=xxx
team_id=xxx
team_domain=xxx
channel_id=xxx
channel_name=xxx
user_id=xxx
user_name=xxx
command=/model              # 或 /new
text=                       # 指令后的文本（可选）
trigger_id=xxx
```

**响应**：直接返回 Interactive Message JSON（Mattermost 支持 Slash Command 响应中返回 `attachments`）。

### 4.2 Interactive Message 按钮回调 POST

```
POST /mm-callback
Content-Type: application/json

{
  "type": "interactive_message",
  "callback_id": "hermes_command",
  "action": "cmd_model_switch",      # 或 cmd_new_confirm / cmd_new_cancel / approve_once 等
  "context": {
    "model_id": "deepseek/deepseek-v4-pro",
    "session_key": "mattermost:channel:xxx:root_xxx"
  },
  "channel_id": "xxx",
  "user_id": "xxx",
  "post_id": "xxx",
  "root_id": "xxx"
}
```

### 4.3 卡片 action 命名约定

沿用已有 DM 审批的 action 格式（纯字母）：

| action | 功能 | context 参数 |
|--------|------|------------|
| `approveonce` | 允许本次 | `command_id` |
| `approvesession` | 本 session 全部允许 | `command_id` |
| `approvealways` | 永久允许 | `command_id` |
| `deny` | 拒绝本次 | `command_id` |
| `cmdmodelswitch` | 切换模型 | `model_id`, `session_key` |
| `cmdnewconfirm` | 确认创建新会话 | `session_key` |
| `cmdnewcancel` | 取消创建新会话 | - |

## 5. 核心类设计

### 5.1 MattermostApprovalAdapter

```python
from gateway.platforms.mattermost import MattermostAdapter

class MattermostApprovalAdapter(MattermostAdapter):
    """继承内置 MattermostAdapter，追加 DM 审批 + Slash 指令卡片交互能力
    """

    # ── 生命周期 ──────────────────────────────────

    async def connect(self):
        result = await super().connect()
        if result:
            await self._start_callback_server()
        return result

    async def disconnect(self):
        await self._stop_callback_server()
        await super().disconnect()

    # ── CRT Thread root_id 修正 ────────────────────

    async def _resolve_root_id(self, post_id: str) -> str:
        """向上遍历找到 Thread 根帖子 ID"""
        ...

    # ── DM 审批 ────────────────────────────────────

    async def send_exec_approval(self, source, command, ...) -> SendResult:
        """发送 DM 审批卡片到用户"""
        ...

    # ── 异常处理 ────────────────────────────────────
    # （覆盖父类方法以处理 MMP 特定异常）

    # ... 其他从 patch 7 迁移的方法
```

### 5.2 CallbackServer

```python
class CallbackServer:
    """HTTP 回调服务器，处理 Mattermost Interactive Message 回调"""

    def __init__(self, adapter, host, port):
        self._app = web.Application()
        self._app.router.add_post('/mm-callback', self._handle_approval)
        self._app.router.add_post('/mm-command', self._handle_slash_command)

    async def _handle_approval(self, request) -> web.Response:
        """处理 DM 审批 / /model / /new 按钮回调"""
        payload = await request.json()
        action = payload.get('action', '')

        if action.startswith('cmdmodel') or action.startswith('cmdnew'):
            return await self._handle_command_action(payload)
        else:
            return await self._handle_approval_action(payload)

    async def _handle_slash_command(self, request) -> web.Response:
        """处理 Mattermost 自定义 Slash 指令 POST"""
        data = await request.post()
        command = data.get('command', '').lstrip('/')

        if command == 'model':
            return web.json_response(
                render_model_selector_card(channel_id=..., user_id=...)
            )
        elif command == 'new':
            return web.json_response(
                render_new_session_confirm_card(channel_id=..., user_id=...)
            )
```

## 6. 卡片 UI 设计

### 6.1 模型选择卡片 (`/model`)

```
┌─────────────────────────────────────────────┐
│ 🔄 切换模型                                  │
│ 当前 session 模型：deepseek/deepseek-v4-pro  │
├─────────────────────────────────────────────┤
│ [deepseek/deepseek-v4-pro]  ← 当前（高亮）   │
│ [claude-sonnet-4.6]                         │
│ [doubao-seed-2.0-pro]                       │
│ [gemini-3.1-flash]                          │
│ [gpt-5.5]                                   │
│                                             │
│ ⚠️ 仅影响当前 Thread，其他 Thread 不受影响    │
└─────────────────────────────────────────────┘
```

**Mattermost Attachment JSON 结构：**
```json
{
  "attachments": [{
    "pretext": "🔄 切换模型",
    "text": "当前 session 模型：**deepseek/deepseek-v4-pro**",
    "actions": [
      {
        "id": "cmdmodelswitch",
        "name": "deepseek/deepseek-v4-pro",
        "style": "primary",
        "integration": {
          "url": "http://host:18065/mm-callback",
          "context": {
            "action": "cmdmodelswitch",
            "model_id": "deepseek/deepseek-v4-pro",
            "session_key": "mattermost:channel:xxx:root_xxx"
          }
        }
      },
      {
        "id": "cmdmodelswitch",
        "name": "claude-sonnet-4.6",
        "integration": {
          "url": "http://host:18065/mm-callback",
          "context": {
            "action": "cmdmodelswitch",
            "model_id": "claude-sonnet-4.6",
            "session_key": "..."
          }
        }
      }
    ],
    "footer": "⚠️ 仅影响当前 Thread"
  }]
}
```

> **Pitfall 提醒**（来自现有 DM 审批经验）：
> - action `id` 必须纯字母（`cmdmodelswitch`），禁止连字符
> - `integration` 在 Bot API 响应中会被 `StripActionIntegrations()` 剥离，但在 DB 中保留 → 回调时有效
> - `context.action` 使用下划线格式（`cmd_model_switch`），与 `choice_map` 匹配

### 6.2 新会话确认卡片 (`/new`)

```
┌─────────────────────────────────────────────┐
│ 🆕 创建新会话                                │
│ 将重置当前 session 的对话上下文               │
│ ⚠️ 之前的对话历史将丢失                       │
├─────────────────────────────────────────────┤
│ [✅ 确认重置]  [❌ 取消]                      │
│                                             │
│ 💡 Thread 模式下直接发新消息即可创建新会话     │
└─────────────────────────────────────────────┘
```

**Mattermost Attachment JSON 结构：**
```json
{
  "attachments": [{
    "pretext": "🆕 创建新会话",
    "text": "将重置当前 session 的对话上下文\n⚠️ 之前的对话历史将丢失",
    "actions": [
      {
        "id": "cmdnewconfirm",
        "name": "✅ 确认重置",
        "style": "danger",
        "integration": {
          "url": "http://host:18065/mm-callback",
          "context": {
            "action": "cmd_new_confirm",
            "session_key": "mattermost:channel:xxx:root_xxx"
          }
        }
      },
      {
        "id": "cmdnewcancel",
        "name": "❌ 取消",
        "integration": {
          "url": "http://host:18065/mm-callback",
          "context": {
            "action": "cmd_new_cancel"
          }
        }
      }
    ],
    "footer": "💡 Thread 模式下直接发新消息即可创建新会话"
  }]
}
```

### 6.3 操作完成确认卡片

切换模型成功后的即时反馈：

```
┌─────────────────────────────────────────────┐
│ ✅ 模型已切换                                │
│ deepseek/deepseek-v4-pro → claude-sonnet-4.6 │
│ 当前 Thread 内生效                           │
└─────────────────────────────────────────────┘
```

## 7. Session 作用域操作实现

### 7.1 Session 定位

```python
def _locate_session(self, channel_id: str, root_id: str = None) -> str:
    """从 callback payload 定位 session_key"""
    if root_id and self._config.reply_mode == 'thread':
        # CRT Thread 模式：session key = channel:root_id
        return f"mattermost:channel:{channel_id}:{root_id}"
    else:
        # 扁平模式：session key = channel
        return f"mattermost:channel:{channel_id}"
```

### 7.2 模型切换

```python
async def _switch_model(self, session_key: str, model_id: str):
    """切换指定 session 的模型（仅影响当前 session）"""
    # 1. 校验 model_id 合法性
    available = get_available_models()
    if model_id not in available:
        raise ValueError(f"Unknown model: {model_id}")

    # 2. 获取 session store
    session_store = self._get_session_store()

    # 3. 修改 session 的 model 配置
    # 注意：这里的实现取决于 Hermes 的 session model 存储方式
    # 可能需要通过 session metadata 或独立的 model mapping 表
    session = await session_store.get_session(session_key)
    session.metadata['model'] = model_id
    await session_store.update_session(session_key, session)

    # 4. 通知用户
    await self._send_card_response(
        channel_id=session.channel_id,
        card=render_switch_success_card(old_model, model_id)
    )
```

### 7.3 Session 重置

```python
async def _reset_session(self, session_key: str):
    """重置指定 session 的对话上下文"""
    session_store = self._get_session_store()
    await session_store.reset_session(session_key)

    await self._send_card_response(
        channel_id=channel_id,
        card=render_reset_success_card()
    )
```

## 8. 迁移步骤

### 阶段一：环境准备

- [ ] 确认 `~/.hermes/plugins/` 目录存在
- [ ] 确认 Hermes 版本 ≥ 2.0.0（支持 `register_platform`）
- [ ] 确认 `plugins.enabled` 机制已理解（需在 config.yaml 中添加 `mattermost-approval`）

### 阶段二：DM 审批迁移（核心）

- [ ] 创建插件目录骨架：`mattermost-approval/`
- [ ] 编写 `plugin.yaml`
- [ ] 将 patches 7a-7d 的代码迁移到 `adapter.py`（继承 `MattermostAdapter`）
  - [ ] `_resolve_root_id()`
  - [ ] `_start_callback_server()` / `_stop_callback_server()`
  - [ ] `_handle_callback()` / choice_map
  - [ ] `send_exec_approval()`
  - [ ] `connect()` / `disconnect()` 生命周期
- [ ] 将 callback server 独立为 `callback_server.py`
- [ ] 在 `__init__.py` 注册 platform override
- [ ] 在 `config.yaml` 的 `plugins.enabled` 中添加 `mattermost-approval`
- [ ] 重启 gateway，验证 DM 审批功能正常
- [ ] 从 `hermes-patches.sh` 移除 patches 7a-7d

### 阶段三：Slash 指令扩展

- [ ] 实现 `models.py`（模型列表获取 + 校验）
- [ ] 实现 `cards.py`（模型选择卡片 + 新会话确认卡片 + 成功确认卡片）
- [ ] 在 `callback_server.py` 新增 `/mm-command` 路由
- [ ] 实现 `_handle_slash_command()` → 分发 `/model` `/new`
- [ ] 实现 `_handle_command_action()` → 处理卡片按钮回调
  - [ ] `cmdmodelswitch` → 切换模型 + 发送确认卡片
  - [ ] `cmdnewconfirm` → 重置 session + 发送确认卡片
  - [ ] `cmdnewcancel` → 发送取消卡片
- [ ] 在 Mattermost System Console 配置 `/model` 和 `/new` 自定义 Slash 指令
- [ ] 端到端测试

### 阶段四：收尾

- [ ] 验证 `git pull` 升级后插件仍然生效
- [ ] 编写 `references/api-contracts.md`
- [ ] 更新 `hermes-patches-migration-plan.md` 状态

## 9. 验证清单

### DM 审批回归测试

- [ ] 危险命令触发 DM 审批卡片
- [ ] Allow Once → 本次通过，下次仍审批
- [ ] Allow Session → 本 session 不再审批
- [ ] Always Allow → 全局不再审批
- [ ] Deny → 拒绝本次执行
- [ ] 超时后按钮自动失效
- [ ] CRT Thread 模式下 root_id 正确

### Slash 指令功能测试

- [ ] `/model` 在 Thread 内触发 → 模型选择卡片正确渲染
- [ ] `/model` 选择模型 → 切换成功确认 + Thread 内后续对话使用新模型
- [ ] `/model` 在 Thread A 切换 → Thread B 模型不受影响
- [ ] `/new` 在扁平模式下触发 → 确认卡片正确渲染
- [ ] `/new` 确认 → Session 重置成功 + 确认反馈
- [ ] `/new` 取消 → 无操作

### 插件兼容性测试

- [ ] `git pull` 更新 Hermes 后插件仍然加载
- [ ] 内置 `MattermostAdapter` API 更新后插件不崩溃（`super()` 调用兼容）
- [ ] 插件加载失败时 gateway 仍然正常启动（内置适配器作为 fallback）

## 10. 风险与缓解

| 风险 | 概率 | 影响 | 缓解 |
|------|------|------|------|
| `register_platform` API 变更 | 低 | 高 | 锁定 `min_hermes_version`，升级前验证 |
| 内置 `MattermostAdapter` 重构 | 中 | 中 | 最小化覆写方法，其余 `super()` 调用 |
| callback server 端口冲突 | 低 | 中 | 通过 `MATTERMOST_CALLBACK_PORT` 环境变量配置 |
| 多个 plugin 注册同一 platform | 低 | 高 | 确保 `priority=100` 高于其他潜在覆盖 |
| `/model` 卡片模型列表与实际可用模型不同步 | 中 | 低 | 每次 `/model` 触发时实时查询 provider 列表 |
| Mattermost 自定义 Slash 指令仅支持 GET/POST，不支持 Interactive Message 直接响应 | 中 | 高 | 已验证：Slash Command 响应中可返回 `attachments` → Mattermost 客户端会渲染 Interactive Message |
