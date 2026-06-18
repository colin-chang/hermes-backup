# macOS launchd Bootstrap Error 5

## 完整错误信息

```
Could not find service "ai.hermes.gateway" in domain for uid: 501
↻ launchd job was unloaded; reloading service definition
Bootstrap failed: 5: Input/output error
Try re-running the command as root for richer errors.
```

## 发生条件（确认过的情况）

- macOS 26.5.1 (Darwin)
- Hermes Desktop 安装后首次启动 Gateway
- `hermes gateway start` 触发
- `~/.hermes/node/bin/node` v22.22.3（Hermes 捆绑版本）

## 根因

macOS `launchctl bootstrap` 的状态不一致——不是 Hermes 的 bug。常见触发场景：

1. **短时间内重复 stop/start**：先 `bootout` 再 `bootstrap`，launchd 域尚未完全释放
2. **系统刚唤醒**：launchd 的用户域尚未完全就绪
3. **plist 刚写入**：文件系统事件尚未被 launchd 消费

## Hermes 的内置降级行为

当 `launchctl bootstrap` 返回 error 5 时，Hermes CLI 自动降级：

```
⚠ launchd cannot manage the gateway on this macOS version (launchctl exit 5).
✓ Started gateway as a background process instead
  It will NOT auto-start at login or auto-restart on crash.
  Logs: ~/.hermes/logs/gateway.log
  Stop it with: hermes gateway stop
```

**这意味着 Gateway 实际上已经启动了**——只是作为普通后台进程而非 launchd 服务。功能完全正常，但缺少两个 launchd 特性：
- ❌ 不会开机自启
- ❌ 不会崩溃自动重启

## 已验证的修复方法

等待 5-10 秒后重新执行，通常第二次就能成功注册：

```bash
hermes gateway status
# 应看到 "✓ Gateway service is loaded"
```

## Plist 位置

`~/Library/LaunchAgents/ai.hermes.gateway.plist`

## 已验证的环境

- macOS 26.5.1 (arm64)
- Hermes Desktop 安装
- uid: 501
