# Mattermost 推送通知（Push Notifications）

## 三种推送模式

| 模式 | 版本要求 | 受众 | URL | 端口 | SLA |
|------|---------|------|-----|------|-----|
| **TPNS** | v10.x 及更早（含 Team Edition）；**v11.x 起需 License** | 非生产/个人 | `https://push-test.mattermost.com` | 443 | ❌ 无 |
| **HPNS** | Enterprise / Professional（所有版本） | 生产环境 | `https://push.mattermost.com` | 443 | ✅ 有 |
| **自建 Proxy** | 所有版本（唯一免费方案 v11.x+） | Team Edition / 自定义 App | 自行部署 | 自定义 | 自行保证 |

> ⚠️ **v11.7.x 重大变更**：Mattermost 11.7.0 起，Team Edition 使用 HPNS/TPNS 均会报 `"Push notifications are disabled - license missing"`。详见 [mattermost-push-proxy-setup.md](mattermost-push-proxy-setup.md)。

> **TPNS 中文文档**：https://docs.mattermost.com/administration-guide/configure/push-notification-server-configuration-settings.html

## 配置项（config.json）

```json
{
  "EmailSettings": {
    "SendPushNotifications": true,
    "PushNotificationServer": "https://push-test.mattermost.com",
    "PushNotificationContents": "full"
  }
}
```

环境变量等价：
- `MM_EMAILSETTINGS_SENDPUSHNOTIFICATIONS=true`
- `MM_EMAILSETTINGS_PUSHNOTIFICATIONSERVER=https://push-test.mattermost.com`

也可通过 **System Console > Environment > Push Notification Server** 在 Web UI 中配置。

## 移动端错误："无法从此服务器接收通知"

此错误意味着 Mattermost Server 无法成功连接到推送代理（TPNS/HPNS/自建）。在移动端登录时，服务器会测试推送连通性，失败则弹此提示。

### 诊断流程

#### 第一步：确认配置和运行时环境
```bash
# 确认配置文件中的推送设置
grep -i 'SendPush\|PushNotif' volumes/app/mattermost/config/config.json

# 确认容器是否有 PushNotificationServer 的 env 覆盖
docker inspect mm-app --format '{{range .Config.Env}}{{println .}}{{end}}' | grep -i push
```
预期：`"SendPushNotifications": true`，`PushNotificationServer` 有合法的 URL。

#### 第二步：查看服务端日志（最关键一步）
```bash
grep -i 'push\|license\|notification' volumes/app/mattermost/logs/mattermost.log | tail -30
```

#### 第三步：根据日志错误分类处理

**错误模式 A：`push notifications are disabled - license missing`** 🔴
```json
{"msg": "Push notifications are disabled - license missing"}
{"msg": "Push notifications have been disabled. Update your license or go to System Console > Environment > Push Notification Server to use a different server"}
```
→ **v11.x Team Edition 不再免费使用 HPNS/TPNS**。解决方案：
1. 自建 [mattermost-push-proxy](mattermost-push-proxy-setup.md)（唯一免费方案）
2. 降级到 v10.x ESR

**错误模式 B：`unsupported protocol scheme ""`**
```json
{"error": "Post \"/api/v1/send_push\": unsupported protocol scheme \"\""}
```
→ PushNotificationServer URL 被解析为空。检查 config.json 中是否有完整 URL（含 `https://`），以及环境变量是否意外覆盖为空。

**错误模式 C：`TLS handshake timeout`**
```json
{"error": "Post \"https://push-test.mattermost.com/api/v1/send_push\": net/http: TLS handshake timeout"}
```
→ 容器无法建立到推送服务器的 TLS 连接。原因：网络阻断或容器未走代理。

验证方法（宿主机，非容器）：
```bash
curl -s -o /dev/null -w '%{http_code} in %{time_total}s\n' --connect-timeout 5 https://push.mattermost.com/api/v1/health
# 200 = 通达；000 = 不通
```
注意：mm-app 容器无 shell（`docker exec mm-app sh` 会失败），不能从容器内测网络。

**错误模式 D：`context deadline exceeded`**
→ 连接超时，与 C 类似，网络不可达。

#### 第四步：网络修复

**方案一：容器配代理**（适用于大陆/代理环境）
在 `docker-compose.yml` 的 mattermost 服务中添加环境变量：
```yaml
environment:
  - HTTP_PROXY=http://proxy.orb.internal:8305      # OrbStack 内网代理
  - HTTPS_PROXY=http://proxy.orb.internal:8305
  - NO_PROXY=localhost,127.0.0.1,::1,postgres,mm-app,*.internal,*.local
```
> **注意**：OrbStack 使用 `proxy.orb.internal:8305`；如用 Docker Desktop 或其他代理，地址可能不同。宿主机 `networksetup -getwebproxy Wi-Fi` 和 `docker info | grep -i proxy` 可查当前代理配置。

然后重启容器。

**方案二：自建 Push Proxy**（v11.x Team Edition 唯一完整方案）
详见 [mattermost-push-proxy-setup.md](mattermost-push-proxy-setup.md)。需准备：
- Apple APNs Auth Key (.p8) + Key ID + Team ID
- Firebase Cloud Messaging Server Key

**方案三：降级到 v10.x ESR**（保留免费 TPNS）
```bash
# 在 .env 中修改
MATTERMOST_IMAGE_TAG=10.x-esr  # 具体版本号
```
然后 `bash start.sh` 重建。

**方案四：容忍 WebSocket 兜底**
不配推送，依赖 WebSocket 长连接。效果：App 在后台短时间内能收到，完全关闭后收不到。

## TPNS 与 HPNS 的区别总结

| | TPNS | HPNS |
|------|------|------|
| 是否需要 License | ✅ v11.x 起需要；v10.x 及更早不需要 | ✅ Enterprise/Professional |
| 稳定性 | 无 SLA | 有 SLA |
| 隐私保证 | 无 | 有 Data Processing Addendum |
| ID-only 推送 | 不支持 | 支持（更高隐私级别） |
| 中国大陆可用性 | 可能被阻断 | 可能被阻断 |

> ⚠️ **v11.7.0 实测**：`SendPushNotifications=true` + `PushNotificationServer=https://push.mattermost.com`（或 `push-test`）→ 日志 `"Push notifications are disabled - license missing"`。Team Edition 用户需自建 Push Proxy 或降级到 v10.x ESR。
