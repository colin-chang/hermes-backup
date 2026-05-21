---
name: mattermost-operations
description: Mattermost 自部署运维 — 推送通知/网络/配置/容器管理
version: 2.9.0
---

# Mattermost 运维操作

Mattermost 是用户的主消息平台（Docker 部署于 `~/Developer/Services/Mattermost/`），用于 Hermes Agent。本 Skill 覆盖日常运维、故障诊断和配置管理。

## 变更记录

- **v2.9.0** (2026-05-21): 插件重命名 `mattermost-approval` → `mattermost-enhancer`。P32（Channel/Thread 会话区分）经用户测试确认通过。所有代码示例和日志 logger 名称同步更新
- **v2.8.0** (2026-05-21): **重大修正** — P32/P33 完全重写：MM Slash Command payload **原生包含 `root_id` 字段**（Channel 顶层为空，Thread 中为 root post ID），无需 API 反查。`_find_user_thread_root_id()` 已删除。P17 根因描述更新。references/slash-command-architecture.md "关键缺失：无 root_id" 节重写为 "root_id 字段：Thread 上下文"
- **v2.7.0** (2026-05-21): 新增 P33（HTTP 回调时序——asyncio.sleep 等待消息创建）；P32 补充时序根因
- **v2.6.0** (2026-05-21): 新增 P31（Deny 后按钮不消失需清空 actions）+ P32（Channel/Thread 会话区分 — 查用户最近帖子而非只找有 root_id 的帖子）；更新 API 反查代码示例
- **v2.5.0** (2026-05-21): 新增 P30（LLM 自报模型错误需 _pending_model_notes）；P25 补充 select name 字段作 placeholder；补充模型切换诊断方法
- **v2.4.0** (2026-05-21): P25 修正为 select 下拉列表替代按钮；新增 P28（select 回调用 selected_option 非 model_id）+ P29（日志截断 [:60] 误判 session_key 不匹配）
- **v2.3.0** (2026-05-21): 重大更新 P23-P27——P23/P26 修正为绕过 switch_model() 直接构建 override；P24 扩展到 Bot API 发帖（不仅是 update）；新增 P27（Slash Command 响应以用户身份显示→返回空 {}）
- **v2.2.0** (2026-05-20): 新增 Pitfall 23-26（switch_model 需 explicit_provider/update 响应消息重复/模型列表混乱/模型切换 api_key 为空失效）；补充卡片更新机制说明
- **v2.1.0** (2026-05-20): 新增 Pitfall 18-22（callback 异常吞噬/ImportError 隐藏/Bot API 权限/插件发现降级/Slash Command URL 为空降级 WS）
- **v2.0.0** (2026-05-19): 修正 v11.x Team Edition HPNS/TPNS License 要求；新增 push-proxy 自建指南；修正容器无 shell 的诊断命令
- **v1.0.0**: 初始版本

## 触发条件

- 用户询问 Mattermost 相关问题（推送通知/配置/网络/容器/升级）
- Mattermost 移动端或桌面端异常
- 服务器端日志分析
- 容器管理（mm-app / mm-postgres）

## 部署架构

| 组件 | 容器名 | 端口 | 说明 |
|------|--------|------|------|
| 应用 | `mm-app` | 8065 | Mattermost Server |
| 数据库 | `mm-postgres` | 5432 | PostgreSQL |
| 隧道 | `cf-tunnel` | — | Cloudflare Tunnel（公网访问） |

配置文件：`volumes/app/mattermost/config/config.json`
日志文件：`volumes/app/mattermost/logs/mattermost.log`

## 推送通知（Push Notifications）

Mattermost 移动端推送通知的配置和故障诊断见 [references/push-notifications.md](references/push-notifications.md)。

核心要点：
- **v11.x 起 Team Edition 的 HPNS 和 TPNS 均需 Enterprise License**。日志会出现 `"Push notifications are disabled - license missing"`
- 唯一免费方案：自建 [mattermost-push-proxy](references/mattermost-push-proxy-setup.md)（需 Firebase + Apple APNs 凭证）
- 替代方案：降级到 v10.x ESR 保留免费 TPNS，或容忍 WebSocket 兜底（App 关闭久了收不到）
- 容器无 Shell（最小镜像），诊断用 `docker inspect` + 日志文件，不能 `docker exec mm-app wget/curl`

## 常用诊断命令

