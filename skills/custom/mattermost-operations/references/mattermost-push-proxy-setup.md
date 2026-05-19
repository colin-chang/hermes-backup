# Mattermost Push Proxy 自建指南

## 背景

Mattermost v11.7.0 起，Team Edition 使用 HPNS (`push.mattermost.com`) 或 TPNS (`push-test.mattermost.com`) 都会返回：

```json
{"msg": "Push notifications are disabled - license missing"}
```

唯一的免费方案是自建 [mattermost/mattermost-push-proxy](https://github.com/mattermost/mattermost-push-proxy)。

## 架构

```
Mattermost Server → Push Proxy (自建) → APNs (iOS) / FCM (Android) → 手机
```

Push Proxy 不直接连接手机，而是转发到 Apple/Google 的推送服务。

## 前置准备

### 1. Firebase Cloud Messaging（Android 推送）

1. 前往 [Firebase Console](https://console.firebase.google.com/) → 创建项目
2. 项目设置 → **服务账号** → **生成新的私钥**，下载 JSON 文件
3. 记录文件路径，后续配置用

### 2. Apple Push Notification Service（iOS 推送）

1. 需要 Apple Developer 账号（$99/年）
2. [Apple Developer Portal](https://developer.apple.com/account/) → Keys → 创建 Auth Key (.p8)
3. 记录三个值：
   - **Auth Key 文件** (.p8 下载)
   - **Key ID**（Portal 中显示）
   - **Team ID**（Membership 中显示）
   - **Bundle ID**（App 的捆绑包标识符，官方 App 用 `org.mattermost.Mattermost`）

## Docker Compose 集成

在你的 `docker-compose.yml` 中添加：

```yaml
services:
  push-proxy:
    image: mattermost/mattermost-push-proxy:latest
    restart: unless-stopped
    container_name: mm-push-proxy
    ports:
      - "8066:8066"
    volumes:
      - ./volumes/push-proxy/config:/mattermost-push-proxy/config
      - /path/to/firebase-key.json:/config/firebase-key.json:ro   # FCM 私钥
      - /path/to/AuthKey.p8:/config/AuthKey.p8:ro                  # APNs Key
```

## Push Proxy 配置文件

创建 `volumes/push-proxy/config/mattermost-push-proxy.json`：

```json
{
  "ListenAddress": ":8066",
  "AndroidPushSettings": [{
    "Type": "android_fcm",
    "ServiceFileLocation": "/config/firebase-key.json"
  }],
  "ApplePushSettings": [{
    "Type": "apple_rn",
    "ApplePushUseDevelopment": false,
    "ApplePushTopic": "org.mattermost.Mattermost",
    "AppleAuthKeyFile": "/config/AuthKey.p8",
    "AppleAuthKeyID": "YOUR_KEY_ID",
    "AppleTeamID": "YOUR_TEAM_ID"
  }]
}
```

## Mattermost 服务端配置

修改 `config.json`：

```json
{
  "EmailSettings": {
    "SendPushNotifications": true,
    "PushNotificationServer": "http://push-proxy:8066"
  }
}
```

或通过环境变量：
```
MM_EMAILSETTINGS_PUSHNOTIFICATIONSERVER=http://push-proxy:8066
```

## 容器内走代理

如果 push proxy 容器也需要走代理连接 APNs/FCM：

```yaml
environment:
  - HTTP_PROXY=http://proxy.orb.internal:8305
  - HTTPS_PROXY=http://proxy.orb.internal:8305
```

## 分流部署思路

| 用户场景 | 方案 |
|---------|------|
| 大陆开发 + 代理 | 容器走代理 → 直连 APNs/FCM |
| 境外 VPS | 无需代理，直接跑 Push Proxy |
| 长期大陆 | Push Proxy 部署在境外 VPS，Mattermost 通过代理连接 Push Proxy |

## 参考

- https://developers.mattermost.com/contribute/more-info/mobile/push-notifications/service/
- https://github.com/mattermost/mattermost-push-proxy
- https://hub.docker.com/r/mattermost/mattermost-push-proxy
