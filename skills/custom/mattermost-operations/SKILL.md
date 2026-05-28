---
name: mattermost-operations
description: Mattermost 自部署运维 — 推送通知/网络/配置/容器管理
version: 4.0.0
---
# Mattermost 运维操作
---

## 触发条件

- 用户询问 Mattermost 相关问题（推送通知/配置/网络/容器/升级）
- 用户询问 `hermes-plugin-mattermost-enhancer` 插件相关问题
- Mattermost 移动端或桌面端异常
- 服务器端日志分析
- 容器管理（mm-app / mm-postgres）

> **文档编辑规则**：插件仓库文档先编辑中文版（`README.zh-CN.md`），用户确认定稿后再同步英文版（`README.md`）。
> 完整的代码→文档同步工作流见 [references/readme-sync-workflow.md](references/readme-sync-workflow.md)。

## Mattermost 部署概况

用户通过 Docker Compose 自托管 Mattermost Team Edition，路径：
```
/Users/Colin/Developer/Services/Mattermost/
```

关键文件：
- `docker-compose.yml` — 主服务定义（postgres + mattermost）
- `.env` — 环境变量（域名、镜像版本、DB 密码等）
- `volumes/app/mattermost/config/config.json` — Mattermost 运行时配置
- `volumes/app/mattermost/logs/mattermost.log` — 服务日志

服务容器：`mm-app`（mattermost）、`mm-postgres`（postgres）

### 快速部署/重启命令

```bash
cd /Users/Colin/Developer/Services/Mattermost
docker compose down && docker compose up -d
```
修改 `config.json` 不需要 down，但修改 `docker-compose.yml` 环境变量需要重建容器。

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

**插件 `hermes-plugin-mattermost-enhancer`（`~/.hermes/plugins/mattermost-enhancer/`）已完整覆盖所有 Mattermost 自定义能力：**

*Adapter 覆写（插件加载即生效）：*
- `_resolve_root_id` + Thread root_id 解析（`send()`/`_send_local_file()`/`_send_url_as_file()` 覆写）
- MEDIA 文件不存在时静默跳过（`_send_local_file()` 覆写）
- DM 审批（`send_exec_approval` → DM 卡片 → 按钮回调 → `_handle_callback`）
- `/model` 模型切换（select 下拉列表 + session override + `_pending_model_notes`）
- **Channel → Thread 模型继承**（`pre_gateway_dispatch` hook — Channel 切模型后新 Thread 自动继承）
- `/new` 会话重置（确认卡片 + `_reset_session`）
- `send_typing` Thread 路由修复
- `connect`/`disconnect` 生命周期（回调服务器启停）
- **Clarify 交互卡片渲染**
- **Runtime Footer 内联合并**：`send()` 检测 footer 行拦截后编辑上一条消息追加为脚注
- **WebSocket 心跳 15s**（`_ws_connect_and_listen` 覆写，替代 shell patch，解决 close 258 断连）
- **Media Thread 路由全覆盖**（`send_multiple_images` / `send_image` / `send_image_file` / `send_document` / `send_video` / `send_voice` 覆写，metadata → reply_to 推导）
- `_build_callback_url()` 回调 URL 构建统一化（fallback: `http://{bind}:{port}/mattermost/callback`）

*配套 Shell 脚本（5 个活跃 patch，修复 Plugin 无法触及的调用方代码）：*
- P1: DM 审批 user_id 传入（可选 — adapter 已有 channel members 降级查询）
- P2: 工具进度消息进 Thread
- P3: Clarify Session 分裂修复
- P4: Clarify 并发守护
- P5: auto-resume session 串台去重（Gateway 重启后同 channel 多 Thread 自动恢复时的跨 Thread 消息泄漏）

*Adapter 覆写已覆盖的修复（非 shell patch）：*
- 批量图片 Thread 路由 — `send_multiple_images()` 覆写，从 metadata 提取 thread_id 注入 root_id
- 其他媒体类型 Thread 路由 — `send_image`/`send_document`/`send_video`/`send_voice` 覆写 + `_derive_reply_to()`

*已迁至主脚本 `hermes-patches.sh`（平台通用修复）：*
- 评论→正文合并 (P50)
- 幽灵代码围栏 (P53)
- stream fallback 保留 reply_to (P55)

**`mattermost.py` 源码已零修改**——v0.14.0 起 Mattermost 适配器已从 `gateway/platforms/mattermost.py` 迁移至 bundled plugin，enhancer 已适配新导入路径。所有自定义逻辑均由插件接管。

详见各 reference 文档了解架构细节和已知问题历史。

