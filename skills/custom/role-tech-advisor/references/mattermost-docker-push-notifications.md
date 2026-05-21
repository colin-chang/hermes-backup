# Mattermost Docker 部署 — 推送通知配置备忘

> 环境：Mattermost Team Edition v11.7.0, Docker Compose (OrbStack), macOS

## TPNS vs HPNS（v11.7.0 Team Edition）

| 服务 | 地址 | 状态 | 说明 |
|------|------|------|------|
| **TPNS** | `https://push-test.mattermost.com` | ✅ 可用 | Team Edition 免费推送，官方 App Store App 可用 |
| **HPNS** | `https://push.mattermost.com` | ❌ 需 License | v11.7.0 起要求 Enterprise License |

## 关键发现：假阳性 Warning

v11.7.0 Team Edition 使用 TPNS 时会出现以下**假阳性**信号，**不影响实际推送**：

### 1. 服务端日志
```
"Push notifications are disabled - license missing"
```
原因：`app/notification.go:43` 的 License 检查在日志层面触发，但不阻断 TPNS 实际推送通路。

### 2. 移动端弹窗
> "无法从此服务器接收通知。由于该服务器的配置，在移动应用程序中无法收到通知。"

原因：移动端调用了服务端健康检查接口，读到 `disabled` 状态后弹窗。**但真正的推送消息（走 TPNS → APNs）正常送达，即使 App 被从后台完全杀死也能收到。**

### 结论
- 弹窗和日志 Warning 可以忽略
- 不要因此切换到 HPNS（会真的断开推送）
- 不要因此折腾自建 push-proxy + 自定义 App 编译（完全多余）

## Docker 容器代理配置（OrbStack）

Docker 容器默认不走宿主机代理，需在 `docker-compose.yml` 的 `mattermost` 服务中显式设置：

```yaml
environment:
  - HTTP_PROXY=http://proxy.orb.internal:8305
  - HTTPS_PROXY=http://proxy.orb.internal:8305
  - NO_PROXY=localhost,127.0.0.1,::1,postgres,mm-app,*.internal,*.local
```

**OrbStack 代理地址**：`proxy.orb.internal:8305`（通过 `docker info` 可确认）

## 部署信息

- **项目路径**：`/Users/Colin/Developer/Services/Mattermost`
- **重启脚本**：`start.sh`（down + up，使用 `docker-compose.without-nginx.yml` 覆写）
- **配置文件**：`volumes/app/mattermost/config/config.json`
- **Mattermost 镜像**：`mattermost-team-edition:11.7.0`

## 如需自建推送（未来参考）

仅在以下情况需要：
1. Mattermost 彻底关闭 TPNS
2. 需要更高的推送可靠性 SLA

自建需要：Apple Developer 账号 + APNs Key (.p8) + 自定义编译 Mattermost App + `mattermost-push-proxy` Docker 容器。App 必须用自己的 Bundle ID 签名，官方 App Store 应用无法连接自建 push-proxy。
