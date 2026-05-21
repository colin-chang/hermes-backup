# Cron Job 中嵌入 iMessage 侧送

> 适用场景：Cron 定时任务生成报告后，除 deliver 到网关平台外，还需推送到 iMessage。

## 原理

iMessage 不是消息网关平台（无 `deliver` 字段支持），必须在 prompt 中嵌入发送步骤。使用 imsg Bridge Daemon（JSON-RPC over TCP），Cron 代理通过 Python socket 发送 JSON-RPC 到 `localhost:8899`。

## 执行流程

```
Cron 触发
  ↓
阶段 1-N：[完全静默] 数据抓取 → 过滤 → 分析 → 组装报告
  ↓
阶段 N+1：[工具调用，非文字输出]
  ├─ 检测 bridge 是否运行（tmux has-session -t imsg-bridge）
  ├─ ✅ 已运行 → write_file 保存报告 → execute_code 发送（首选，不触发审批）
  ├─ ⚠️ 已运行但 execute_code 不可用 → terminal 从文件读取发送（降级）
  ├─ ❌ 未运行 → **不尝试启动**（Hermes foreground terminal 拒绝），跳过 iMessage 侧送
  └─ 根据返回的 guid 判断成功/失败（若跳过则标注 ⚠️）
  ↓
最终文字输出：完整报告（含 ⚠️ 标记，如果有推送异常）
  ↓
Cron deliver → Mattermost / Discord 等网关平台
```

**关键约束**：所有工具调用发生在最终文字输出**之前**，不受「第一条文字输出」规则限制。

> ⚠️ **Hermes Cron 环境的 bridge 启动限制**：`imsg-bridge.command` 使用 `tmux new-session -d`（后台模式），Hermes foreground terminal 会拒绝执行。**在 cron prompt 中，只检测 bridge 状态，不要尝试启动。** bridge 未运行 → 跳过 iMessage 侧送，标注 `⚠️ iMessage 推送跳过：bridge 未运行`。推荐将 bridge 部署为 LaunchAgent（系统守护进程），保证 cron 执行时始终可用。

## ⚠️ Cron 前置配置（必须）

Cron job 的 `enabled_toolsets` **必须包含 `execute_code`**。若缺少，子代理只能用 `terminal` 的 `python3 -c` 发送，会触发：
1. Hermes 审批弹窗（`script execution via -e/-c flag`）→ 无人值守超时
2. 安全扫描误判 Unicode emoji（ZWJ、变体选择器 VS16、肤色修饰符）→ 标记为 `[HIGH] Zero-width characters` → 拦截

```json
"enabled_toolsets": ["terminal", "web", "browser", "vision", "memory", "session_search", "execute_code"]
```

## 🚨 发送策略（Cron 环境，严格按此顺序）

### Step 1：write_file 保存报告（必须）

**必须先保存到文件，严禁在 terminal 命令中内联含 emoji 的报告全文。**
emoji（📋🗓️🔴🟡👩🏼‍⚖️📰✅📊🕐 等）包含 ZWJ 零宽连接符、变体选择器、肤色修饰符，会被 Hermes 安全扫描误判为零宽攻击字符。

```
write_file(path='/tmp/imessage-daily-report.txt', content='<完整报告内容>')
```

### Step 2：execute_code 发送（首选，不触发审批弹窗）

```python
import socket, json, time
with open('/tmp/imessage-daily-report.txt') as f:
    report = f.read()
s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
s.connect(('127.0.0.1', 8899))
s.settimeout(10)
payload = json.dumps({'jsonrpc':'2.0','id':'1','method':'send','params':{'to':'recipient@example.com','text':report}}) + '\n'
s.sendall(payload.encode())
time.sleep(1)
try:
    resp = s.recv(4096).decode()
    print(resp)
except socket.timeout:
    print('TIMEOUT — 消息通常已发出，严禁重试')
s.close()
```

### Step 3（降级）：terminal 从文件读取发送

> ⚠️ 仅当 `execute_code` 不可用时使用。`terminal` 的 `python3 -c` 可能触发审批弹窗或安全扫描。

