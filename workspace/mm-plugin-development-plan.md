# Mattermost 统一插件开发计划

> 关联文档：[hermes-patches-migration-plan.md](./hermes-patches-migration-plan.md) — 上游 PR 迁移总路线图
>
> 创建时间：2026-05-19 | 状态：✅ 已完成（v2.0.0，mattermost.py 源码零修改）

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
│    /model → POST http://host.docker.internal:18065/mm-command    │
│    /new   → POST http://host.docker.internal:18065/mm-command    │
│                                                                  │
│  Interactive Message 按钮回调（DM 审批 + /model + /new）          │
│    → POST http://host.docker.internal:18065/mattermost/callback  │
└──────────────────────────────┬───────────────────────────────────┘
                               │
                               ▼
┌──────────────────────────────────────────────────────────────────┐
│             Hermes Plugin: mattermost-enhancer                    │
│                                                                  │
│  plugin.yaml: kind=platform, min_hermes_version=2.0.0            │
│                                                                  │
│  __init__.py:                                                    │
│    register_platform(name="mattermost", adapter_factory=...)      │
│    → 覆盖内置 MattermostAdapter                                   │
│                                                                  │
│  adapter.py (~450 行):                                           │
│    MattermostApprovalAdapter(MattermostAdapter)                  │
│      ├ _start_callback_server() → asyncio 多路由                  │
│      │   POST /mattermost/callback → 按钮回调                     │
│      │   POST /mm-command          → Slash 指令                   │
│      ├ _route_callback() → 签名验证 + 分发                        │
│      ├ _route_slash_command() → 权限校验 + 分发                    │
│      ├ _handle_model_command() → 读 payload root_id + Bot API 发帖│
│      ├ _handle_new_command()   → 读 payload root_id + Bot API 发帖│
│      ├ _handle_callback() → 审批 + 模型切换 + 会话重置            │
│      ├ _post_card_in_thread() → Bot API 发帖（Bot 头像）         │
│      ├ _switch_session_model() → switch_model + session override │
│      ├ _reset_session() → 清除 override + agent cache            │
│      └ send_typing() (override) → 父类 Bug 修复：Thread 路由       │
│                                                                  │
│  cards.py:                                                       │
│    render_model_selector_card()     → N 按钮（5/att 自动分组）    │
│    render_new_session_confirm_card()→ 2 按钮（确认/取消）         │
│    render_switch_success_card()     → 成功确认                    │
│    render_reset_success_card()      → 成功确认                    │
│                                                                  │
│  models.py:                                                      │
│    get_available_models()  → 从 config.yaml + providers 获取     │
│    validate_model_id()     → 合法性校验                          │
│    _resolve_provider_for_model() → 模型→provider 映射            │
│                                                                  │
│  session.py:                                                     │
│    create_session_key()    → 对齐 Gateway 格式                    │
│    switch_session_model()  → 操作 _session_model_overrides       │
│    reset_session()         → 清除 session 状态                    │
└──────────────────────────────────────────────────────────────────┘
```

## 3. 关键设计决策（开发中确认）

### 3.1 Slash Command 响应策略：ephemeral + Bot API 发帖

**问题**：Slash Command 响应以用户身份发送，导致三个缺陷：
1. 重复消息（in_channel 响应 + ephemeral_text 双重输出）
2. 显示用户头像而非 Bot 头像
3. 按钮回调响应用户身份可见

**解决**：
- Slash Command 返回 `{"response_type": "ephemeral", "text": "..."}`（仅用户可见，自动消失）
- 卡片通过 `_api_post("posts", ...)` 以 Bot 身份发帖（唯一持久可见消息，Bot 头像）

### 3.2 session_key 构造：直接读取 payload root_id

**关键发现（2026-05-20）**：MM Slash Command payload **原生包含 `root_id` 字段**！

```
params_keys=['channel_id', 'channel_name', 'command', 'response_url', 'root_id', ...]
```

- Thread 中发送：`root_id=twcryzndejf15px8cuhy43sx4a`
- Channel 顶层发送：`root_id=`（空字符串）

之前误以为 payload 不含 root_id，通过 API 反查用户最近帖子——这是完全错误的方向。
`_find_user_thread_root_id()` 已删除，直接从 payload 读取：

```python
root_id = params.get("root_id", "") or None
# root_id=None → session_key = "agent:main:mattermost:group:{channel_id}"
# root_id=xxx  → session_key = "agent:main:mattermost:group:{channel_id}:{root_id}"
```

### 3.3 模型切换：switch_model() + _session_model_overrides

**问题**：最初尝试直接操作 `_session_model_overrides`，但缺少 provider 解析和 credentials 获取。

**解决**：调用 Gateway 内置的 `switch_model()` 函数（与 `/model` 命令完全一致的解析链）：
```python
from hermes_cli.model_switch import switch_model
result = switch_model(raw_input=model_id, current_provider=..., ...)
# result → ModelSwitchResult(new_model, target_provider, api_key, base_url, api_mode)

