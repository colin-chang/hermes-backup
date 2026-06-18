---
name: hermes-session-model
description: "Hermes Agent 会话模型 — 多客户端会话隔离机制、session_key 架构、state.db 存储与清理策略、Desktop/CLI/Mattermost/Web UI 行为差异。当用户询问 Hermes 多端会话共享、Desktop 与其他客户端互通、会话持久化/压缩/清理、或会话历史恢复时使用。"
version: 1.2.0
metadata:
  hermes:
    tags: [hermes, gateway, sessions, architecture, multi-client, state-db]
    category: custom
---

# Hermes Session Model

Hermes Agent 在多客户端（Mattermost / Desktop / Web UI / CLI）环境下通过 `session_key` 实现平台级会话隔离。**不同客户端之间的会话不互通**，这是设计如此，不是 bug。

## ⚠️ 关键规则：先查代码，不要假设

当用户询问 Hermes 内部行为（会话共享、消息互通、存储机制）时，**必须检查源码再回答**，不要用「理论上应该」或「一般这种架构会」的逻辑推断。本 Skill 记录已验证的代码级事实。

## Triggers

- 用户问 Desktop / Mattermost / Web UI / CLI 之间会话是否共享
- 用户问 Desktop 会话存储在哪里、会保留多久
- 用户问 Hermes 会话清理策略与 Mattermost 消息的关系
- 用户问多客户端同时使用 Hermes 的行为
- 用户想了解 session_key 机制或 state.db 架构

## Session Key 架构（核心机制）

会话唯一键在 `gateway/session.py` 中构造（`build_session_key()`）：

```
agent:main:{platform}:{chat_type}:{chat_id}:{thread_id}
```

关键常量（`gateway/config.py`）：
```python
LOCAL = "local"          # Desktop / CLI
MATTERMOST = "mattermost"
API_SERVER = "api_server"  # Web UI
```

### 不同客户端的 session_key 示例

| 客户端 | platform | session_key |
|--------|----------|-------------|
| Desktop | `local` | `agent:main:local:dm` |
| CLI | `local` | `agent:main:local:dm` |
| Mattermost | `mattermost` | `agent:main:mattermost:channel:{chat_id}` |
| Web UI | `api_server` | `agent:main:api_server:...` |

**不同 platform = 不同 session_key = 完全独立的会话。消息不互通。**

### Desktop 能看到其他客户端历史的原因

所有会话存入 `~/.hermes/state.db`（SQLite），Desktop 的会话列表可以展示所有平台的历史记录。但：

- **Desktop 能看到 Mattermost 历史** → ✅ 读取 state.db 中的记录
- **Desktop 发消息 Mattermost 能收到** → ❌ 新消息写入 `local` 平台会话，不推送到 Mattermost
- **Desktop 继续 Mattermost 会话** → ❌ 仅在 Desktop 可见，Mattermost 频道中不可见

错误认知来源：误以为「同一 Agent 实例 + 同一 state.db = 会话互通」。实际是 **session_key 平台隔离** 阻断了互通。

## 会话存储架构

```
~/.hermes/state.db                    ← 所有平台的会话统一存这里（SQLite + FTS5）
  ├─ sessions 表                       ← 元数据（session_id, source, platform, …）
  └─ messages 表（FTS5 全文索引）       ← 每条消息

Mattermost Docker Volume（PostgreSQL） ← Mattermost 自己的消息存储，独立于 Hermes
```

Gateway 加载历史的代码（`gateway/run.py:7867`）：
```python
history = self.session_store.load_transcript(session_entry.session_id)
```

从 state.db 加载，**不是**从 Mattermost API 回填。

## 会话生命周期

### 压缩（Compression）

发生在对话上下文中，不是存储层：

- 当对话 token 接近模型上限（默认 50% 上下文窗口）时触发
- 旧 session 标记 `end_reason='compression'`，创建新 child session
- state.db 中旧消息保留，只是 Agent 不再引用
- Gateway 层有独立的 "Session Hygiene" 机制（85% 阈值），预处理阶段压缩

### 清理（Pruning）

代码位置：`hermes_state.py:4195` `maybe_auto_prune_and_vacuum()`

| 参数 | 默认值 | 含义 |
|------|--------|------|
| `retention_days` | 90 | 超过此天数的**已结束**会话被清理 |
| `min_interval_hours` | 24 | 每 24 小时最多执行一次 |
| `auto_prune` | 取决于 `sessions.auto_prune` 配置 | 是否启用自动清理 |

**只清理已结束的会话**（`end_reason IS NOT NULL`）。正在进行的会话不受影响。

清理时同时删除 `~/.hermes/sessions/` 下的 `.jsonl` 转录文件。

### Mattermost 消息不受 Hermes 清理影响

Mattermost 的消息存在 Docker PostgreSQL 中，与 `state.db` 完全独立：
- Hermes `auto_prune` 清理 → state.db 中旧上下文消失，但 Mattermost 频道里消息还在
- 重新对话时 Agent 从空历史开始（state.db 中没有旧记录）

**关键行为：auto_prune 后继续 Mattermost 对话**

```
auto_prune 清理 state.db 中旧会话
  → 用户在 Mattermost 频道继续发消息
    → Gateway 计算同一 session_key
    → get_or_create_session_entry() 找不到旧条目
    → 创建 NEW session_id（全新会话）
    → load_transcript(new_session_id) 返回空 []
    → Agent 从零上下文开始，完全不知道之前的对话
    → Mattermost 频道中肉眼可见的历史消息 ≠ Agent 上下文
```

