# Cron Job 中嵌入 iMessage 侧送

> 适用场景：Cron 定时任务生成报告后，除 deliver 到网关平台外，还需推送到 iMessage。

## 原理

iMessage 不是 消息网关平台（无 `deliver` 字段支持），必须在 prompt 中嵌入发送步骤。使用 imsg Bridge Daemon（JSON-RPC over TCP），Cron 代理通过 Python socket 发送 JSON-RPC 到 `localhost:8899`。

## 执行流程

```
Cron 触发
  ↓
阶段 1-N：[完全静默] 数据抓取 → 过滤 → 分析 → 组装报告
  ↓
阶段 N+1：[terminal 调用，非文字输出]
  ├─ 检测 bridge 是否运行（tmux has-session -t imsg-bridge）
  ├─ ✅ 已运行 → 写入临时文件 → Python socket 发 JSON-RPC
  ├─ ❌ 未运行 → **不尝试启动**（Hermes foreground terminal 拒绝），跳过 iMessage 侧送
  └─ 根据返回的 guid 判断成功/失败（若跳过则标注 ⚠️）
  ↓
最终文字输出：完整报告（含 ⚠️ 标记，如果有推送异常）
  ↓
Cron deliver → Mattermost / Discord 等网关平台
```

**关键约束**：所有 `terminal` 调用发生在最终文字输出**之前**，不受「第一条文字输出」规则限制。

> ⚠️ **Hermes Cron 环境的 bridge 启动限制**：`imsg-bridge.command` 使用 `tmux new-session -d`（后台模式），Hermes foreground terminal 会拒绝执行。**在 cron prompt 中，只检测 bridge 状态，不要尝试启动。** bridge 未运行 → 跳过 iMessage 侧送，标注 `⚠️ iMessage 推送跳过：bridge 未运行`。推荐将 bridge 部署为 LaunchAgent（系统守护进程），保证 cron 执行时始终可用。

## 模板代码

> ⚠️ **严禁用 `echo '...' | nc`**：macOS nc 发完即关连接，JSON-RPC 响应被丢弃，导致"空响应→误判失败→重试→重复发送"的循环。

```bash
# Step 0: 检测 bridge 是否运行（不尝试启动——Hermes foreground terminal 会拒绝 .command）
if ! tmux has-session -t imsg-bridge 2>/dev/null; then
    echo "BRIDGE_DOWN"
    exit 0
fi

# Step 1: 写入临时文件
cat > /tmp/report.txt << 'REPORT_EOF'
<完整报告内容>
REPORT_EOF

# Step 2: Python socket 发送并接收响应（必须收响应以判断发送结果）
python3 -c "
import socket, json, time
s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
s.connect(('127.0.0.1', 8899))
s.settimeout(10)
with open('/tmp/report.txt') as f:
    text = f.read()
payload = json.dumps({'jsonrpc':'2.0','id':'1','method':'send','params':{'to':'recipient@example.com','text':text}}) + '\n'
s.sendall(payload.encode())
time.sleep(1)
try:
    resp = s.recv(4096).decode()
    print(resp)
except socket.timeout:
    print('TIMEOUT')
s.close()
"
```

## 成功/失败判断

```
✅ {"result":{"ok":true,"guid":"8DF..."}} → 成功，继续
⚠️ {"result":{"ok":true}} 无 guid       → 已提交未确认，不重试
❌ {"error":{...}} 或 nc 超时            → 失败，不重试
🚫 绝对禁止：因无 guid 而重试             → 重试 = 重复发送
```

## 踩坑记录

| 坑 | 现象 | 解法 |
|---|------|------|
| macOS `nc` 丢响应 | `echo \| nc` 返回空，exit 0，但消息已发 | **严禁用 nc**，用 Python socket 收响应 |
| nc 空响应误判重试 | 空响应 → 以为失败 → 重试 → 对方收 N 条 | 空响应 = 消息大概率已发，禁止重试 |
| osascript 假阳性 | 永远返回 exit 0，无法判断送达 | **已弃用** |
| bridge 未启动 | 连接拒绝 | 前置检测 + `open` |
| open 异步 | bridge 还没准备好就发消息 | `sleep 2` |
| Hermes 拒绝启动 bridge | `"Foreground command uses '&' backgrounding"`（`tmux -d` 被拦截） | 部署 LaunchAgent（见下方）或手动预先启动 bridge；Cron prompt 中检测到 bridge 未运行 → 跳过 iMessage 侧送并标注失败 |
| shell 转义 | 报告中 `$`、反引号被展开 | Python `json.dumps()` 造 payload |

## ⛔ 已弃用：AppleScript heredoc 方案

弃用原因：`osascript send` 永远返回 exit 0，无法区分成功与失败，导致代理反复重试。
