---
name: mattermost-operations
description: Mattermost 自部署运维 — 推送通知/网络/配置/容器管理
version: 2.0.0
---

# Mattermost 运维操作

Mattermost 是用户的主消息平台（Docker 部署于 `~/Developer/Services/Mattermost/`），用于 Hermes Agent。本 Skill 覆盖日常运维、故障诊断和配置管理。

## 变更记录

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

## 网络问题

Mattermost 容器访问外网可能受 GFW 影响。解决方案：
1. 容器配 `HTTP_PROXY` / `HTTPS_PROXY` 环境变量
2. 搬至蒙特利尔后自然解决