这与 Discord 不同——Discord adapter 有 `_fetch_channel_context` 回填机制（`plugins/platforms/discord/adapter.py:5048`），Mattermost 没有。

## Desktop 会话特性

- **存储位置**：`~/.hermes/state.db`（与其他客户端共用同一数据库）
- **source 字段**：`"cli"`（`local` 平台映射为 `"cli"`，见 `gateway/run.py:1550`）
- **保留时间**：自动清理默认 90 天（`auto_prune: true` 时），可配置 `retention_days`
- **压缩**：运行时 token 触发，非存储层压缩
- Desktop + CLI 共享同一个 `local` 平台 → 从 Desktop 发的消息 CLI 也能看到，反之亦然

### Desktop 升级机制

Desktop 右下角版本号点击升级 → Electron 后端执行 `POST /api/hermes/update`（IPC 桥接）→ 后端根据安装方式执行对应升级命令：

| 安装方式 | 升级命令 | Desktop 自动执行？ |
|---------|---------|------------------|
| **git** | `hermes update` | ✅ 自动（子进程执行） |
| Homebrew | `brew upgrade hermes-agent` | ✅ 自动 |
| pip/uv | `pip/uv install --upgrade …` | ✅ 自动 |
| Docker | `docker pull …` | ❌ 手动（仅提示命令） |

代码证据（`apps/desktop/src/global.d.ts:175-178`）：
```typescript
/** True when no staged updater exists (CLI install) and the user should run
 *  `hermes update` themselves. */
manual?: boolean
```

**结论：Desktop 和 CLI 共享同一个 `~/.hermes/hermes-agent/`，升级 Desktop 就是升级 CLI 安装。** 不存在「两个独立安装」。

关键代码路径：
- `apps/desktop/src/hermes.ts:684` — `updateHermes()` → `POST /api/hermes/update`
- `apps/desktop/src/store/updates.ts:345` — `applyBackendUpdate()` 调 `updateHermes()` 后轮询 action 状态
- `tui_gateway/server.py:2054` — `recommended_update_command()` 决定具体命令
- `hermes_cli/config.py:443` — 根据 `detect_install_method()` 返回对应命令

## 常见误区

| 误区 | 事实 |
|------|------|
| Desktop/Mattermost/Web UI 共享会话 | ❌ 不同 platform = 不同 session_key |
| state.db 清空后 Mattermost 消息也丢 | ❌ Mattermost PostgreSQL 独立存储 |
| Desktop 是新安装的独立 Hermes | ❌ 共享 ~/.hermes/ 下所有配置和 state.db |
| 从 Desktop 继续 Mattermost 会话会同步 | ❌ 只在 Desktop 本地可见 |
| 同一频道内不同 Thread 之间消息互不干扰 | ⚠️ session_key 隔离但 **中断机制不隔离** — 见下方 |

## 跨 Thread 中断行为（⚠️ 已知 Bug）

当 `busy_input_mode=interrupt`（默认）时，在同一频道（channel）但不同 thread 发送的消息仍会**中断当前活跃的 agent 会话**，即使 session_key 不同。

**触发条件**：
1. Agent 正在处理 Thread A 的消息
2. 用户在**同一频道**发送 channel-level 帖子（或另一 Thread 的消息）
3. Gateway 检测到碰撞 → 中断 agent → 会话重启
4. **Bug**：重启时使用中断消息的 source（`thread_id=None` + 错误的 `message_id`），导致后续回复路由到错误的 Thread

**影响**：Mattermost / Discord / Slack 等支持多线程的平台均受影响。

**已修复**（Hermes 补丁 P60a + P60b）：在 `gateway/run.py` 中保护 session source 不被中断消息覆盖，并回退到缓存的原始 source 构造 thread metadata。

**补丁细节** — 见 `references/cross-thread-interrupt-fix.md`。

## 中断处理与跨线程污染（⚠️ 已知 Bug）

### 问题

当 Hermes 在 Mattermost 的一个线程中执行长时间任务时，如果用户在**同一频道的不同线程**中发送消息触发中断，中断消息携带的 `reply_to`/`root_id` 会覆盖原会话的发送目标。

### 机制

1. 会话 A 在线程 A 中处理（session_key 绑定 thread_id_A）
2. 用户在线程 B 发送消息
3. Gateway 检测到同 user + 同 platform 碰撞 → 注入中断
4. 中断消息携带线程 B 的 `root_id`
5. `hermes_plugins.mattermost_enhancer.adapter.send()` 使用新消息的 `reply_to` 而非 session 绑定的原始目标
6. 会话 A 的所有后续回复发往线程 B

### 证据

- 中断前后 `_resolve_root_id` 输入从 `thread_id_A` 变为 `thread_id_B`
- `tcp_force_closed=1` 标志中断发生
- 后续所有 `send() threading` 日志均显示错误的 `reply_to`
- 会话 ID 未变（说明 session_key 未被重建，但 metadata 被覆盖）

详见 `hermes-operations` skill 的 `references/mattermost-cross-thread-interruption.md`。

## References

- `references/session-isolation-evidence.md` — 源码证据：session_key 构造、platform 常量、历史加载路径
