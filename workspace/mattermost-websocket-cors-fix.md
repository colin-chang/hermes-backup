# Mattermost WebSocket CORS 拦截导致消息不实时渲染

> 诊断日期：2026-05-18 | 修复状态：✅ 已修复，待重启生效

## 问题表现

在 Mattermost 中接入 Hermes 后，无论 `MATTERMOST_REPLY_MODE` 设为 `off` 还是 `thread`，**频道主消息流中的所有新消息都不会主动渲染**，包括：

- Agent 处理过程的工具调用进度
- 流式输出的中间状态
- 最终的回复内容

**触发条件：** 通过 `http://127.0.0.1:8065` 本地访问 Mattermost 时出现。

**唯一的"刷新"方式：** 切换频道再切回来，或者刷新浏览器页面，新消息才会加载出来。

> ⚠️ 通过 Cloudflare Tunnel 域名 `https://mm.a-nomad.com` 远程访问时**不受影响**。

---

## 根因分析

### 直接原因

Mattermost 服务端拒绝了浏览器客户端的 WebSocket 升级请求。

Mattermost 日志（`docker logs mm-app`）中反复出现：

```
URL Blocked because of CORS. Url: http://127.0.0.1:8065
websocket: request origin not allowed by Upgrader.CheckOrigin
user_id: 57fzdj87x3f3tjp85w8fy7ugyy
http_code: 400
```

### 机制解释

```
┌─────────────────────────────────────────────────────────────┐
│                      Mattermost 消息推送流程                   │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  ① Bot 通过 REST API POST 消息到频道                           │
│     POST /api/v4/posts → 201 Created ✅                       │
│                          │                                   │
│  ② 服务器广播 posted 事件到 WebSocket                           │
│     ┌─ Bot WebSocket (aiohttp)     → 收到事件 ✅               │
│     └─ 用户浏览器 WebSocket         → ❌ 连接被拒               │
│                                                             │
│  ③ 用户浏览器：没有 WebSocket → 看不到实时推送                    │
│     刷新/切换频道 → REST API 拉取 → 消息才出现                    │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### 关键技术点

| 组件 | WebSocket 连接 | Origin 头 | 结果 |
|------|---------------|-----------|------|
| Hermes Gateway (Bot) | aiohttp | **不发送** | ✅ 绕过 CORS 检查 |
| 用户浏览器（本地） | 浏览器 WebSocket API | `http://127.0.0.1:8065` | ❌ 被拦截 |
| 用户浏览器（CF Tunnel） | 浏览器 WebSocket API | `https://mm.a-nomad.com` | ✅ 匹配 SiteURL |

### 为什么 Bot 不受影响

Hermes Gateway 使用 Python `aiohttp` 库连接 WebSocket。`aiohttp` 默认不发送 `Origin` 请求头。Mattermost 的 `Upgrader.CheckOrigin` 在没有 `Origin` 头时**跳过检查**，因此 Bot 的 WebSocket 连接始终正常——这解释了为什么只有人类用户的浏览器客户端受影响。

### 为什么 CF Tunnel 远程访问正常

配置文件 `.env` 中设置了：
```
DOMAIN=mm.a-nomad.com
MM_SERVICESETTINGS_SITEURL=https://${DOMAIN}
```

通过 CF Tunnel 远程访问时，浏览器发送的 `Origin: https://mm.a-nomad.com` 与 `SiteURL` 匹配，检查通过。只有通过 `127.0.0.1` 本地访问时，`Origin: http://127.0.0.1:8065` 与 `https://mm.a-nomad.com` 不匹配，才被拦截。

---

## 修复方案

### 修改内容

**文件：** `/Users/Colin/Developer/Services/Mattermost/volumes/app/mattermost/config/config.json`

```diff
- "AllowCorsFrom": "",
+ "AllowCorsFrom": "http://127.0.0.1:8065",
```

### Milk 生效

修改 `config.json` 后需要重启 Mattermost 容器：

```bash
cd /Users/Colin/Developer/Services/Mattermost
docker compose restart mattermost
```

`AllowCorsFrom` 字段在 Mattermost WebSocket upgrader 初始化时读取，不支持热重载。

### 为什么选择 AllowCorsFrom 而非其他方案

| 方案 | 影响 | 评估 |
|------|------|------|
| `AllowCorsFrom: "http://127.0.0.1:8065"` | 仅允许本地访问 | ✅ 推荐：最小权限 |
| `AllowCorsFrom: "*"` | 允许所有来源 | ⚠️ 安全风险 |
| `EnableDeveloper: true` | 禁用所有安全检查 | ❌ 过度放宽 |
| 修改 `SiteURL` 为 `http://127.0.0.1:8065` | 破坏 CF Tunnel 访问 | ❌ 不可行 |

### 多 Origin 配置（如果需要）

Mattermost 的 `AllowCorsFrom` 支持空格分隔多个 Origin：

```
"AllowCorsFrom": "http://127.0.0.1:8065 http://192.168.1.100:8065"
```

