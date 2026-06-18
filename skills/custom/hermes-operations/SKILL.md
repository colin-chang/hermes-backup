---
name: hermes-operations
description: Hermes Agent 运维排障 — 日志分析、Gateway 启动问题、MCP 服务器故障、macOS launchd 异常、Cron 任务排障
version: 1.2.0
category: custom
---

# Hermes Agent 运维排障

当用户报告 Hermes 运行异常（Gateway 启动失败、MCP 服务器报错、日志告警等）时使用。

## 触发条件

- "Hermes 报错" / "Gateway 启动失败" / "启动报错"
- "分析 Hermes 日志" / "检查错误日志"
- MCP 服务器连接失败
- launchd 相关错误 ("Bootstrap failed: 5" / "Could not find service")
- Gateway 状态异常
- Cron 任务失败 / "定时任务是否存在问题" / "cron job error"
- "Desktop 更新失败" / "Rebuilding the desktop app failed" / "更新报错"
- "消息发错频道" / "串台" / "回复出现在了错误的 thread 里"

## 诊断工作流

### 第一步：全域日志扫描

Hermes 日志分布在 6 个文件中，必须全部检查：

```bash
find ~/.hermes/logs/ -name "*.log" -type f | sort
```

| 日志文件 | 级别 | 内容 |
|----------|------|------|
| `gateway.log` | INFO+ | Gateway 启动/运行/平台连接 |
| `gateway.error.log` | WARNING+ | Gateway 级错误（精简版） |
| `errors.log` | WARNING+ | 全局错误（包含 Gateway + Agent） |
| `agent.log` | INFO+ | 插件加载、API 调用、工具执行、会话 |
| `mcp-stderr.log` | STDERR | MCP 服务器的 stderr 输出（**不看这个会漏掉 MCP 崩溃根因**） |
| `gateway-exit-diag.log` | JSON | Gateway 退出诊断（argv/platform/pid） |
| `bootstrap-installer.log` | INFO+ | 安装/更新流程日志（update/rebuild 阶段，**Desktop 更新失败时优先查此文件**） |

**⚠️ 关键陷阱**：`gateway.error.log` 只记录 "连接失败" 但不包含具体错误原因。MCP 崩溃的根因在 `mcp-stderr.log` 中（进程 stderr），必须同时检查才能定位。

### 第二步：交叉关联

1. 从 `gateway.error.log` / `errors.log` 找到错误时间和组件
2. 去 `mcp-stderr.log` 看对应时间段的 stderr 输出
3. 去 `agent.log` 看完整上下文（插件加载顺序、注册结果）

### 第三步：按错误类型分流

见下方「常见问题」章节。

### 参考资料

- `references/macos-launchd-bootstrap-error5.md` — macOS launchd error 5 完整错误信息、环境背景、已验证修复
- `references/mcp-nodejs-abi-mismatch.md` — MCP 服务器 Node.js ABI 不匹配的诊断清单与修复方案
- `references/desktop-rebuild-npm-path.md` — Desktop 更新 rebuild 失败的 npm 路径与 lock 文件问题
- `references/cross-thread-routing-diagnosis.md` — Mattermost 跨线程串台（reply_to 被覆盖）的诊断流程
- `references/security-scanner-credential-injection.md` — 绕过安全扫描器注入 GitHub token / API key 的模式

## 常见问题

### macOS launchd Bootstrap failed: 5

**症状：**
```
Could not find service "ai.hermes.gateway" in domain for uid: 501
↻ launchd job was unloaded; reloading service definition
Bootstrap failed: 5: Input/output error
⚠ launchd cannot manage the gateway on this macOS version (launchctl exit 5).
✓ Started gateway as a background process instead
```

**根因：** macOS `launchctl bootstrap` 偶发状态不一致（非 Hermes bug）。常见触发场景：短时间内重复 stop/start、系统刚唤醒、plist 刚写入尚未被 launchd 识别。

**处理：** Hermes CLI 已内置降级逻辑——launchd 失败后自动切为后台进程模式。Gateway **实际上已启动成功**，只是不走 launchd 管理（不会开机自启、不会崩溃自动重启）。

**修复：** 等 5-10 秒后重新执行 `hermes gateway start`，第二次通常能成功注册到 launchd。验证：
```bash
hermes gateway status
# 应看到 "✓ Gateway service is loaded"
```

### MCP 服务器 Node.js 原生模块 ABI 不匹配

**症状：**
```
WARNING tools.mcp_tool: MCP server 'xxx' initial connection failed (attempt X/3)
Failed to connect to MCP server 'xxx' (command=xxx): Connection closed
```
在 `mcp-stderr.log` 中看到：
```
Error: The module '.../better_sqlite3.node' was compiled against a different Node.js version
NODE_MODULE_VERSION 147. This version of Node.js requires NODE_MODULE_VERSION 127.
```

