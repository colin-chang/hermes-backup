# Mattermost Desktop：编辑 Server URL 静默回退

## 症状

Mattermost Desktop（macOS）中编辑已有 server 的 URL：

1. 打开 Server 管理 → 选择已有 server（如 `https://mm.a-nomad.com`）
2. 将 URL 改为 `http://localhost:8065`
3. 保存成功
4. **重新打开 Server 管理 → URL 已自动恢复为 `https://mm.a-nomad.com`**

## 根因

Desktop 客户端（Electron 壳）存储 server 信息时有两层数据：

| 层 | 来源 | 示例 |
|---|---|---|
| **本地存储**（electron-store） | 用户保存时写入 | `http://localhost:8065` |
| **Tab origin**（webContents） | 活动连接的实际 URL | `https://mm.a-nomad.com` |

Server 管理弹窗预填充 URL 字段时，**不从本地存储读取，而是从该 server 当前 tab 的 webContents origin 读取**。编辑旧 server 时，旧 tab 的 origin 仍然是原来的域名，存入本地存储的值被 tab origin 覆盖。

## 排查路径

编辑 URL 保存后自动回退时，按以下顺序排查：

1. **排除服务端**：确认 `SiteURL` 为空（不会覆盖客户端 URL）
   ```bash
   # config.json 中 ServiceSettings.SiteURL 应为 ""
   ```
2. **排除反向代理 redirect**：`curl -sI http://localhost:8065` 不应返回 301/302
3. **确认客户端**：前两步排除后，问题在 Desktop 应用本身 → 使用下方绕过方案

## 绕过方案

**删除旧 server → 新建 server，不要编辑。**

1. Desktop 客户端 → Server 管理 → 删除旧 server
2. 新增 Server → 输入 `http://localhost:8065`
3. 新 server 没有旧 tab 数据干扰，URL 稳定保存

## 适用场景

- Bot 与 Mattermost 同主机部署，需要切换为 `localhost` 直连（绕过 Cloudflare WebSocket 超时）
- 需要在不同网络环境下使用不同 URL 访问同一服务器
- 任何需要修改已有 server URL 的场景