**关键架构文档：**
- [Slash Command 架构](references/slash-command-architecture.md) — MM interactive message 机制、卡片更新规则
- [同频道多 Thread 并发分析](references/mattermost-concurrent-threads.md) — 代码路径追踪 + 阻塞排查
- [插件 API 契约](~/.hermes/plugins/hermes-plugin-mattermost-enhancer/references/api-contracts.md)
- [插件打包规范](references/plugin-packaging-conventions.md) — 中英文 README / LICENSE / .gitignore / 配套脚本
- [消息碎片化分析](references/mattermost-streaming-fragmentation.md)（由 `hermes-agent` Skill 维护）

## 网络问题

### WebSocket 稳定性（Cloudflare 反向代理陷阱）

**Bot 和 Mattermost 在同一主机时，必须用 `localhost` 直连，不要走 Cloudflare。** `MATTERMOST_URL` 配置项决定了 Bot 的 WebSocket 和 API 连接目标。如果设为经 Cloudflare 代理的域名（如 `https://mm.example.com`），Cloudflare 的 WebSocket 超时会导致连接每 30 秒断连（close code 258），引发一连串问题：`edit_message` 超时 → Stream fallback → Thread 路由丢失 → 消息截断。

**快速诊断**：
```bash
# 检查是否经 Cloudflare
curl -sI https://<your-domain> | grep -i "server\|cf-ray"
# server: cloudflare = 走 CF ❌

# 检查本地可达性
curl -s http://localhost:8065/api/v4/system/ping
# {"status":"OK"} = 可直连 ✅

# 检查 Bot 连接目标
grep "connecting to w" ~/.hermes/logs/gateway.log | tail -3
# ws://localhost = 直连 ✅ | wss://domain = 走 CF ❌
```

**修复**：在 `.env` 中将 `MATTERMOST_URL=https://mm.example.com` 改为 `MATTERMOST_URL=http://localhost:8065`，然后重启 Gateway。

Mattermost 容器访问外网可能受 GFW 影响。解决方案：
1. 容器配 `HTTP_PROXY` / `HTTPS_PROXY` 环境变量
2. 搬至蒙特利尔后自然解决

## 桌面客户端已知问题

### Server URL 编辑后静默回退

Mattermost Desktop（macOS）编辑已有 server 的 URL 时，保存后重新打开会恢复为旧 URL。根因是弹窗预填充 URL 时读取 tab 的 webContents origin 而非本地存储。绕过方案：删除旧 server → 新建，不要编辑。详见 [references/desktop-client-url-revert.md](references/desktop-client-url-revert.md)。

## 插件 Release 工作流

`hermes-plugin-mattermost-enhancer` 使用 GitHub Actions `release.yml`（`workflow_dispatch`）发布新版本：

```bash
# 1. 推送代码
cd ~/.hermes/plugins/mattermost-enhancer && git push origin main

# 2. 触发 Release workflow（版本号 + Release Notes）
gh workflow run release.yml \
  --repo colin-chang/hermes-plugin-mattermost-enhancer \
  -f version=v2.4.0 \
  -f notes="$(cat <<'EOF'
## v2.4.0 — 修复摘要

1. 修复 A ...
2. 修复 B ...
EOF
)"

# 3. 检查运行结果
gh run list --repo colin-chang/hermes-plugin-mattermost-enhancer --limit 1
```

Workflow 自动完成：版本号写入 `plugin.yaml` → commit + tag → 创建 GitHub Release（含自动生成的 commit log）。

**版本号规则**：根据语义化版本选择 MAJOR/MINOR/PATCH。修复 bug → PATCH，新功能 → MINOR，破坏性变更 → MAJOR。

**Release Notes 最佳实践**：详尽描述每个修复的根因、影响面和修复方式，方便将来排查和追踪。不要只写"修复了 XX 问题"。

## Hermes Cron 定时任务排障

[references/hermes-cron-pitfalls.md](references/hermes-cron-pitfalls.md) — Cron 子代理工具不可用、安检误判、Skill ZWJ 拦截、iMessage 发送模板等已知陷阱 P40-P44。

## 开发技巧

对 `hermes-patches.sh` 等 shell 脚本做大规模修改时的工具选择陷阱：
[references/patch-tool-pitfalls.md](references/patch-tool-pitfalls.md) — `patch` 工具在 heredoc / f-string 上的已知问题及 `execute_code` 替代方案。
[references/hermes-patches-conventions.md](references/hermes-patches-conventions.md) — `hermes-patches.sh` 编写规范：注册表约定、check_grep 选型、`_do_patch` 必须在函数体内、同文件多补丁注册表一一对应。