```bash
# 查看容器状态
docker ps --filter name=mm-

# 查看推送相关日志（容器无 shell，直接读宿主机挂载的日志文件）
grep -i 'push\|notification.*error' volumes/app/mattermost/logs/mattermost.log | tail -30

# 查看推送配置
grep -i 'SendPush\|PushNotif' volumes/app/mattermost/config/config.json

# 检查容器环境变量（含代理配置）
docker inspect mm-app --format '{{range .Config.Env}}{{println .}}{{end}}' | grep -i 'proxy\|push'

# 注意：mm-app 容器无 sh/ash/bash，不能用 docker exec 跑 wget/curl
# 测试外网连通性需从宿主机跑 curl，或用 docker inspect 检查 proxy 配置
```

## Slash Command 与插件架构

Mattermost 客户端拦截所有 `/` 开头消息，**必须**注册 Slash Command 才能接收。
Slash Command payload 包含 `root_id` 字段（Channel 顶层为空，Thread 中为 root post ID），无需 API 反查。

详见 [references/slash-command-architecture.md](references/slash-command-architecture.md)（含 27 个已知 Pitfall）。

核心要点：
- **删除 Slash Command 注册 ≠ `/model` 走 WebSocket** — 会被客户端静默拦截
- Slash Command 响应以用户身份发送 → 卡片改用 Bot API `_api_post("posts", ...)` 发帖
- Interactive Message 限制：5 actions/attachment, 5 attachments/message（但 select 下拉列表只需 1 action，推荐使用）
- session_key 构建需要 `channel_id + root_id`，Slash Command payload 的 `root_id` 字段提供 Thread 上下文（Channel 顶层时为空）
- **Callback Server 异常吞噬**（P18）：`_handler` 的 `except` 不记录日志 → 静默空回复，必须加 `logger.exception()`
- **插件 ImportError 隐藏**（P19）：`from .module import nonexistent_func` 在调用时才抛异常，被 P18 吞噬
- **Bot API 无法读取 Slash Command URL**（P20）：非 admin token 返回空值，需查数据库
- **插件发现失败被 debug 吞噬**（P21）：Gateway 启动时插件加载异常不显眼，运行时静默降级为内置适配器
- **Slash Command URL 为空时降级为 WebSocket**（P22）：导致双重显示+错误 thread+用户头像
- **switch_model 路由 custom_provider 模型到错误 provider**（P23）：必须绕过 switch_model()，直接从 custom_providers 配置构建 session override（4 字段：provider/base_url/api_key/api_mode），否则 api_key 为空 override 不生效
- **Bot API 帖子 message + props 双重显示**（P24）：`_post_card_in_thread()` 的 message 必须留空，内容仅放 props.attachments；callback update 响应同理
- **模型选择器用 select 下拉列表**（P25）：取代多行按钮，1 个 attachment + 1 个 action，`name` 字段作为 placeholder 显示当前模型（如 "当前: zenmux/minimax-m2.7"）
- **LLM 自报模型错误**（P30）：模型切换在 API 层面生效，但 LLM 回答"当前模型"时仍报默认模型——必须设置 `runner._pending_model_notes[session_key]`，Gateway 会在下条消息前注入切换通知
- **select 回调用 selected_option 非 model_id**（P28）：回调中 `context.selected_option` 包含选中值，需兼容 button 格式
- **日志截断 [:60] 误判 session_key 不匹配**（P29）：完整 session_key 81 字符被截断为 60，导致误认为 root_id 不完整
- **Deny 后卡片按钮不消失**（P31）：MM 的 `update` 响应只替换 message/props，保留原始按钮。必须在 `props.attachments` 中返回空 `actions` 数组来清除按钮，否则 Deny 后用户可重复点击导致 "No pending approval found" 报错。即使 `count == 0`（审批已处理）也必须返回 `update` 清空按钮，不能只返回 `ephemeral_text`
- **Channel/Thread 会话区分**（P32）：**MM Slash Command payload 原生包含 `root_id` 字段！** 在 Thread 中发送时 `root_id=<root_post_id>`，在 Channel 顶层发送时 `root_id=""`。直接从 `params.get("root_id", "") or None` 读取即可，无需 API 反查。旧版文档声称"payload 不含 root_id"是错误的——可能当时未测试 Thread 中的场景。`_find_user_thread_root_id()` 方法已删除

卡片更新机制关键规则：`{"update": {"message": "...", "props": card}}` 会导致 MM 同时渲染 message 正文和 props.attachments，必须避免内容重叠。select 下拉列表选择后卡片被 update 替换（无按钮），用户需重新 `/model` 获取新卡片。详见 [references/slash-command-architecture.md](references/slash-command-architecture.md)。

## 网络问题

Mattermost 容器访问外网可能受 GFW 影响。解决方案：
1. 容器配 `HTTP_PROXY` / `HTTPS_PROXY` 环境变量
2. 搬至蒙特利尔后自然解决
