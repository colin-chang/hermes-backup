# MCP Server Node.js 原生模块 ABI 不匹配

## 完整错误信息

在 `mcp-stderr.log` 中：
```
Error: The module '/opt/homebrew/lib/node_modules/@tobilu/qmd/node_modules/better-sqlite3/build/Release/better_sqlite3.node'
was compiled against a different Node.js version using
NODE_MODULE_VERSION 147. This version of Node.js requires
NODE_MODULE_VERSION 127. Please try re-compiling or re-installing
the module (for instance, using `npm rebuild` or `npm install`).
    code: 'ERR_DLOPEN_FAILED'
Node.js v22.22.3
```

在 `gateway.error.log` / `errors.log` 中（精简版）：
```
WARNING tools.mcp_tool: MCP server 'qmd' initial connection failed (attempt 1/3)
WARNING tools.mcp_tool: MCP server 'qmd' failed initial connection after 3 attempts, giving up
WARNING tools.mcp_tool: Failed to connect to MCP server 'qmd' (command=qmd): Connection closed
```

在 `agent.log` 中：
```
INFO tools.mcp_tool: MCP: registered 0 tool(s) from 0 server(s) (1 failed)
```

## 环境背景（2026-06-10 确认）

| 组件 | 路径 | 版本 | NODE_MODULE_VERSION | 来源 |
|------|------|------|---------------------|------|
| Hermes 捆绑 Node | `~/.hermes/node/bin/node` | v22.22.3 | 127 | Hermes Desktop 安装器 |
| PATH 上的 Node | `~/.local/bin/node` → 上述 | v22.22.3 | 127 | 符号链接（由安装器创建） |
| Homebrew Node | `/opt/homebrew/bin/node` | v26.3.0 | 147 | 用户手动 `brew install node` |
| qmd | `/opt/homebrew/lib/node_modules/@tobilu/qmd/` | 2.1.0 | — | `npm install -g`（当时 PATH 上可能是 Homebrew node） |

## 冲突链路

```
qmd 安装时（npm install -g）：PATH 优先级 → /opt/homebrew/bin/node (v26, ABI 147)
                                       ↓ better-sqlite3 编译为 ABI 147

Hermes 启动 qmd MCP 时：PATH 优先级 → ~/.local/bin/node (v22, ABI 127)
                                       ↓ 加载 better-sqlite3.node → 版本不匹配 💥
```

## 诊断清单

```bash
# 1. 确认 MCP 服务器列表和状态
hermes mcp list

# 2. 查看 MCP 崩溃的完整错误（关键！）
cat ~/.hermes/logs/mcp-stderr.log

# 3. 确认当前 Node.js 版本
which node && node --version

# 4. 检查多 Node.js 共存
~/.hermes/node/bin/node --version 2>/dev/null
/opt/homebrew/bin/node --version 2>/dev/null
ls -la ~/.local/bin/node ~/.local/bin/npm 2>/dev/null

# 5. 确认原生模块的编译目标
file /opt/homebrew/lib/node_modules/@tobilu/qmd/node_modules/better-sqlite3/build/Release/better_sqlite3.node 2>/dev/null
```

## 修复方案

### 方案 A：npm rebuild（推荐，一行命令）

用当前 PATH 上的 Node 重建原生模块，不动任何环境配置：

```bash
npm rebuild -g @tobilu/qmd
hermes gateway restart
```

### 方案 B：切换全局 Node 为 Homebrew 版本

移除 Hermes 的符号链接，让 Homebrew 的 Node 生效：

```bash
rm ~/.local/bin/node ~/.local/bin/npm ~/.local/bin/npx
hash -r
node --version          # 应显示 v26.3.0
npm rebuild -g @tobilu/qmd
hermes gateway restart
```

> **安全性验证**：Hermes Desktop（`/Applications/Hermes.app`）是 Electron 应用，自带运行时，不依赖 `~/.local/bin/node`。这些符号链接仅用于 CLI/MCP 场景。

### 方案 C：禁用 MCP 服务器

```bash
hermes mcp remove qmd
```

## 注意事项

- `gateway.error.log` 中只看到 "Connection closed"——**根因在 `mcp-stderr.log` 中**
- 这是一个 MCP 工具不可用的问题，**不影响 Gateway 核心功能**（平台连接、Cron、Kanban 等均正常）
- `hermes mcp list` 显示 "✓ enabled" 但实际启动失败——不要被状态列误导