---

## 验证方法

### 1. 确认配置生效

```bash
curl -s -H "Authorization: Bearer $MATTERMOST_TOKEN" \
  http://127.0.0.1:8065/api/v4/config | \
  jq '.ServiceSettings.AllowCorsFrom'
# 期望输出: "http://127.0.0.1:8065"
```

### 2. 确认不再有 WebSocket 拦截日志

```bash
docker logs mm-app 2>&1 | grep "request origin not allowed"
# 修复后应该没有新的同类输出
```

### 3. 功能验证

1. 浏览器打开 `http://127.0.0.1:8065`
2. 在频道中 @Hermes 发送消息
3. 观察是否能看到实时的工具调用进度和回复

### 4. 确认 CF Tunnel 远程访问不受影响

通过 `https://mm.a-nomad.com` 访问，WebSocket 应继续正常工作。

---

## 排查过程记录

| 步骤 | 检查内容 | 结果 |
|------|---------|------|
| 1 | 查看频道消息是否存在（REST API） | ✅ 消息已在数据库中 |
| 2 | Bot 发送消息是否成功（`_api_post`） | ✅ 201 Created |
| 3 | WebSocket 事件广播测试（Python 脚本） | ✅ `posted` 事件正常到达 |
| 4 | `config.json` 检查 | ❌ `SiteURL` 空，`AllowCorsFrom` 空 |
| 5 | 环境变量检查 | `MM_SERVICESETTINGS_SITEURL=https://mm.a-nomad.com` |
| 6 | Mattermost 容器日志 | ❌ CORS WebSocket 拦截错误 |

### 关键诊断脚本

用于确认 WebSocket 广播正常但客户端连接被拒的 Python 测试：

```python
# 使用 Hermes venv 中的 aiohttp
# 连接 Bot WebSocket → POST 测试消息 → 等待 posted 事件
# 结果：Bot 能收到 posted 事件 ✅ → 服务器广播正常 → 问题在客户端 CORS
```

---

## 相关配置位置

| 配置项 | 位置 |
|--------|------|
| Mattermost config.json | `/Users/Colin/Developer/Services/Mattermost/volumes/app/mattermost/config/config.json` |
| Docker 环境变量 | `/Users/Colin/Developer/Services/Mattermost/.env` |
| Cloudflare Tunnel | `/Users/Colin/Developer/Services/CF/docker-compose.yaml` |
| Hermes Mattermost 配置 | `/Users/Colin/.hermes/.env`（`MATTERMOST_*`） |
| Hermes gateway 日志 | `/Users/Colin/.hermes/logs/gateway.log` |

---

## 关联 Bug：CRT Thread root_id 修复

> 诊断日期：2026-05-18 | Issue：[#28005](https://github.com/NousResearch/hermes-agent/issues/28005) | 修复状态：✅ 已修复，需重启 Gateway

### 问题表现

在 Mattermost CRT Thread 中发消息给 Hermes 时：
- 主频道能看到工具调用进度（初始几条）
- 过了一段时间后工具调用进度停止更新
- Thread 里没有任何回复（无结果、无错误）
- Agent 实际上已完成处理，但所有发送都失败了

### 根因

`gateway/platforms/mattermost.py` 的 `send()` 方法中，`root_id` 使用了错误的 ID：

```
用户从 Thread 中发消息
  → post.id = "msg_B"（用户刚发的消息）
  → post.root_id = "msg_A"（Thread 的真正根消息）

send() 的错误行为:
  → payload["root_id"] = reply_to (= "msg_B")  ← 这是用户的消息，不是根！
  → Mattermost 返回 400 "Invalid RootId parameter"
  
正确行为:
  → payload["root_id"] = metadata["thread_id"] (= "msg_A")  ← 正确的 Thread 根
```

**为什么主频道消息没问题：** 用户在主频道发的消息本身就是根级帖子，使用 `reply_to` 作为 `root_id` 合法。只有在 Thread 内部回复时，用户的回复消息不是根消息，才会触发这个 Bug。

### 修复

**文件：** `gateway/platforms/mattermost.py` 第 272-274 行

```diff
-            # Thread support: reply_to is the root post ID.
+            # Thread support: use the thread's root_id from metadata when
+            # replying inside an existing CRT Thread. Mattermost requires
+            # root_id to point to the root-level post, not a nested reply.
+            # Fall back to reply_to for top-level channel messages (where
+            # the user's message itself is a valid thread root).
             if reply_to and self._reply_mode == "thread":
-                payload["root_id"] = reply_to
+                thread_root = (metadata or {}).get("thread_id")
+                payload["root_id"] = thread_root or reply_to
```

### 生效

重启 Hermes Gateway：

```bash
hermes gateway restart
```

### Patch 脚本

已集成到 `~/.hermes/scripts/hermes-patches.sh`（Patch 6），升级后可一键恢复：

```bash
./hermes-patches.sh check   # 检查状态
./hermes-patches.sh apply   # 应用所有补丁
```
