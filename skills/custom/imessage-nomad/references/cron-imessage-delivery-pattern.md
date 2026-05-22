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

Cron job 的 `enabled_toolsets` **必须包含 `code_execution`**（toolset 名，不是 tool 名 `execute_code`）。若缺少，子代理只能用 `terminal` 的 `python3 -c` 发送，会触发：
1. Hermes 审批弹窗（`script execution via -e/-c flag`）→ 无人值守超时
2. 安全扫描误判 Unicode emoji（ZWJ、变体选择器 VS16、肤色修饰符）→ 标记为 `[HIGH] Zero-width characters` → 拦截

```json
"enabled_toolsets": ["terminal", "web", "browser", "vision", "memory", "session_search", "code_execution"]
```

## 🚨 发送策略（Cron 环境，严格按此顺序）

### ✅ execute_code 可用（已修复）

Cron job 的 `enabled_toolsets` 必须填 **toolset 名 `code_execution`**（非 tool 名 `execute_code`）。`terminal`、`web` 等碰巧同名所以之前能工作。已修复：`cron/jobs.json` 中 `"execute_code"` → `"code_execution"`。

### Step 1（首选）：execute_code 直接内联发送

> `execute_code` 不触发审批弹窗。日报直接放在 Python 字符串中，**不走文件中转**，Markdown 格式原样保留。

```python
import socket, json, time

report = """<完整报告内容，直接内联，保留所有 Markdown 格式>"""

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

### Step 2（当前实际生效）：terminal 分两步发送

> ⚠️ **必须拆成两次独立的 `terminal` 调用**，严禁合并。合并时 terminal 工具会误报 `Foreground command uses '&' backgrounding`。

**2a. 先写文件（HEREDOC）：**
```bash
cat > /tmp/imessage-daily-report.txt << 'REPORT_EOF'
<完整报告内容>
REPORT_EOF
```

**2b. 再从文件读出发送：**
```bash
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

> ⚠️ **不要执行 `open imsg-bridge.command` 或 `tmux has-session`**——bridge 已常驻运行（LaunchAgent），启动命令含后台符号会被 terminal 工具拒绝。若 bridge 意外未运行 → 2b 的 Python socket 会报 `ConnectionRefusedError` → 正常走失败处理。

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
| **终端内联 emoji 触发安全扫描** | `terminal` 的 `python3 -c` 中含 ZWJ emoji（如女性法官组合emoji）→ `[HIGH] Zero-width characters` → 拦截。`execute_code` 不受此影响 | **源头清 ZWJ**：报告模板用不含 ZWJ 的基础 emoji（`⚖️` 替代 `女性法官组合emoji`）。`execute_code` 直接内联发送（不触发审批弹窗），保留 Markdown 格式。详见 `role-canada-affairs` → `references/cron-emoji-failure-postmortem.md` |
| **execute_code 配置问题已解决** | Cron `enabled_toolsets` 写入 tool 名 `execute_code`，应写 toolset 名 `code_execution`。`terminal`/`web`/`browser` 碰巧同名所以能工作 | `cron/jobs.json` 中 `"execute_code"` → `"code_execution"` |
| **terminal 合并命令误报后台运行** | HEREDOC + python3 -c 写在同一次 `terminal` 调用中 → `Foreground command uses '&' backgrounding` | **拆成两次独立 terminal 调用**：第一次写文件（HEREDOC），第二次 python3 -c 发送。严禁合并 |
| **Cron 缺 code_execution toolset** | 子代理只能用 terminal → `python3 -c` 触发审批弹窗 → 无人值守超时 → iMessage 静默失败 | Cron `enabled_toolsets` 必须包含 `code_execution` |
| **Skill 文档含 ZWJ 被 runtime 扫描拦截** | Cron 执行时 `_scan_assembled_cron_prompt()` 扫描 prompt + 所有 Skill 全文 → Skill 文档中 `女性法官组合emoji` ZWJ 被拦截 → 整 Job 被拒 | Skill 文档严禁出现含 ZWJ 的组合 emoji |
| shell 转义 | 报告中 `$`、反引号被展开 | Python `json.dumps()` 造 payload |

## ⛔ 已弃用：AppleScript heredoc 方案

弃用原因：`osascript send` 永远返回 exit 0，无法区分成功与失败，导致代理反复重试。

## 事故记录

### 2026-05-21：emoji 触发安全扫描 + 缺 code_execution toolset

加拿大移民日报 cron（ID: `2e081401e374`）的 iMessage 推送连续多日静默失败：

1. **缺 `code_execution` toolset**：Cron `enabled_toolsets` 为 `["terminal","web","browser","vision","memory","session_search"]`，无 `code_execution`
2. **terminal 内联 emoji 被拦截**：子代理用 `python3 -c` 将含 📋🗓️🔴🟡 等 emoji（及含 ZWJ 的组合 emoji）的完整日报内联在命令中
3. **安全扫描误判**：emoji 的 ZWJ 零宽连接符 + 变体选择器 VS16 + 肤色修饰符 → `[HIGH] Zero-width characters` + `[HIGH] Confusable Unicode`
4. **审批弹窗超时**：`python3 -c` 触发 `script execution via -e/-c flag` 审批 → 无人值守超时 → `exit_code: -1`
5. **子代理放弃**：收到失败后直接输出报告到 Mattermost，跳过 iMessage 推送

