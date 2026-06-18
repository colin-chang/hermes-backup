# Hermes MCP & Node.js 排障

当 MCP 服务器连接失败、Native 模块报错、或 Hermes Desktop 与系统 Node.js 版本冲突时使用。

---

## MCP 崩溃诊断（首要步骤）

MCP 服务器启动失败时，`errors.log` 和 `gateway.error.log` 只显示笼统的 "Connection closed"。**真正的崩溃堆栈在 `mcp-stderr.log`**：

```bash
# 查看 MCP 服务器的 stderr 输出
cat ~/.hermes/logs/mcp-stderr.log

# 确认当前 MCP 服务器状态
hermes mcp list
```

**典型症状对照**：

| 日志文件 | 能看到的信息 |
|----------|------------|
| `errors.log` / `gateway.error.log` | `Failed to connect to MCP server 'X': Connection closed`（无细节） |
| `mcp-stderr.log` | 完整进程 stderr：Native 模块加载失败、JS 异常堆栈、退出码 |
| `agent.log` | `MCP: registered 0 tool(s) from 0 server(s) (1 failed)` |

---

## Node.js 原生模块 ABI 不匹配（高频）

### 根因

Hermes Desktop 安装器（`install.sh` 的 `check_node()`）会在**未检测到兼容 Node.js 时**自动下载 Node.js v22 到 `~/.hermes/node/`，并在 `~/.local/bin/` 创建符号链接。但全局 npm 包（如 `qmd`）可能是在 Homebrew Node.js v26 下安装的，其原生模块（`better-sqlite3`）编译时 ABI 与运行时 Node 版本不匹配。

```
~/.local/bin/node → ~/.hermes/node/bin/node (v22, ABI 127)  ← PATH 优先
/opt/homebrew/bin/node (v26, ABI 147)                        ← npm install -g 时用的版本
→ better-sqlite3.node 编译于 v26，无法在 v22 下加载 → 崩溃
```

### 诊断

```bash
# 1. 确认存在多个 Node.js
which node && node --version         # PATH 上的版本
/opt/homebrew/bin/node --version     # Homebrew 版本
~/.hermes/node/bin/node --version    # Hermes 捆绑版本

# 2. 确认全局包的原生模块状态
npm ls -g --depth=0 @tobilu/qmd 2>/dev/null

# 3. 检查 mcp-stderr.log 是否有 NODE_MODULE_VERSION 错误
grep "NODE_MODULE_VERSION" ~/.hermes/logs/mcp-stderr.log
```

### 修复方案

**方案一：用当前 PATH 上的 Node 重建原生模块（一行命令）**

```bash
npm rebuild -g @tobilu/qmd
hermes gateway restart
```

**方案二：移除 Hermes 捆绑的 Node，统一用 Homebrew**

```bash
rm ~/.local/bin/node ~/.local/bin/npm ~/.local/bin/npx
hash -r
node --version                    # 确认显示 v26.x
npm rebuild -g @tobilu/qmd
hermes gateway restart
```

方案二是根本解决，且不影响 Hermes Desktop（见下文）。

---

## Hermes Desktop 捆绑 Node.js 行为

### install.sh 的 check_node() 逻辑

```
check_node():
  1. PATH 上有 node 且版本 ≥20.19 或 ≥22.12 → 直接使用，不安装捆绑版
  2. ~/.hermes/node/bin/node 存在且兼容 → 使用已有捆绑版
  3. PATH 上有 node 但版本太旧 → 安装捆绑版
  4. 完全没有 node → 安装捆绑版（下载到 ~/.hermes/node/，符号链接到 ~/.local/bin/）
```

### macOS GUI 应用的 PATH 陷阱

macOS 从 Finder/Dock 启动的 GUI 应用默认 PATH 为：
```
/usr/bin:/bin:/usr/sbin:/sbin
```

**不包含** `/opt/homebrew/bin` 或 `~/.local/bin`。因此即使终端里 `node --version` 输出 v26，**Hermes Desktop 安装器可能检测不到 Homebrew 的 Node.js**，从而触发捆绑下载。

### 更新行为

Desktop 更新流程（`apps/bootstrap-installer/src-tauri/src/update.rs`）：
1. `hermes update --yes --gateway`
2. `hermes desktop --build-only`
3. 启动新版本

**更新不调用 `install.sh` 或 `check_node()`**，因此：
- 移除 `~/.local/bin/node` 符号链接后，后续更新**不会**重新创建
- 即使完全重装，只要安装器运行时 PATH 上有兼容 Node.js，也不会再下载捆绑版

### Hermes Desktop 对捆绑 Node 的依赖

- Hermes Desktop GUI 是 Electron/Tauri 应用，自带运行时，**不依赖** `~/.local/bin/node`
- `~/.local/bin/hermes` 是 CLI 入口脚本，指向 Python venv，也不依赖
- 只有 **MCP 服务器**（通过 `shutil.which("node")`）会用到 PATH 上的 Node.js

---

## MCP 日志文件速查

| 文件 | 内容 |
|------|------|
| `~/.hermes/logs/mcp-stderr.log` | MCP 子进程 stderr：崩溃堆栈、Native 模块错误 |
| `~/.hermes/logs/errors.log` | WARNING 级别以上：连接失败摘要 |
| `~/.hermes/logs/gateway.error.log` | Gateway 维度的 MCP 错误（与 errors.log 可能重复） |
| `~/.hermes/logs/agent.log` | MCP 注册结果：成功/失败计数 |
| `~/.hermes/logs/gateway.log` | Gateway 完整日志（含正常启动流程） |

**诊断优先级**：MCP 报错 → 先看 `mcp-stderr.log`（根因），再看 `errors.log`（影响范围）。