**根因：** 环境中存在两个 Node.js 版本，原生模块（`.node` 文件）编译时用的版本 ≠ 运行时用的版本。

**典型场景** — macOS 上 Hermes Desktop 安装了捆绑的 Node.js（`~/.hermes/node/bin/node` → 符号链接到 `~/.local/bin/node`），用户又通过 Homebrew 装了另一个 Node.js。当 `npm install -g` 用 Homebrew 的 node 编译原生模块，但 Hermes 启动 MCP 时 PATH 上先命中捆绑的 node，版本不匹配导致崩溃。

**诊断步骤：**
```bash
# 1. 确认当前 PATH 上的 Node
which node && node --version

# 2. 检查 Hermes 捆绑的 Node
~/.hermes/node/bin/node --version

# 3. 检查 Homebrew 的 Node
/opt/homebrew/bin/node --version 2>/dev/null

# 4. 检查 Hermes 的符号链接（如果存在）
ls -la ~/.local/bin/node ~/.local/bin/npm ~/.local/bin/npx 2>/dev/null

# 5. 确认 MCP 服务器的原生模块编译目标（看 mcp-stderr.log 中的 NODE_MODULE_VERSION）
```

**修复（三选一，按推荐顺序）：**

**方案 A：用当前 PATH 的 Node 重建原生模块（不动环境，推荐）**
```bash
npm rebuild -g <mcp-package-name>
# 例如：npm rebuild -g @tobilu/qmd
hermes gateway restart
```

**方案 B：移除 Hermes 捆绑的 Node 符号链接，统一使用 Homebrew Node**
```bash
rm ~/.local/bin/node ~/.local/bin/npm ~/.local/bin/npx
hash -r
node --version          # 确认指向 Homebrew 版本
npm rebuild -g <mcp-package-name>
hermes gateway restart
```

> **安全性**：Hermes Desktop（Electron 应用）自带运行时，不依赖 `~/.local/bin/node`。这些符号链接仅用于 CLI/MCP 场景，移除不影响 Desktop 应用。

**方案 C：禁用有问题的 MCP 服务器（不需要该功能时）**
```bash
hermes mcp remove <server-name>
```

### Desktop 更新 rebuild 失败

**症状：**
```
Rebuilding the desktop app failed (exit Some(1)).
The update was applied but the app could not be rebuilt;
run `hermes desktop` from a terminal to see the error.
```

在 `bootstrap-installer.log` 的 `stage=rebuild` 中看到：
```
Desktop GUI requires Node.js/npm, but npm was not found on PATH.
Install Node.js, then run:  hermes gui
```

**根因：** macOS GUI 进程从 `launchd` 继承环境变量，不会加载 `~/.zshrc`。Node.js 通过 Homebrew 装在 `/opt/homebrew/bin/` 时，GUI 进程的默认 PATH 不含该目录。update 阶段（Python/pip）成功，rebuild 阶段（Electron/npm）失败。

**关键原则：** 用 `launchctl setenv` 注入 PATH，**不要重新创建** `~/.local/bin/node` 符号链接。如果之前因 MCP ABI 不匹配移除了这些符号链接，重新创建会导致 MCP 问题复现。

**修复：**

```bash
# 1. 设置 GUI 可见的 PATH
launchctl setenv PATH "/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

# 2. 持久化（每次开终端自动 re-set）
echo '
launchctl setenv PATH "/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
' >> ~/.zshrc

# 3. 如果 lock 文件版本不匹配（另见 references/desktop-rebuild-npm-path.md）
cd ~/.hermes/hermes-agent/apps/desktop
npm install --package-lock-only

# 4. 重建
hermes desktop --build-only
```

详见 `references/desktop-rebuild-npm-path.md`。

### 日志目录定位

```bash
# 快速查看所有告警/错误
grep -i "error\|warning\|fail" ~/.hermes/logs/*.log | tail -30

# 按时间查看最新日志
tail -50 ~/.hermes/logs/agent.log
tail -20 ~/.hermes/logs/errors.log
```

## Cron 任务排障

### 检查任务状态

```bash
# 列表所有 cron 任务，关注 last_status 和 last_run_at
hermes cron list
# 或通过 Hermes Agent 的 cronjob(action='list') 工具
```

重点关注字段：

| 字段 | 含义 |
|------|------|
| `last_status` | `ok` / `error` — 上次运行结果 |
| `last_run_at` | 上次实际运行时间（对比 schedule 看是否准时） |
| `no_agent` | true=纯脚本模式（stdout 直投递），false=LLM Agent 模式 |
| `script` | 脚本路径（仅 no_agent 模式） |

### 诊断 no_agent 脚本失败

`no_agent` 模式的 cron 任务不经过 LLM，运行时 stdout 作为消息投递。失败时需直接检查输出存档：