**修复（2026-05-22 最终）**：
- Cron `enabled_toolsets` 加入 `code_execution`（toolset 名，不是 tool 名 `execute_code`）
- Prompt 阶段 4.5 简化为 `execute_code` 直接内联发送
- 源头清 ZWJ：女性法官组合emoji → `⚖️`

**诊断发现（2026-05-22）：两套扫描器，不同代码路径**

Hermes 源码中存在两套独立的安全扫描器，保护范围不同：

| 扫描器 | 位置 | emoji ZWJ 正则 | 触发场景 |
|--------|------|---------------|---------|
| Cron prompt 扫描 | `tools/cronjob_tools.py` `_scan_cron_prompt()` | ✅ 有 `_EMOJI_ZWJ_RE`（L73-80），匹配 emoji 之间的 ZWJ 并剥离 | 仅扫描 cron job 的 prompt 文本 |
| Terminal 工具扫描 | terminal 工具内部（tirith 引擎） | ❌ 无 | 扫描所有 `terminal` 调用的命令文本 |

`cronjob_tools.py` 的 `_EMOJI_ZWJ_RE` 正则逻辑：
```python
_EMOJI_ZWJ_RE = re.compile(
    r'(?<=[\U0001F300-\U0001FAFF\u2600-\u27BF\uFE00-\uFE0F])'
    r'\u200d'
    r'(?=[\U0001F300-\U0001FAFF\u2600-\u27BF\uFE00-\uFE0F])'
)
# 仅剥离 emoji 字符之间的 ZWJ，非 emoji 上下文的 ZWJ 仍保留以被拦截
```

**关键结论**：即使 cron prompt 文本通过了 `_scan_cron_prompt()` 的安全检查，子代理在运行时通过 `terminal` 工具执行的命令仍会被 terminal 的独立安全扫描器拦截。正则修复 cron prompt 端无法解决 terminal 端的误判——**必须用 `execute_code` 替代 `terminal` 发送 iMessage**（`execute_code` 走独立沙箱，不触发 terminal 安检）。

**诊断发现（2026-05-22）：第三套扫描器 — 运行时组装扫描**

除上述两套扫描器外，还存在第三套：`cron/scheduler.py` 的 `_scan_assembled_cron_prompt()`（L999-1021）。该扫描器在 cron **每次执行时**运行，扫描的是 **完整组装后的 prompt**（用户 prompt + 所有加载的 Skill 全文拼接），而非仅用户 prompt。

这意味着 **Skill 文档中的 ZWJ emoji 也会被扫描并拦截**。本次 session 中，`imessage-nomad/SKILL.md` 和 `cron-imessage-delivery-pattern.md` 的事故记录行含 `女性法官组合emoji`（ZWJ），虽然 `_EMOJI_ZWJ_RE` 理论上应剥离它，但实际未剥净导致 2026-05-22 17:00 cron 执行被 `_scan_assembled_cron_prompt` 拦截。

**三套扫描器总结**：

| 扫描器 | 时机 | 扫描范围 | emoji ZWJ 处理 |
|--------|------|---------|---------------|
| `_scan_cron_prompt()` | create/update | 用户 prompt | ✅ `_EMOJI_ZWJ_RE` 剥离 |
| `_scan_assembled_cron_prompt()` | **每次执行** | prompt + **所有 Skill 全文** | ✅ 同上（但不一定 100% 有效） |
| Terminal tirith 引擎 | terminal 调用时 | 命令文本 | ❌ 无 |

**教训**：Skill 文档中**严禁出现含 ZWJ 的组合 emoji**（如女性法官、家庭等组合emoji），用文字描述替代。即便 emoji ZWJ 正则理论上能剥离，运行时组装后的复杂上下文中可能失效。

### 2026-05-22：toolset 命名 bug — execute_code vs code_execution

在上次修复基础上继续调试，发现根因：

1. **toolset 命名不匹配**：Cron `enabled_toolsets` 写了 tool 名 `execute_code`，但应写 toolset 名 `code_execution`。`terminal`/`web`/`browser` 等碰巧同名所以一直能工作，`execute_code` 是唯一例外。

2. **terminal 合并命令被误判后台运行**：HEREDOC 写文件 + `python3 -c` 发送写在同一 `terminal` 调用中时，Hermes terminal 工具误报 `Foreground command uses '&' backgrounding`，拒绝执行。

3. **报告模板 ZWJ 残留**：Skill 文档的 ZWJ 已清理，但 `immigration-monitor-prompt.md` 报告模板阶段 3 的女性法官组合emoji未清理，导致生成的报告中仍含 ZWJ。

**最终方案**：
- `cron/jobs.json`：`"execute_code"` → `"code_execution"`
- Prompt 阶段 4.5：`execute_code` 直接内联发送，不写文件，Markdown 原样保留
- 源头清 ZWJ：模板 女性法官组合emoji → `⚖️`
- 报告模板 女性法官组合emoji → `⚖️`（全 prompt 文件 0 ZWJ）