runner._session_model_overrides[session_key] = {
    "model": result.new_model,
    "provider": result.target_provider,
    "base_url": result.base_url,
    "api_key": result.api_key,
    "api_mode": result.api_mode,
}
runner._evict_cached_agent(session_key)
```

### 3.4 会话重置：全面清除

重置时清除所有相关状态，对齐 Gateway 内置 `/new` 命令行为：
- `_session_model_overrides.pop(session_key)`
- `_evict_cached_agent(session_key)`
- `session_store.reset_session(session_key)`
- `_set_session_reasoning_override(session_key, None)`
- `_pending_model_notes.pop(session_key, None)`
- `_clear_session_boundary_security_state(session_key)`

### 3.5 Mattermost 5 按钮/attachment 限制

Mattermost 限制每个 attachment 最多 5 个 actions，每个 message 最多 5 个 attachments。
cards.py 自动将模型列表按 5 个一组分组渲染。

### 3.6 callback_server 实现：asyncio.start_server

**未采用** aiohttp（额外依赖），而是覆写 `_start_callback_server()` 使用内置 `asyncio.start_server`，
与父类 `MattermostAdapter` 实现方式一致。手动解析 HTTP 请求行和 body。

### 3.7 send_model_picker 保留但不可用

Gateway 内置 `send_model_picker` 机制仅在 WebSocket 消息流中触发。
**Mattermost 会拦截所有 `/` 开头消息**，必须注册 Slash Command 才能接收。
因此 `send_model_picker` 当前不会被调用，保留仅用于未来兼容。

### 3.8 send_typing Thread 路由：插件覆写替代源码 patch ✅

**背景**：内置 `MattermostAdapter.send_typing()` 只传 `channel_id`，不传 `parent_id`。
在 `reply_mode=thread` 时，typing 指示器错误地显示在频道层而非 Thread 内。

**修复**：在插件的 `MattermostApprovalAdapter` 中覆写 `send_typing()`：

```python
async def send_typing(self, chat_id: str, metadata: Optional[Dict[str, Any]] = None):
    body: Dict[str, Any] = {"channel_id": chat_id}
    if metadata and metadata.get("thread_id"):
        body["parent_id"] = metadata["thread_id"]
    await self._api_post(f"users/{self._bot_user_id}/typing", body)
```

**关键设计原则**：typing 指示器跟随「当前会话上下文」：

| 场景 | `source.thread_id` | metadata | `parent_id` | typing 显示位置 |
|------|:---:|:---:|:---:|------|
| Channel 顶层新消息（Thread 不存在） | `None` | `None` | 不传 | **Channel** |
| Thread 内回复（Thread 已存在） | `"root_post_id"` | `{"thread_id": "root_post_id"}` | 传入 | **Thread** |

**溯源链**：
```
Mattermost WebSocket post.root_id ("" → None)
  ↓ mattermost.py:1205  thread_id = post.get("root_id") or None
  ↓ source.thread_id
  ↓ run.py:12522        _thread_metadata_for_source → None 或 {"thread_id": ...}
  ↓ run.py:14388        send_typing(chat_id, metadata=_thread_metadata)
  ↓ adapter.py (插件)    if metadata.thread_id → parent_id
