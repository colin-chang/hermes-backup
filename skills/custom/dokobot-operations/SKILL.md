---
name: dokobot-operations
description: Dokobot 运维与排障 — bridge 生命周期、冷/热启动、日志分析、"No local bridge running" 诊断流程。当 dokobot read --local 报错或 bridge 不稳定时使用。
read_when:
  - dokobot read --local 报 "No local bridge running" 或超时
  - dokobot read --local 报 "Frame with ID 0 is showing error page"
  - bridge 间歇性不可用，需要排查生命周期问题
  - 需要理解 bridge 启动机制（谁启动、何时启动）
  - 定时任务中 dokobot 偶尔失败，需要加固
emoji: 🌐
category: custom
---

# Dokobot 运维与排障

[[toc]]

## Bridge 架构

```
dokobot read --local
        │
        ▼
  ┌─────────────┐     连接 Unix socket        ┌──────────────────┐
  │ dokobot CLI │ ─────────────────────────▶  │ ~/.dokobot/      │
  │             │                              │ bridges/*.sock   │
  └─────────────┘                              └──────┬───────────┘
        │                                    socket 不存活
        │  通知 Chrome 扩展（Native Messaging）     │
        ▼                                           ▼
  ┌──────────────────────────────────────────────────────────┐
  │                  Google Chrome（bridge 父进程）             │
  │  ┌────────────────────────────────────────────────────┐  │
  │  │  Dokobot Extension (0.3.x)                         │  │
  │  │  chrome-extension://dlbiigchkpmpijahmlofleeemiomaneo│  │
  │  └────────────────────┬───────────────────────────────┘  │
  │                       │ stdio                             │
  │                       ▼                                   │
  │  bridge-host.sh → node bridge/main.js                     │
  │  （创建 Unix socket + 与扩展握手）                           │
  └──────────────────────────────────────────────────────────┘
```

**谁启动 bridge？** Chrome 浏览器（作为 Native Messaging Host 的父进程），不是 LaunchAgent/LaunchDaemon。

**何时启动？** 当 `dokobot read --local` 被调用且 Unix socket 不存在时，CLI 通过 Chrome Native Messaging 协议通知 Chrome 扩展 → Chrome fork `bridge-host.sh` → node bridge/main.js。

**注册位置：** `~/Library/Application Support/Google/Chrome/NativeMessagingHosts/ai.dokobot.bridge.json`
→ 指向 `/Users/Colin/.dokobot/bridge-host.sh`
→ `allowed_origins` 限定 `chrome-extension://dlbiigchkpmpijahmlofleeemiomaneo/`

## 冷启动 vs 热启动

| 状态 | 特征 | 首次调用耗时 |
|:---|:---|:---|
| **热启动** | socket 文件存在，bridge 进程存活 | < 5s |
| **冷启动** | bridge 进程已退出（`stdin ended` 后无人调用） | 10-30s（CLI → Chrome → fork → node init → 握手 → 页面加载） |

**bridge 退出条件：** 长时间无 `dokobot read --local` 调用后，Chrome 扩展的 stdio 连接断开 → `stdin ended, shutting down`。

**关键影响：** 如果距上次 dokobot 调用超过数小时，下一次调用就是冷启动，需要更多超时时间。

## 诊断流程

### 1. 快速状态检查

```bash
# bridge 是否存活
dokobot doko list

# 进程检查
ps aux | grep "bridge/main"

# socket 是否存在
ls -la ~/.dokobot/bridges/
```

### 2. 时间线重建（日志分析）

```bash
# bridge 启动/关闭记录
grep -E "Bridge process started|stdin ended" ~/.dokobot/bridge.log

# 最近活动
tail -30 ~/.dokobot/bridge.log
```

### 3. cron job 排障

```bash
# 查看 cron 运行日志
grep "cron_<job_id>" ~/.hermes/logs/agent.log | grep -E "dokobot|web_search|terminal"

# 确定 bridge 在 cron 触发时刻是否存活
# 对比 bridge.log 时间线与 cron 触发时间（北京时间 = UTC+8）
```

## 常见故障模式

### "No local bridge running"

**模式 A：bridge 冷启动超时**
- 特征：bridge 日志显示上次活动距今数小时，cron job 中超时设为 15s
- 修复：连通性检测改为 `--timeout 30` + 3 次重试

**模式 B：Chrome 未运行**
- 特征：`dokobot doko list` 返回空，bridge 日志无最近记录
- 修复：确保 Chrome 运行且 Dokobot 扩展已启用

**模式 C：扩展未连接**
- 特征：bridge 进程启动但 `dokobot doko list` 无设备
- 修复：检查 Chrome 扩展是否启用 Remote Control（本地模式可选）

### "Frame with ID 0 is showing error page"

**模式 D：Chrome 自身网络故障（bridge 存活但所有页面报错）**
- 特征：
  - `dokobot doko list` 正常返回设备（如 `pid 98424, Chrome, ext 0.3.1`）
  - `ps aux | grep "bridge/main"` 进程存活
  - socket 文件存在
  - **但所有 URL（包括 `https://example.com`）都返回 `Frame with ID 0 is showing error page`**
  - bridge 日志：`"success":false,"error":"Frame with ID 0 is showing error page"`
  - 日志时间线：之前正常读取记录，某个时刻后全部报错
- 可能原因：
  - Chrome 自身网络栈异常（代理/VPN 断连后 Chrome 未恢复）
  - Chrome 实例的渲染进程崩溃
  - 系统网络切换（WiFi→有线→热点）后 Chrome 未刷新连接
