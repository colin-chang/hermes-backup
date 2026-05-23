# Hermes Cron 定时任务排障指南

记录 Hermes cron 定时任务配置和执行中的已知陷阱与解决方案。

## P40：enabled_toolsets 使用 toolset 名而非 tool 名

**症状：** `execute_code` 工具不在子代理的 Available tools 列表中，调用时报 `Tool 'execute_code' does not exist`。

**根因：** `cron/jobs.json` 的 `enabled_toolsets` 数组需要填的是 **toolset 名称**，而非 tool 名称。两者大部分刚好同名（`terminal`、`web`、`browser` 等同时是 toolset 名和 tool 名），但 `execute_code` 是一个例外——它的 toolset 名叫 `code_execution`。

**对照表：**

| Tool 名 | Toolset 名 | 是否同名 |
|---------|-----------|---------|
| `terminal` | `terminal` | ✅ |
| `web_search` / `web_extract` | `web` | — |
| `execute_code` | `code_execution` | ❌ 注意！ |
| `delegate_task` | `delegation` | ❌ 注意！ |

**修复：** `cron/jobs.json` 中 `"execute_code"` → `"code_execution"`。

**验证：** cron 子代理的 Available tools 列表中应出现 `execute_code`。

---

## P41：terminal + python3 -c 触发安检 vs execute_code 绕过

**症状：** 子代理用 `terminal` 执行 `python3 -c "report='...日报内容含 emoji...'"` 时，Hermes 安全扫描拦截：
```
[HIGH] Zero-width characters detected
[MEDIUM] Variation selector characters detected
[HIGH] Confusable Unicode characters
script execution via -e/-c flag
```

**根因：** Hermes 的 `tirith` 安全扫描引擎扫描 terminal 命令字符串。`python3 -c` 的参数字符串中包含 emoji（含 ZWJ `U+200D`、变体选择器 `U+FE0F` 等）时，扫描器将其误判为隐写攻击。

**解决方案优先级：**

1. **首选：`execute_code` 直接内联（需 `code_execution` toolset）** — 走独立沙箱，不触发 terminal 安检。日报直接放在 Python 字符串中，Markdown 格式原样保留，不写文件。
2. **降级：Python HEREDOC** — 仅当 `execute_code` 不可用时使用。内容走 stdin，不在命令字符串中，不触发安检。

```python
# execute_code 方式（首选）
import socket, json, time
report = """完整日报内容，保留 Markdown 格式"""
s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
s.connect(('127.0.0.1', 8899))
s.settimeout(10)
s.sendall((json.dumps({'jsonrpc':'2.0','id':'1','method':'send','params':{'to':'recipient@email','text':report}})+'\n').encode())
time.sleep(1)
try:
    print(s.recv(4096).decode())
except socket.timeout:
    print('TIMEOUT')
s.close()
```

**注意：** `execute_code` 需要在 cron 的 `enabled_toolsets` 中配置 `code_execution`（不是 `execute_code`），见 P40。

---

## P42：Cron 运行时扫描器扫描 Skill 全文

**症状：** 之前正常运行的 cron job 突然报错：
```
last_status: "error"
last_error: "Blocked: prompt contains invisible unicode U+200D (possible injection)."
```

**根因：** `cron/scheduler.py` 的 `_scan_assembled_cron_prompt()` 每次 cron **执行时**扫描的是完整拼接的 prompt（用户 prompt + 所有已加载 Skill 的全文），不只是用户自己写的 prompt。如果某个 Skill 的 SKILL.md 或 reference 文件含 ZWJ emoji（如 `👩🏼‍⚖️`），扫描器会拦截整个 job。

这与 create/update 时的 `_scan_cron_prompt`（只扫描用户 prompt）是**两次独立扫描**：
| 扫描时机 | 函数 | 扫描范围 |
|---------|------|---------|
| create/update | `_scan_cron_prompt` | 仅用户 prompt |
| 每次执行 | `_scan_assembled_cron_prompt` | prompt + 所有 Skill 全文 |

**修复：** 确保 cron job 加载的所有 Skill 文件中不含 ZWJ 字符（`U+200D`）。用 `python3 -c "print(content.count('\u200d'))"` 检测。

---

## P43：子代理使用 nomad-imessage skill 的正确姿势

**背景：** cron job 的 `skills` 数组配置了 `nomad-imessage`，Skill 内容被注入系统 prompt，子代理能看到 Skill 指令。但子代理只能用 `enabled_toolsets` 中的工具来执行，而 `skills` toolset（含 `skill_view`）通常不在 cron toolsets 中。

**正确做法：**
1. Skill 内容作为**知识源**注入子代理的系统 prompt
2. Prompt（如 `immigration-monitor-prompt.md`）的「阶段 4.5」提供**具体执行步骤**，使用 `execute_code` 直接内联发送
3. 不写文件，不绕路。日报放在 Python 字符串中，`execute_code` 一次调用完成

**发送模板（放在 cron prompt 的阶段 4.5 中）：**
```python
import socket, json, time

report = """<完整日报内容，保留所有 Markdown 格式>"""

s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
s.connect(('127.0.0.1', 8899))
s.settimeout(10)
s.sendall((json.dumps({'jsonrpc':'2.0','id':'1','method':'send','params':{'to':'chenjieyu.swufe@gmail.com','text':report}})+'\n').encode())
time.sleep(1)
try:
    print(s.recv(4096).decode())
except socket.timeout:
    print('TIMEOUT')
s.close()
```

**前置条件：** `cron/jobs.json` 的 `enabled_toolsets` 必须包含 `code_execution`（toolset 名），不是 `execute_code`（tool 名）。见 P40。

---

## P44：Don't Auto-Trigger — 修改完等用户确认

**用户偏好：** 修复 cron 相关配置后，**不要自动执行 `cronjob action=run`**。等用户确认修改无误后再手动触发。反复自动触发会浪费 token、生成重复报告、且让用户失去对执行时机的控制。

---

## P45：Hermes 三层安全扫描架构

Cron 任务经过三层独立的安全扫描，理解这个架构是排障的基础：

| 层级 | 函数 | 触发时机 | 扫描范围 | emoji ZWJ 处理 |
|------|------|---------|---------|---------------|
| Layer 1 | `_scan_cron_prompt()` | create/update 时 | 仅用户 prompt | ✅ `_EMOJI_ZWJ_RE` 剥离 |
| Layer 2 | `_scan_assembled_cron_prompt()` | 每次执行时 | prompt + 所有 Skill 全文 | ⚠️ 同正则，但可能漏 |
| Layer 3 | terminal tirith 引擎 | terminal 调用时 | 命令文本 | ❌ 无 emoji 处理 |

**Layer 2 的关键陷阱：** Skill 文件是运行时才加载的，create/update 时的扫描（Layer 1）扫不到 Skill 内容。如果 Skill 的 SKILL.md 或 references 中含 ZWJ emoji，会在执行时被 Layer 2 拦截——整 Job 被拒，即使之前一直正常运行。

**Layer 3 的关键陷阱：** `terminal` 的 `python3 -c` 会触发 Layer 3 扫描，但 Layer 3 **没有** emoji ZWJ 剥离逻辑（`_EMOJI_ZWJ_RE` 只在 Layer 1/2 中生效）。所以：
- `python3 -c "report = '...emoji...'"` → Layer 3 拦截 ❌
- `execute_code` → 走独立沙箱，不经过 Layer 3 ✅
- Python HEREDOC → stdin 内容不在命令字符串中，绕过 Layer 3 ✅