```

**迁移效果**：
- `hermes-patches.sh` 中 Patch 11（send_typing Thread 路由）已移除
- `mattermost.py` 源码已回滚至原始实现
- 插件独立维护此修复，不受 `git pull` 影响

## 4. 插件目录结构

```
~/.hermes/plugins/mattermost-enhancer/
├── plugin.yaml              # 插件元数据 (kind=platform, min_hermes_version=2.0.0)
├── __init__.py              # 入口：register_platform(name="mattermost", adapter_factory=...)
├── adapter.py               # MattermostApprovalAdapter 类 (~1180 行, 31 个方法)
├── callback_server.py       # HTTP callback 服务器辅助函数
├── cards.py                 # Interactive Message 卡片渲染
├── models.py                # 模型列表管理 (13 个模型)
├── session.py               # Session 定位与操作
└── references/
    └── api-contracts.md     # MM API 契约文档 Mattermost Slash Command / Interactive Message API 契约
```

## 5. 接口契约

### 5.1 Mattermost 自定义 Slash 指令 POST

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

**响应**：`{"response_type": "ephemeral", "text": "🔄 模型选择器已发送"}`
- ephemeral 响应仅用户可见，自动消失
- 实际卡片通过 Bot API 单独发帖到 Thread

### 5.2 Interactive Message 按钮回调 POST

```
POST /mattermost/callback
Content-Type: application/json

