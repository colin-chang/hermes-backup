# Node.js 版本冲突：Desktop 捆绑版 vs 系统版

## 问题特征

- Gateway 启动日志中出现 MCP 服务器（如 qmd）连接失败
- `mcp-stderr.log` 报错 `NODE_MODULE_VERSION 127 vs 147` 或类似 `ERR_DLOPEN_FAILED`
- `hermes mcp test <name>` 显示连接失败
- 仅影响依赖原生模块的 Node.js MCP 服务器（better-sqlite3 等）

## 根因链

```
Hermes Desktop 安装器（GUI PATH 不含 Homebrew/手动安装的 Node.js）
  → install.sh 的 check_node() 找不到系统 Node.js
    → 下载 Node.js v22 LTS 到 ~/.hermes/node/
      → 在 ~/.local/bin/ 创建 node/npm/npx 符号链接
        → PATH 优先级覆盖系统 Node.js
          → MCP 服务器的原生模块编译时用 v26，运行时被 v22 加载 → 💥 ABI 不匹配
```

## 环境确认

```bash
# 1. 检查有多少个 Node.js 在 PATH 上
which -a node

# 2. 确认符号链接来源
ls -la ~/.local/bin/node    # → 如果指向 ~/.hermes/node/bin/node，说明是 Desktop 安装的

# 3. 对比版本
~/.hermes/node/bin/node --version   # Desktop 捆绑版（通常 v22）
/opt/homebrew/bin/node --version    # Homebrew 安装版（可能 v26+）

# 4. 检查 gateway plist 中的 PATH
/usr/libexec/PlistBuddy -c "Print :EnvironmentVariables:PATH" \
  ~/Library/LaunchAgents/ai.hermes.gateway.plist | tr ':' '\n' | grep node
```

## 修复步骤

### 方案 A：统一到 Homebrew/系统 Node.js（推荐）

```bash
# 1. 停止 gateway
launchctl bootout gui/501/ai.hermes.gateway
# 如果 bootout 失败（error 3），用 pkill -9 强杀
pkill -9 -f "hermes_cli.main gateway"

# 2. 删除 Desktop 捆绑的 Node.js
rm -rf ~/.hermes/node/

# 3. 删除 PATH 中的旧符号链接
rm -f ~/.local/bin/node ~/.local/bin/npm ~/.local/bin/npx

# 4. 确认当前使用系统 Node.js
hash -r && which node && node --version

# 5. 重建受影响的 MCP 服务器原生模块
npm rebuild -g @tobilu/qmd    # 或其他受影响的包

# 6. 重建 gateway plist（刷新 PATH）
hermes gateway install --force

# 7. 验证
hermes mcp test qmd
```

### 方案 B：统一到 Desktop 捆绑版

```bash
# 用 Desktop 捆绑的 Node 重建原生模块
export PATH="$HOME/.hermes/node/bin:$PATH"
npm rebuild -g @tobilu/qmd
hermes gateway restart
```

简单但未来 Desktop 更新可能更换捆绑版本，需再次 rebuild。

## Desktop 更新是否会重新创建捆绑 Node.js？

**不会。** Desktop 更新流程（`update.rs`）只执行：
1. `hermes update --yes --gateway`（git pull + pip install）
2. `hermes desktop --build-only`（重编译 Tauri 桌面应用）

不调用 `install.sh` 的 `check_node()`，不会重新下载或创建 Node.js。

彻底重装时 `check_node()` 会优先使用 PATH 上已有的现代 Node.js，不会重复下载。

## `Bootstrap failed: 5` 说明

macOS 上 `launchctl bootstrap` 偶发返回 error 5 但实际加载成功。表现：
- 终端显示 `Bootstrap failed: 5: Input/output error`
- 紧接着 `⚠ launchd cannot manage the gateway on this macOS version`
- 但 `hermes gateway status` 显示 `✓ Gateway service is loaded`

**这是 cosmetic 问题**，不影响功能。Hermes 检测到 launchd 失败后自动降级为后台进程模式，功能完全一致（仅缺失自动重启和开机自启，但下次 `hermes gateway install --force` 通常能修复）。

## 相关日志文件

| 文件 | 内容 |
|------|------|
| `~/.hermes/logs/mcp-stderr.log` | MCP 服务器的 stderr — NODE_MODULE_VERSION 错误在这里 |
| `~/.hermes/logs/gateway.error.log` | Gateway 级错误 |
| `~/.hermes/logs/errors.log` | WARNING+ 级别日志（含 MCP 连接失败警告） |
