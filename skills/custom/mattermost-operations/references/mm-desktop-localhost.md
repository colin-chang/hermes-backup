# Mattermost Desktop 本地直连配置

## 问题

Mac 端 Mattermost Desktop 配置 localhost:8065 后，自动切换到 CloudFlare Tunnel 域名（如 `https://mm.a-nomad.com/`），导致网络链路变长、不稳定。

## 根因

不是服务端重定向。`SiteURL` 为空时服务器不做重定向。是 Desktop 客户端的 `config.json` 硬编码了 CF Tunnel 域名。

## Desktop 配置文件路径

```
~/Library/Containers/Mattermost.Desktop/Data/Library/Application Support/Mattermost/config.json
```

## 修复

完全退出 Mattermost Desktop（⌘Q），编辑 `config.json`：

```json
"servers": [
  {
    "name": "Local",
    "url": "http://localhost:8065",
    "order": 0
  },
  {
    "name": "Remote (CF Tunnel)",
    "url": "https://mm.a-nomad.com/",
    "order": 1
  }
]
```

保留两个服务器：本地直连为主（order 0），CF Tunnel 为备（order 1）。

## 验证

1. `docker ps --filter name=mm-app` 确认端口映射 `0.0.0.0:8065->8065`
2. `grep SiteURL config.json` 确认服务端 `SiteURL: ""`（空，不做重定向）
3. 重启 Desktop 后检查是否默认连接 Local 服务器