{
  "context": {
    "action": "cmd_model_switch",      # 或 cmd_new_confirm / cmd_new_cancel / approve_once 等
    "model_id": "deepseek/deepseek-v4-pro",
    "session_key": "agent:main:mattermost:group:xxx:root_xxx",
    "provider_slug": "custom-api-z-ai",
    "channel_id": "xxx",
    "user_id": "xxx"
  },
  "user_id": "xxx",
  "post_id": "xxx"
}
```

### 5.3 卡片 action 命名约定

沿用已有 DM 审批的 action 格式（纯字母）：

| action (context.action) | action id | 功能 | context 参数 |
|-------------------------|-----------|------|------------|
| `approve_once` | `approveonce` | 允许本次 | `session_key`, `command` |
| `approve_session` | `approvesession` | 本 session 全部允许 | `session_key`, `command` |
| `approve_always` | `approvealways` | 永久允许 | `session_key`, `command` |
| `deny` | `deny` | 拒绝本次 | `session_key`, `command` |
| `cmd_model_switch` | `cmdmodelswitch` | 切换模型 | `model_id`, `session_key`, `provider_slug`, `channel_id`, `user_id` |
| `cmd_new_confirm` | `cmdnewconfirm` | 确认创建新会话 | `session_key` |
| `cmd_new_cancel` | `cmdnewcancel` | 取消创建新会话 | - |

## 6. 已知 Pitfall 清单

| Pitfall | 影响 | 解决方案 |
|---------|------|---------|
| ~~Slash Command payload 不含 root_id~~ | ~~已证实错误~~ | **MM payload 原生包含 root_id 字段**，直接读取即可 |
| Slash Command 响应以用户身份发送 | 显示用户头像 | Bot API `_api_post("posts", ...)` 发帖 |
| `in_channel` 响应 + ephemeral_text | 重复消息 | Slash Command 返回 `{}`，Bot API 单独发帖 |
| action id 含连字符/下划线 | Mattermost 拒绝 | id 纯字母：`cmdmodelswitch` |
| 5 actions/attachment 限制 | 超过 5 个模型时渲染异常 | cards.py 改用 select 下拉列表（不限数量） |
| `load_hermes_config` 不存在 | import 报错 | 使用 `load_config()` |
| `StripActionIntegrations()` 剥离 API 输出 | Bot API 响应中 integration 被清空 | DB 中保留 → 回调时有效 |
| `_gateway_runner_ref` 是弱引用 | 重启后可能失效 | 每次调用时检查 `runner is not None` |
| DM 审批回调移除 ephemeral_text | 不再重复提示 | 仅通过 `update` 替换原始消息 |
| Deny 后卡片按钮仍可点击 | 用户可重复点击报错 | `update` 响应中清空 `attachments.actions` |
| `/model` 切换后 LLM 不知道模型已变 | LLM 回答错误模型名 | 设置 `_pending_model_notes` 注入提示 |

## 7. 迁移步骤

### 阶段一：环境准备 ✅

- [x] 确认 `~/.hermes/plugins/` 目录存在
- [x] 确认 Hermes 版本 ≥ 2.0.0（支持 `register_platform`）
- [x] 确认 `plugins.enabled` 机制已理解（`config.yaml` 中已添加 `mattermost-enhancer`）
- [x] 验证插件加载链：`discover_plugins()` → `platform_registry.register("mattermost")` → `_create_adapter()` 优先使用插件

### 阶段二：DM 审批迁移 ✅

> **风险说明**：需要修改源码（`gateway/run.py` 中 `send_exec_approval` 调用路径），
> 确保审批请求路由到插件的 `send_exec_approval` 而非内置方法。

- [x] 将 patches 7a-7d 的代码迁移到 `adapter.py`（继承 `MattermostAdapter`）
  - [x] `_resolve_root_id()`
  - [x] `_start_callback_server()` / `_stop_callback_server()`
  - [x] `_handle_callback()` / choice_map
  - [x] `send_exec_approval()`
  - [x] `connect()` / `disconnect()` 生命周期
- [x] 在 `__init__.py` 注册 platform override
- [x] 重启 gateway，验证 DM 审批功能正常
- [x] 从 `hermes-patches.sh` 移除 patches 7a-7d

### 阶段三：Slash 指令扩展 ✅

- [x] 实现 `models.py`（模型列表获取 + 校验，13 个模型）
- [x] 实现 `cards.py`（模型选择卡片 + 新会话确认卡片 + 成功确认卡片，5 按钮/att 自动分组）
- [x] 在 `adapter.py` 新增 `/mm-command` 路由（`_start_callback_server` 多路由）
- [x] 实现 `_route_slash_command()` → 分发 `/model` `/new`
- [x] 实现 `_handle_model_command()` → **直接从 payload 读取 root_id** + Bot API 发帖
- [x] 实现 `_handle_new_command()` → **直接从 payload 读取 root_id** + Bot API 发帖
- [x] 实现 `_handle_callback()` → 统一处理审批 + 模型切换 + 会话重置按钮回调
  - [x] `cmd_model_switch` → `switch_model()` + `_session_model_overrides` + `_evict_cached_agent()`
  - [x] `cmd_new_confirm` → 清除 override + agent cache + session store + security state
  - [x] `cmd_new_cancel` → 更新消息为"已取消"
- [x] 实现 `_find_user_thread_root_id()` → ~~API 反查~~ **已删除**（payload 原生含 root_id）
- [x] 实现 `_post_card_in_thread()` → Bot API 发帖（Bot 头像，root_id=None 时不进 thread）
- [x] 实现 `_build_session_key()` → 对齐 `build_session_key()` 格式
- [x] 实现 `_get_current_model_for_session()` → session override → config default
- [x] 修复：重复消息 / 模型切换不生效 / 用户头像 / Deny 后按钮可重复点击
- [x] 修复：Channel/Thread 会话正确区分（直接读 payload root_id）
- [x] 修复：模型选择器改为 select 下拉列表（格式 `zenmux/minimax-m2.7`）
- [x] 修复：LLM 模型切换感知（`_pending_model_notes` 注入）
- [x] 在 Mattermost System Console 配置 `/model` 和 `/new` 自定义 Slash 指令
- [x] 端到端测试（Channel 顶层 + Thread 中均正常）

### 阶段四：收尾 ✅

- [x] 验证 `git pull` 升级后插件仍然生效
- [x] 编写 `references/api-contracts.md`
- [x] 更新 `hermes-patches-migration-plan.md` 状态
- [x] 全面测试通过后，从 `hermes-patches.sh` 移除 patches 7a-7d
- [x] 补全插件缺失的 DM 审批方法（`send_exec_approval`, `_get_or_create_dm`, `_verify_signature`, `_stop_callback_server`, `connect`, `disconnect`）

## 8. 验证清单

### DM 审批回归测试

- [x] 危险命令触发 DM 审批卡片
- [x] Allow Once → 本次通过，下次仍审批
- [x] Allow Session → 本 session 不再审批
- [x] Always Allow → 全局不再审批
- [x] Deny → 拒绝本次执行，按钮正确关闭
- [ ] 超时后按钮自动失效
- [x] CRT Thread 模式下 root_id 正确

### Slash 指令功能测试

- [x] `/model` 触发 → 模型选择卡片正确渲染（Bot 头像）
- [x] `/model` 选择模型 → 切换成功确认 + 后续对话使用新模型
- [ ] `/model` 在 Thread A 切换 → Thread B 模型不受影响
- [x] `/model` 当前模型显示在下拉列表 placeholder
- [x] `/model` 无重复消息（仅有 Bot 帖子）
- [x] `/model` Channel 顶层发送 → 不进 Thread（直接读 payload root_id）
- [x] `/new` 触发 → 确认卡片正确渲染（Bot 头像）
- [x] `/new` 确认 → Session 重置成功 + 确认反馈（无重复）
- [ ] `/new` 取消 → 无操作
- [x] 非白名单用户执行指令 → Unauthorized

### 插件兼容性测试

- [ ] `git pull` 更新 Hermes 后插件仍然加载
- [ ] 内置 `MattermostAdapter` API 更新后插件不崩溃（`super()` 调用兼容）
- [ ] 插件加载失败时 gateway 仍然正常启动（内置适配器作为 fallback）

## 9. 风险与缓解

| 风险 | 概率 | 影响 | 缓解 |
|------|------|------|------|
| `register_platform` API 变更 | 低 | 高 | 锁定 `min_hermes_version`，升级前验证 |
| 内置 `MattermostAdapter` 重构 | 中 | 中 | 最小化覆写方法，其余 `super()` 调用 |
| callback server 端口冲突 | 低 | 中 | 通过 `MATTERMOST_CALLBACK_PORT` 环境变量配置 |
| `_gateway_runner_ref` 弱引用失效 | 低 | 高 | 每次调用时检查 `runner is not None`，失败时友好提示 |
|| API 反查 root_id 无结果 | 低 | 低 | **已过时** — payload 原生含 root_id，无需反查 |
| `switch_model()` 解析失败 | 低 | 中 | 返回 `ModelSwitchResult.error_message` 给用户 |
| 多个 plugin 注册同一 platform | 低 | 高 | 确保 `priority=100` 高于其他潜在覆盖 |
| `/model` 卡片模型列表与实际可用模型不同步 | 中 | 低 | 每次 `/model` 触发时实时查询 config |

## 10. 开发日志

### 2026-05-20：阶段三代码开发完成

**完成**：
- 插件目录骨架创建（plugin.yaml, __init__.py, 6 个 .py 模块）
- 所有文件语法编译通过，import 链验证通过
- 模型列表获取验证：13 个模型 + provider 解析正确
- 插件静态加载验证：`platform_registry` 注册 `mattermost` source=plugin
- Gateway 运行中加载插件：callback server 双路由 `/mattermost/callback` + `/mm-command` 均可达
- 三个关键 bug 修复：重复消息、模型切换无效、用户头像
- cards.py 5 按钮/attachment 限制处理

**待操作**：
- 重启 Gateway 加载新插件代码
- 端到端测试 /model 和 /new Slash Command

**关键认知**：
- Mattermost 会拦截所有 `/` 开头消息，必须注册 Slash Command
- **MM Slash Command payload 原生包含 `root_id` 字段**（此前误判，导致 API 反查不可靠）
- Slash Command 响应以用户身份发送，需 Bot API 单独发帖
- `send_model_picker` 在 Mattermost 场景不可用（WebSocket 不传递 `/` 消息）
- `load_config()` 是正确的配置加载函数（非 `load_hermes_config`）
- `_session_model_overrides` + `_evict_cached_agent()` 是模型切换的正确机制
- 模型切换后需设置 `_pending_model_notes` 让 LLM 感知模型变化
- Mattermost select action 不支持 default 选中，用 name 字段作为 placeholder
- DM 审批 Deny 后需清空 `attachments.actions` 防止重复点击

### 2026-05-20：Channel/Thread 会话区分 + 多 Bug 修复

**修复的 Bug**：

| # | Bug | 根因 | 修复 |
|---|-----|------|------|
| 1 | /new 消息重复显示两遍 | message + props.attachments 双重渲染 | message 留空，仅 props.attachments |
| 2 | ephemeral 消息显示用户头像 | Slash Command HTTP response 以用户身份发送 | 返回空 `{}`，Bot API 单独发帖 |
| 3 | 模型选择器 13 按钮排列混乱 | 5 按钮/att 限制导致多行 | 改为 select 下拉列表，格式 `zenmux/minimax-m2.7` |
| 4 | 模型切换"成功"但实际未变 | LLM 不知道 session override | 设置 `_pending_model_notes` 注入提示 |
| 5 | select 回调无法识别 | 只读 `context.model_id`，select 回调用 `selected_option` | 优先读 `selected_option`，回退 `model_id` |
| 6 | 日志截断误导 session_key 误判 | `session_key[:60]` 截断 | 去掉截断，显示完整 key |
| 7 | Channel 中 /model 被路由到 Thread | **核心误判**：以为 payload 不含 root_id，API 反查旧帖子 | 直接从 payload 读 `root_id`；`_find_user_thread_root_id` 已删除 |
| 8 | Deny 后卡片按钮仍可点击 | `update` 只替换 message，不清 actions | `update` 返回空 `attachments.actions` |
| 9 | 重复 Deny 报 "No pending approval" | `count==0` 返回 ephemeral，不关卡片 | 改为 `update` 清空按钮 + "此审批已处理" |

**架构认知修正**：
- ❌ ~~MM Slash Command payload 不含 root_id~~ → ✅ **原生包含**
- ❌ ~~需要 `_find_user_thread_root_id()` API 反查~~ → ✅ **已删除**
- ❌ ~~模型选择器用按钮分组~~ → ✅ **select 下拉列表**
- ❌ ~~Channel/Thread 会话无法区分~~ → ✅ **直接读 payload.root_id**

**当前验证状态**：
- ✅ Channel 顶层 `/model` → session_key 不含 thread 后缀，卡片发到 Channel
- ✅ Thread 中 `/model` → session_key 含 thread 后缀，卡片发到对应 Thread
- ✅ 模型切换多次均生效（API 日志确认）
- ✅ DM Deny 后按钮清空，无法重复点击
- ✅ Select 下拉列表 placeholder 显示当前模型


### 2026-05-22：阶段二 + 阶段四完成 ✅

**完成事项：**
- DM 审批完整迁移至插件（`send_exec_approval`, `_get_or_create_dm`, `_verify_signature`, `_stop_callback_server`, `connect`, `disconnect` 覆写）
- `_resolve_root_id` + `send()` / `_send_local_file()` / `_send_url_as_file()` 覆写（替代 patch 6）
- MEDIA 静默跳过合并到 `_send_local_file()` 覆写（替代 patch 10c）
- `mattermost.py` 源码回滚至 a91a57fa5（1292→852 行，零 patch 残留）
- `hermes-patches.sh` 移除 patches 6, 7, 10c（registry + apply blocks，-673 行）
- 3 个 Bug 修复：resolve_gateway_approval 延迟 import、provider 格式缺 custom: 前缀、pending_model_notes 时序错误
- references/api-contracts.md 编写完成
- plugin.yaml 升级至 v2.0.0，README 全面改版
- hermes-patches.sh 标签人性化，registry 残留清理

**最终效果：**
```
mattermost.py: 1292 行 (4 patch 残留) → 852 行 (零修改)
hermes-patches.sh: 16 patch → 12 patch
```

### 2026-05-22：send_typing Thread 路由迁移至插件 ✅

**操作**：
1. 在 `adapter.py` 中新增 `send_typing()` 覆写（+21 行）
   - 读取 `metadata.thread_id` → 设置 `parent_id` 将 typing 指示器路由到 Thread
   - 无 `thread_id` 时（Channel 顶层消息）只传 `channel_id`，typing 留在 Channel
2. 源码回滚：`mattermost.py` 恢复原始 `send_typing()` 实现（-5 行）
3. Patch 清理：从 `hermes-patches.sh` 移除 Patch 11（-45 行，registry 条目 + apply block）
4. 注释标记为「已迁移到 mattermost-enhancer 插件」

**设计原则验证**：
- `post.root_id=""` → `thread_id=None` → metadata=None → typing 在 Channel ✅
- `post.root_id="abc123"` → `thread_id="abc123"` → metadata 含 thread_id → typing 在 Thread ✅
- 完全遵循「当前会话上下文在哪，typing 就显示在哪」

**迁移效果**：
- `hermes-patches.sh` 从 16 patch 降至 15 patch
- send_typing 修复完全由插件接管，不受 `git pull` 影响
- 源码零修改，符合「一个插件覆盖所有 Mattermost 自定义」的最终愿景