```bash
# 输出文件路径规则：~/.hermes/cron/output/<job_id>/<timestamp>.md
ls -la ~/.hermes/cron/output/<job_id>/
cat ~/.hermes/cron/output/<job_id>/<latest-file>.md
```

常见失败模式：

| 模式 | 特征 | 方向 |
|------|------|------|
| `Script timed out after Ns` | 脚本整体超时被 kill | 逐段测试脚本各步骤耗时，定位慢的环节。常见根因：curl 重试参数与 cron 超时不匹配（见 `references/cron-script-curl-reliability.md` 陷阱章节） |
| `Script exited with code N` | curl/ssh 等子命令失败 | 查 stderr 信息，加 `--retry` 应对网络抖动 |
| `stdout 空白` | 脚本 ran 但没输出 | 检查 `set -e` 是否在非关键步骤提前退出 |

**诊断流程：**
1. `cronjob list` → 找到异常的 job，记下 `job_id` 和 `last_status`
2. `read_file ~/.hermes/cron/output/<job_id>/<latest>.md` → 看失败原因文本
3. `terminal` 手动跑脚本各步骤 → 定位具体卡在哪一步
4. 修复 → `terminal` 验证脚本整体能跑通 → 等待下次 cron 触发或手动 `cronjob action='run'`

### Shell 脚本 curl 网络可靠性

当 cron 脚本需要从 GitHub 等外部源下载文件时，必须加 curl 重试参数应对瞬断：

```bash
# 推荐配置（定义在脚本顶部，所有 curl 调用统一引用）
CURL_RETRY="--retry 3 --retry-delay 10 --connect-timeout 15 --max-time 120"

# 应用到各处
curl -fsSL $CURL_RETRY "$URL" ...
curl -fL -s $CURL_RETRY "$DOWNLOAD_URL" -o "$TMP_FILE" ...
curl -fsIL $CURL_RETRY --max-redirs 5 "$URL" >/dev/null 2>&1
```

**参数说明：**
- `--retry 3`: 失败后重试最多 3 次（瞬断自动恢复）
- `--retry-delay 10`: 每次重试间隔 10 秒（给 GitHub 喘息时间）
- `--connect-timeout 15`: 连接超时 15 秒（避免 DNS/TCP 卡死）
- `--max-time 120`: 单次调用总超时 120 秒（防止无限挂起）

> 注意：`--max-time` 不包含重试时间，每次重试独立计时。

### Mattermost 串台：中断导致消息发到错误线程

**症状：**
- 用户报告 Agent 回复出现在了错误的 Mattermost 线程中
- 原始查询在一个线程，但响应（部分或全部）发到了另一个线程
- 通常发生在「长时间工具调用期间用户从一个不同线程发送了中断消息」

**诊断步骤：**

1. 从 Mattermost 消息 ID 反查日志：
   ```bash
   grep "<mattermost_post_id>" ~/.hermes/logs/agent.log ~/.hermes/logs/gateway.log
   ```

2. 追踪 `_resolve_root_id` 和 `send() threading` 日志行，比较中断前后的 `reply_to` / `resolved_root` 变化：
   ```bash
   grep "_resolve_root_id\|send() threading" ~/.hermes/logs/agent.log | tail -20
   ```

3. 确认时间线：
   - 中断前的 `send()` 目标（正确线程）
   - `tcp_force_closed=1` 事件（中断发生点）
   - 中断后的 `send()` 目标（是否变了）

4. 确认 Gateway inbound 日志：
   ```bash
   grep "inbound message" ~/.hermes/logs/gateway.log | grep "<时间窗口>"
   ```
   如果中断消息**没有独立的 inbound 日志**，说明它通过会话碰撞检测直接注入已激活会话。

**根因：** 两个 bug 在 `gateway/run.py`：① 中断后重入时 `_cache_session_source` 用中断消息的 source 覆盖原始正确缓存；② `source.thread_id=None`（渠道级帖子）导致 `_thread_metadata_for_source` 返回 `None`。

**修复：** 已作为 P60a + P60b 纳入 `hermes-patches.sh`。
```bash
bash ~/.hermes/scripts/hermes-patches.sh check  # 检查是否已应用
bash ~/.hermes/scripts/hermes-patches.sh apply  # 应用修复
```

详见 `references/mattermost-cross-thread-interruption.md` — 完整日志时间线与分析。

### 参考资料

- `references/macos-launchd-bootstrap-error5.md` — macOS launchd error 5
- `references/mcp-nodejs-abi-mismatch.md` — MCP 服务器 Node.js ABI 不匹配
- `references/cron-script-curl-reliability.md` — cron 脚本 curl 可靠性模式（完整示例）
- `references/desktop-rebuild-npm-path.md` — Desktop rebuild npm 路径与 lock 文件问题
- `references/mattermost-cross-thread-interruption.md` — Mattermost 串台：中断 metadata 传播 bug 完整日志分析