- 修复步骤：
  1. 手动在 Chrome 中打开 `https://example.com` 确认 Chrome 能否正常浏览
  2. 若不能 → 重启 Chrome（完全退出 `Cmd+Q`，不是关窗口）
  3. 检查系统代理设置：`scutil --proxy`
  4. 重启后执行 `dokobot read --local 'https://example.com'` 验证恢复
- **注意**：此模式下**不要反复重试 dokobot**——每次重试都浪费 ~30s 且一定失败。诊断优先，重试在后。

### "No local bridge running" — Chrome 崩溃后 bridge 未重启

**模式 E：Chrome Crashed → Bridge Dead（bridge 进程消失，socket 目录空，Chrome 正在运行）**

- 特征：
  - `dokobot doko list` 返回 `No available devices` 或空
  - `ls ~/.dokobot/bridges/` 目录为空（无 socket 文件）
  - `ps aux | grep "bridge/main"` 无结果
  - **但 Chrome 进程正在运行**（`ps aux | grep "Google Chrome"` 有大量进程）
  - `dokobot install-bridge` 显示 bridge 已安装但 `dokobot read --local` 仍报 `No local bridge running`
  - bridge 日志最后一行是 `stdin ended, shutting down`（数小时前），之后无任何记录——bridge 从未被重新启动
- 根因：
  - Chrome 进程崩溃（`exit_type: Crashed`，可在 Chrome Preferences 中确认：`grep "exit_type" ~/Library/Application\ Support/Google/Chrome/Default/Preferences`）
  - Chrome 崩溃后自动重启，Native Messaging Host 注册信息仍在，但 **Dokobot 扩展与 bridge 的 stdio 连接已断**
  - Chrome 重启时**不会自动重连 Native Messaging Host**——bridge 只在首次 `dokobot read --local` 触发或扩展显式重载时启动
  - 而 `dokobot read --local` 依赖 bridge 存活才能通过 Native Messaging 协议通知 Chrome → 形成**死锁**：bridge 死了需要 CLI 触发启动，但 CLI 需要 bridge 才能通知 Chrome 启动 bridge
- 诊断确认：
  ```bash
  # 1. 确认 bridge 已死
  dokobot doko list                           # → "No available devices"
  ls -la ~/.dokobot/bridges/                  # → 目录空
  tail -3 ~/.dokobot/bridge.log               # → 最后一行是 "stdin ended, shutting down"

  # 2. 确认 Chrome 崩溃过
  grep "exit_type" ~/Library/Application\ Support/Google/Chrome/Default/Preferences
  # → "exit_type":"Crashed"  ← 这就是根因

  # 3. 确认扩展仍安装
  ls ~/Library/Application\ Support/Google/Chrome/Default/Extensions/dlbiigchkpmpijahmlofleeemiomaneo/
  # → 0.3.1_0  ← 扩展文件还在，只是 bridge 连接断了
  ```
- 修复（选其一）：
  - **方案 A（推荐，无需重启 Chrome）：** 打开 Chrome 扩展页面触发扩展重载
    ```bash
    open -a "Google Chrome" "chrome://extensions/?id=dlbiigchkpmpijahmlofleeemiomaneo"
    ```
    等待 3-5 秒后验证：
    ```bash
    dokobot doko list
    # → 应返回设备信息
    ```
  - **方案 B：** 在 Chrome 地址栏手动输入 `chrome://extensions`，找到 Dokobot 扩展，点击刷新按钮 🔄
  - **方案 C：** 完全退出 Chrome（`Cmd+Q`）后重新打开
- ⚠️ **`dokobot install-bridge` 无法修复此模式**：bridge 文件未损坏，问题出在 Chrome 扩展的运行时状态，重装 bridge 无用。只有扩展重载/Chrome 重启能恢复连接。
- 验证恢复：
  ```bash
  dokobot read --local 'https://www.reddit.com/r/ImmigrationCanada/' --screens 1 --timeout 30
  # → 正常返回页面内容
  tail -3 ~/.dokobot/bridge.log
  # → 应看到 "Bridge process started" 紧随恢复操作之后
  ```

### 定时任务中的加固模式

在 cron prompt 中，连通性检测不要用单一 15s 调用，改用：

```bash
# 带重试 + 更长超时的连通性检测
DOKO_OK=0
for i in 1 2 3; do
  result=$(dokobot read --local 'https://www.reddit.com/r/ImmigrationCanada/' --screens 1 --timeout 30 2>&1)
  if [ -n "$result" ] && ! echo "$result" | grep -q "No local bridge" && ! echo "$result" | grep -q "Error"; then
    DOKO_OK=1
    break
  fi
  [ $i -lt 3 ] && sleep 5
done
[ $DOKO_OK -eq 1 ] && echo "DOKOBOT_READY" || echo "DOKOBOT_FAILED"
```

**为什么 30s + 3 次重试？** 冷启动全流程（CLI 通知 Chrome → fork bridge → node init → 扩展握手 → 页面加载）在无缓存的 macOS 环境下实测需要 10-25 秒。30s 给足够余量，3 次重试覆盖偶尔的 Chrome 响应延迟。

## 环境事实

- CLI 版本：`dokobot --version`（当前 2.11.0）
- Bridge 路径：`/opt/homebrew/lib/node_modules/@dokobot/cli/dist/cli/src/bridge/main.js`
- 启动脚本：`/Users/Colin/.dokobot/bridge-host.sh`
- Bridge 日志：`/Users/Colin/.dokobot/bridge.log`
- Socket 目录：`/Users/Colin/.dokobot/bridges/`
- 扩展版本：Chrome 扩展 0.3.x，设备 ID `1d6b1ae5-bed4-428f-9f57-4f45159c1018`