```bash
# 检测 bridge 是否运行（不尝试启动）
if ! tmux has-session -t imsg-bridge 2>/dev/null; then
    echo "BRIDGE_DOWN"
    exit 0
fi

# 从文件读取发送（严禁在 python3 -c 中直接内联含 emoji 的报告全文）
python3 -c "
import socket, json, time
with open('/tmp/imessage-daily-report.txt') as f:
    report = f.read()
s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
s.connect(('127.0.0.1', 8899))
s.settimeout(10)
payload = json.dumps({'jsonrpc':'2.0','id':'1','method':'send','params':{'to':'recipient@example.com','text':report}}) + '\n'
s.sendall(payload.encode())
time.sleep(1)
try:
    print(s.recv(4096).decode())
except socket.timeout:
    print('TIMEOUT')
s.close()
"
```

## 成功/失败判断

```
✅ {"result":{"ok":true,"guid":"8DF..."}} → 确认送达，继续
⚠️ {"result":{"ok":true}} 无 guid       → 已提交未确认，不重试
⚠️ TIMEOUT                               → 消息通常已发出，严禁重试
❌ {"error":{...}} 或连接拒绝             → 失败，不重试，报告中标注
🚫 绝对禁止：因空响应/无 guid 而重试      → 重试 = 重复发送
```

## 踩坑记录

| 坑 | 现象 | 解法 |
|---|------|------|
| macOS `nc` 丢响应 | `echo \| nc` 返回空，exit 0，但消息已发 | **严禁用 nc**，用 Python socket 收响应 |
| nc 空响应误判重试 | 空响应 → 以为失败 → 重试 → 对方收 N 条 | 空响应 = 消息大概率已发，禁止重试 |
| osascript 假阳性 | 永远返回 exit 0，无法判断送达 | **已弃用** |
| bridge 未启动 | 连接拒绝 | 前置检测 + 部署 LaunchAgent |
| open 异步 | bridge 还没准备好就发消息 | `sleep 2` |
| Hermes 拒绝启动 bridge | `"Foreground command uses '&' backgrounding"`（`tmux -d` 被拦截） | 部署 LaunchAgent；Cron prompt 中检测到 bridge 未运行 → 跳过 iMessage 并标注 |
| **终端内联 emoji 触发安全扫描** | `terminal` 的 `python3 -c "report='📋🗓️...'"` → `[HIGH] Zero-width characters` + `[HIGH] Confusable Unicode` → 审批弹窗超时 | `write_file` 保存到文件 + `execute_code` 从文件读取发送；Cron 的 `enabled_toolsets` 必须包含 `execute_code` |
| **Cron 缺 execute_code** | 子代理只能用 terminal → `python3 -c` 触发审批弹窗 → 无人值守超时 → iMessage 静默失败 | Cron `enabled_toolsets` 必须包含 `execute_code` |
| shell 转义 | 报告中 `$`、反引号被展开 | Python `json.dumps()` 造 payload |

## ⛔ 已弃用：AppleScript heredoc 方案

弃用原因：`osascript send` 永远返回 exit 0，无法区分成功与失败，导致代理反复重试。

## 事故记录

### 2026-05-21：emoji 触发安全扫描 + 缺 execute_code

加拿大移民日报 cron（ID: `2e081401e374`）的 iMessage 推送连续多日静默失败：

1. **缺 `execute_code` toolset**：Cron `enabled_toolsets` 为 `["terminal","web","browser","vision","memory","session_search"]`，无 `execute_code`
2. **terminal 内联 emoji 被拦截**：子代理用 `python3 -c` 将含 📋🗓️🔴🟡👩🏼‍⚖️ 等 emoji 的完整日报内联在命令中
3. **安全扫描误判**：emoji 的 ZWJ 零宽连接符 + 变体选择器 VS16 + 肤色修饰符 → `[HIGH] Zero-width characters` + `[HIGH] Confusable Unicode`
4. **审批弹窗超时**：`python3 -c` 触发 `script execution via -e/-c flag` 审批 → 无人值守超时 → `exit_code: -1`
5. **子代理放弃**：收到失败后直接输出报告到 Mattermost，跳过 iMessage 推送

**修复**：
- Cron `enabled_toolsets` 加入 `execute_code`
- Prompt 阶段 4.5 重写：`write_file` 保存 → `execute_code` 从文件发送 → terminal 降级
- 本文件更新：execute_code 提升为首选方式，添加 Unicode 安全扫描踩坑
