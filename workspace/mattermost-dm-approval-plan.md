# Mattermost DM 审批模式 —— 实施总结

> 版本：2.0（最终） | 日期：2026-06-24 | 状态：✅ 已完成并验证
>
> 目标：将 Mattermost 的危险命令审批流程从「文字 `/approve`（不可用）」升级为「DM 私信按钮审批」，对标 Discord 体验。

---

## 目录

1. [架构总览](#1-架构总览)
2. [核心发现与踩坑记录](#2-核心发现与踩坑记录)
3. [最终方案：Bot API + DM](#3-最终方案bot-api--dm)
4. [数据流详解](#4-数据流详解)
5. [源码修改清单](#5-源码修改清单)
6. [环境配置](#6-环境配置)
7. [升级恢复](#7-升级恢复)
8. [验证结果](#8-验证结果)
9. [附录](#9-附录)

---

## 1. 架构总览

```
┌──────────────────── 频道 #general ────────────────────┐
│                                                        │
│  用户: rm -rf /tmp/cache                               │
│                                                        │
│  MattermostAdapter 接收消息                             │
│       │                                                │
│       ▼                                                │
│  run.py: _run_agent()                                  │
│       │                                                │
│       ▼                                                │
│  Agent 循环 → terminal tool 判断危险                    │
│       │                                                │
│       ▼                                                │
│  tools/approval.py: _request_approval() → Event.wait()⏸️│
│       │                                                │
│       ▼                                                │
│  _approval_notify_sync()                               │
│       │                                                │
│       ▼                                                │
│  检测: type(adapter).send_exec_approval 存在?           │
│       │                                                │
│       ▼  YES                                           │
│  MattermostAdapter.send_exec_approval()                 │
│       │                                                │
│       ├──→ ① 获取/创建 DM channel                        │
│       │      POST /api/v4/channels/direct              │
│       │                                                │
│       ├──→ ② Bot API 发 Interactive Message 到 DM        │
│       │      POST /api/v4/posts                        │
│       │      {channel_id: dm_channel,                  │
│       │       props: {attachments: [{actions: [...]}]}}│
│       │                                                │
│       └──→ ③ 发简短提示到频道                             │
│              "⏳ 已向您发送私信，请在DM中审批"              │
│                                                        │
│  ★ 频道内 Agent 继续 Event.wait()，不被中断              │
│                                                        │
└────────────────────────────────────────────────────────┘

┌────────────────── DM (用户 ↔ Hermes Bot) ──────────────┐
│                                                        │
│  Hermes Bot:                                           │
│  ⚠️ 危险命令需要审批                                    │
│  ┌──────────────────────────────────────────────────┐  │
│  │ rm -rf /tmp/cache                                │  │
│  └──────────────────────────────────────────────────┘  │
│  Reason: 删除操作涉及系统文件                            │
│                                                        │
│  [Allow Once] [Allow Session] [Always Allow] [Deny]    │
│                                                        │
│  用户点击 [Allow Once]                                  │
│       │                                                │
│       ▼                                                │
│  MM 服务端 → HTTP POST callback_url                     │
│       │                                                │
│       ▼                                                │
│  Hermes CallbackServer._handle_callback()               │
│       │                                                │
│       ├──→ 校验签名（HMAC-SHA256，可选）                  │
│       ├──→ 校验 user_id ∈ MATTERMOST_ALLOWED_USERS      │
│       ├──→ resolve_gateway_approval(session_key, "once") │
│       │     → Event.set() → 频道 Agent 解除阻塞 ✅       │
│       │                                                │
│       └──→ 返回 {"update": {...}, "ephemeral_text":...} │
│              DM 消息按钮变灰，显示审批结果                  │
│                                                        │
└────────────────────────────────────────────────────────┘
```

### 关键设计原则

| 原则 | 说明 |
|------|------|
| **Bot API 直接发 DM** | 无需 Webhook，`StripActionIntegrations()` 只剥离 API 响应输出，DB 完整保留 `integration` 字段 |
| **Session 隔离** | 频道 Session 和 DM Session 用不同的 `session_key`，互不干扰 |
| **HTTP 回调不走消息通道** | 按钮点击 → Mattermost HTTP POST → callback server → `resolve_gateway_approval()`，不经过 Agent 消息循环 |
| **回调 URL 独立配置** | `MATTERMOST_CALLBACK_URL` 解决 Docker 部署中 bind 地址 ≠ 回调地址的问题 |
| **root_id 向上查找** | `_resolve_root_id()` 确保 thread 回复时 root_id 指向根帖子，避免 `Invalid RootId` |

---

## 2. 核心发现与踩坑记录

### 2.1 StripActionIntegrations 的真相（最关键发现）

**问题：** 最初认为 Bot API 创建的帖子 `integration` 字段会被 Mattermost 剥离，导致按钮点击无法回调，因此设计了 Incoming Webhook 方案。

**真相：** Mattermost 11.7 的 `StripActionIntegrations()` **只剥离 API 响应 JSON 中的 `integration` 字段**（对前端展示无影响），**数据库中完整保留**。服务端处理按钮点击时从 DB 读取 `integration`，因此 Bot API 发送的帖子按钮回调**完全正常**。

**验证方式：**
```sql
-- PostgreSQL 查询确认 DB 中的 integration 完整保留
SELECT props->'attachments'->0->'actions'->0->'integration'
FROM posts WHERE id = '<post_id>';
-- 结果: {"url": "http://...", "context": {"action": "approve_once", ...}}
```

**结论：** Incoming Webhook **不是必须的**，Bot API + DM 方式更简洁，无需额外配置 Webhook 和审批频道。

### 2.2 root_id 必须是 Thread 根帖子

**问题：** `send()` 方法在 `reply_mode == "thread"` 时，直接将 `reply_to`（可能是某个回复帖子的 ID）作为 `root_id`，导致 `Invalid RootId parameter` 错误。

**原因：** Mattermost 要求 `root_id` 必须是 thread 的**根帖子** ID，不能是 thread 中某个回复的 ID。

**解决方案：** 添加 `_resolve_root_id()` 方法，通过 `GET /api/v4/posts/{post_id}` 查询帖子，如果该帖子有 `root_id`（说明它是回复），则向上追溯返回根帖子 ID。

### 2.3 choice_map 的下划线格式

**问题：** 按钮 action id 使用连字符格式（如 `approve-once`），但 Mattermost 回调中 `context.action` 使用的是下划线格式（`approve_once`），导致 `choice_map` 映射失败。

**解决方案：** Action id 改为纯字母（`approveonce`），`context.action` 使用下划线格式（`approve_once`），`choice_map` key 与 `context.action` 保持一致。

### 2.4 回调 URL 与监听地址的区分

**问题：** Docker 部署中，callback server 监听 `0.0.0.0`，但 Mattermost 容器需要通过 `host.docker.internal` 访问宿主机。这两个地址不同。

**解决方案：** 引入 `MATTERMOST_CALLBACK_URL` 环境变量，显式指定回调 URL，与 `_callback_bind` 解耦。

---

## 3. 最终方案：Bot API + DM

### 方案对比

| 维度 | Bot API + DM（✅ 最终方案） | Incoming Webhook（❌ 已弃用） |
|------|---------------------------|------------------------------|
| 配置复杂度 | 仅需 `MATTERMOST_CALLBACK_URL` | 额外需要 Webhook URL + 审批频道 ID |
| 消息位置 | DM 私信（对标 Discord） | 需发到 Webhook 绑定的频道 |
| integration 保留 | ✅ DB 完整保留 | ✅ 完整保留 |
| 按钮回调 | ✅ 正常 | ✅ 正常 |
| 用户体验 | 审批在 DM 中完成，不污染频道 | 审批在公共频道可见 |
| 代码侵入 | 最小 | 额外的 Webhook 逻辑 |

---

## 4. 数据流详解

### 4.1 审批触发流程

```
位置：tools/approval.py — _request_approval()

1. approval_data = {
     "command":      "rm -rf /tmp/cache",
     "description":  "删除操作涉及系统文件",
     "session_key":  "agent:main:mattermost:channel:<channel_id>:<root_id>"
   }

2. entry = _ApprovalEntry(event=threading.Event())
   _gateway_queues[session_key].append(entry)

3. notify_cb(approval_data)  # → _approval_notify_sync()

4. entry.event.wait(timeout=300)  # 最多等 5 分钟
```

### 4.2 DM Channel 创建

```
POST /api/v4/channels/direct
Body: [bot_user_id, target_user_id]

→ 幂等：已存在的 DM 返回已存在的 channel_id
→ 缓存：session 生命周期内缓存 channel_id
```

### 4.3 Interactive Message 发送

```
POST /api/v4/posts
Body:
{
  "channel_id": "<dm_channel_id>",
  "message": "⚠️ 危险命令需要审批",
  "props": {
    "attachments": [{
      "fallback": "⚠️ 危险命令需要审批: ...",
      "color": "#ff9900",
      "text": "```\nrm -rf /tmp/cache\n```\n**Reason:** 删除操作\n\n请点击下方按钮审批或拒绝此操作。",
      "actions": [
        {
          "id": "approveonce",
          "name": "Allow Once",
          "type": "button",
          "style": "primary",
          "integration": {
            "url": "http://host.docker.internal:18065/mattermost/callback",
            "context": {
              "action": "approve_once",
              "session_key": "...",
              "command": "rm -rf /tmp/cache"
            }
          }
        },
        // ... Allow Session, Always Allow, Deny
      ]
    }]
  }
}
```

### 4.4 按钮回调处理

```
Mattermost HTTP POST → http://host.docker.internal:18065/mattermost/callback

Body:
{
  "context": {
    "action": "approve_once",
    "session_key": "...",
    "command": "rm -rf /tmp/cache"
  },
  "post_id": "原始消息ID",
  "user_id": "点击按钮的用户ID"
}

处理流程:
  1. 校验 HMAC-SHA256 签名（可选，配置了 MATTERMOST_CALLBACK_SECRET 时）
  2. 校验 user_id ∈ MATTERMOST_ALLOWED_USERS
  3. choice_map = {
       "approve_once": "once",
       "approve_session": "session",
       "approve_always": "always",
       "deny": "deny"
     }
  4. resolve_gateway_approval(session_key, choice)
  5. 返回 {"update": {"message": "✅ Approved — Allow Once", "props": {}}, "ephemeral_text": "审批完成"}
```

---

## 5. 源码修改清单

### 文件 1: `gateway/platforms/mattermost.py` — 主要修改

| 修改项 | 说明 |
|--------|------|
| `__init__` 末尾 | 添加 callback server 属性、`_callback_url`、`_callback_secret`、`_dm_cache` |
| `_get_allowed_users()` | 获取 `MATTERMOST_ALLOWED_USERS` 配置 |
| `_get_or_create_dm()` | 获取/创建 DM channel（幂等，带缓存） |
| `_start_callback_server()` | 内嵌 asyncio HTTP server，接收按钮回调 |
| `_stop_callback_server()` | 安全关闭 callback server |
| `_verify_signature()` | HMAC-SHA256 签名校验 |
| `_handle_callback()` | 处理回调：校验→映射→resolve_gateway_approval→返回更新 |
| `send_exec_approval()` | Bot API 发 DM 审批卡片 + 频道提示 |
| `_resolve_root_id()` | 向上查找 thread 根帖子 ID |
| `send()` | 使用 `_resolve_root_id()` |
| `_send_url_as_file()` | 使用 `_resolve_root_id()` |
| `_send_local_file()` | 使用 `_resolve_root_id()` |
| `connect()` 末尾 | `await self._start_callback_server()` |
| `disconnect()` 开头 | `await self._stop_callback_server()` |

### 文件 2: `gateway/run.py` — 传入 user_id

```python
# 第 15550 行附近
_status_adapter.send_exec_approval(
    chat_id=_status_chat_id,
    command=cmd,
    session_key=_approval_session_key,
    description=desc,
    metadata=_status_thread_metadata,
    user_id=source.user_id if hasattr(source, 'user_id') else None,  # Hermes Patch
)
```

### 未修改的文件

以下文件签名兼容（`user_id` 是可选参数，默认 `None`，不影响现有行为）：
- `gateway/platforms/base.py` — 鸭子类型检测，无需修改
- `gateway/platforms/discord.py` — `send_exec_approval` 忽略新参数
- `gateway/platforms/telegram.py` — 同上
- `gateway/platforms/slack.py` — 同上
- `gateway/platforms/feishu.py` — 同上

---

## 6. 环境配置

### 6.1 Mattermost 服务端 `config.json`

```json
{
  "ServiceSettings": {
    "AllowedUntrustedInternalConnections": "host.docker.internal"
  }
}
```

> Docker 部署必须配置，否则按钮点击回调会被 Mattermost 安全策略拒绝。重启 Mattermost 后生效。

### 6.2 Hermes `.env`

```bash
# ── Mattermost DM 审批回调 ──
# bind=0.0.0.0 使 Docker 容器可连接到宿主机 callback server
MATTERMOST_CALLBACK_BIND=0.0.0.0
MATTERMOST_CALLBACK_PORT=18065
# Docker 部署必须显式设置：MM 容器通过 host.docker.internal 访问宿主机
MATTERMOST_CALLBACK_URL=http://host.docker.internal:18065/mattermost/callback
# 可选：HMAC 签名 secret（提升安全性）
# MATTERMOST_CALLBACK_SECRET=your-secret-here
```

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `MATTERMOST_CALLBACK_BIND` | `127.0.0.1` | 监听地址。Docker 部署设 `0.0.0.0` |
| `MATTERMOST_CALLBACK_PORT` | `18065` | 监听端口 |
| `MATTERMOST_CALLBACK_URL` | 自动构造 | **Docker 部署必须设**，与 `bind` 解耦 |
| `MATTERMOST_CALLBACK_SECRET` | 空（不校验） | HMAC-SHA256 签名 secret |

### 6.3 已清理的配置

以下环境变量已被移除（Webhook 方案已弃用）：
- ~~`MATTERMOST_WEBHOOK_URL`~~ — 不再需要
- ~~`MATTERMOST_APPROVAL_CHANNEL_ID`~~ — 不再需要

---

## 7. 升级恢复

Hermes `git pull` 升级后会覆盖所有修改，通过 `hermes-patches.sh` 一键恢复：

```bash
~/workspace/hermes-patches.sh apply   # 应用所有 patches
hermes gateway restart                # 重启生效
```

脚本包含以下 Mattermost 相关 patches：

| # | Patch | 说明 |
|---|-------|------|
| 1 | `mattermost.py (CRT root_id)` | thread root_id 向上查找（send 等方法） |
| 2 | `mattermost.py (DM 审批基础设施)` | callback server + DM 审批完整实现 |
| 3 | `mattermost.py (MEDIA 静默跳过)` | 文件不存在时不报错 |
| 4 | `run.py (user_id 传入)` | send_exec_approval 传入 user_id |
| 5 | `run.py (MEDIA 工具结果扫描)` | MEDIA 正则收紧 |

---

## 8. 验证结果

### 8.1 手动验证清单

- [x] `hermes gateway restart` 后日志出现 "Mattermost callback server listening on 0.0.0.0:18065"
- [x] 在 Mattermost 频道中触发危险命令
- [x] 频道中出现 "⏳ 已向您发送私信，请在 DM 中审批危险命令。"
- [x] DM 中出现带 4 个按钮的审批消息
- [x] 点击 "Allow Once" → DM 消息按钮变灰 + 频道命令继续执行
- [x] 点击 "Deny" → DM 消息更新 + 命令被拒绝
- [x] PostgreSQL 查询确认 `integration` 字段在 DB 中完整保留
- [x] Bot API 直接发 DM 审批卡片 → 按钮回调正常
- [x] `_resolve_root_id()` 解决 `Invalid RootId` 问题

### 8.2 集成测试矩阵

| 场景 | 结果 |
|------|------|
| 完整审批流程（Allow Once） | ✅ DM 审批 → 频道执行 |
| Deny 流程 | ✅ DM 消息更新为 "❌ Denied" |
| 超时回退 | ✅ 5 分钟后自动拒绝 |
| 并发审批 | ✅ 各自独立 DM，互不干扰 |
| DM 已存在 | ✅ 复用同一 DM channel |
| root_id 回复帖子 | ✅ `_resolve_root_id()` 自动向上查找 |
| choice_map 下划线匹配 | ✅ `approve_once` 正确映射到 `"once"` |

---

## 9. 附录

### A. 与 Discord DM 审批的对比

| 维度 | Discord | Mattermost（本方案） |
|------|---------|---------------------|
| 按钮载体 | Discord Button Component | Mattermost Interactive Message Attachment |
| 回调方式 | Discord Interaction API（gateway 连接自动处理） | 独立 HTTP callback server |
| 审批路由 | Discord 自动路由 | 通过 `context.session_key` 手动关联 |
| Session 隔离 | Discord Thread = 独立 Session | DM channel ≠ 频道 channel → 天然隔离 |
| 端口需求 | 无额外端口 | 需一个本地端口（默认 18065） |
| 配置复杂度 | 零配置 | 需配 `AllowedUntrustedInternalConnections` |

### B. 关键代码路径

- `gateway/platforms/mattermost.py:102-132` — `__init__` 审批基础设施属性
- `gateway/platforms/mattermost.py:224-588` — DM 审批方法（callback server + send_exec_approval）
- `gateway/platforms/mattermost.py:660-674` — `_resolve_root_id()`
- `gateway/platforms/mattermost.py:627-629` — `connect()` 启动 callback server
- `gateway/platforms/mattermost.py:637-639` — `disconnect()` 停止 callback server
- `gateway/run.py:15550` — `user_id` 传入
- `tools/approval.py:517-568` — `resolve_gateway_approval` 全局状态机

### C. Mattermost API 参考

- [创建 DM Channel](https://api.mattermost.com/#tag/channels/operation/CreateDirectChannel) — `POST /api/v4/channels/direct`
- [发送 Post](https://api.mattermost.com/#tag/posts/operation/CreatePost) — `POST /api/v4/posts`（支持 `props.attachments`）
- [Interactive Messages](https://docs.mattermost.com/developer/interactive-messages.html) — 按钮与回调格式
- [获取 Post](https://api.mattermost.com/#tag/posts/operation/GetPost) — `GET /api/v4/posts/{post_id}`（用于 `_resolve_root_id`）

### D. 13 个 Pitfall 速查

| # | Pitfall | 解决方案 |
|---|---------|---------|
| 1 | `StripActionIntegrations()` 剥离 API 输出但不影响 DB | Bot API DM + `props.attachments` 可行 |
| 2 | Webhook 用顶层 `attachments` / Bot API 用 `props.attachments` | 搞反则按钮消失 |
| 3 | Action id 纯字母（`approveonce`） | 含特殊字符可能出问题 |
| 4 | `context.action` 下划线格式（`approve_once`） | 须与 `choice_map` key 匹配 |
| 5 | `root_id` 须是 thread 根帖子 | `_resolve_root_id()` 向上遍历 |
| 6 | `MATTERMOST_CALLBACK_URL` 与 `_callback_bind` 解耦 | Docker 场景必须显式配置 |
| 7 | `AllowedUntrustedInternalConnections` | Docker: `host.docker.internal` |
| 8 | callback server 绑定 `0.0.0.0` | 接受 Docker 容器连接 |
| 9 | HMAC 签名可选 | 未配置 secret 时跳过校验 |
| 10 | `user_id` 校验 | 非白名单用户回调返回 Unauthorized |
| 11 | 回调响应 `update` 字段 | 按钮变灰 + 显示审批结果 |
| 12 | `Event.wait(timeout=300)` | 5 分钟超时自动拒绝 |
| 13 | Webhook 方案已弃用 | 环境变量 `MATTERMOST_WEBHOOK_URL` 和 `MATTERMOST_APPROVAL_CHANNEL_ID` 已从代码中移除 |
