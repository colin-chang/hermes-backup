# Desktop Rebuild 失败：npm 路径与 lock 文件

## 错误日志特征

在 `~/.hermes/logs/bootstrap-installer.log` 的 `stage=rebuild` 中：

```
Desktop GUI requires Node.js/npm, but npm was not found on PATH.
Install Node.js, then run:  hermes gui
```

随后 bootstrap 报告：

```
Rebuilding the desktop app failed (exit Some(1)). The update was applied
but the app could not be rebuilt; run `hermes desktop` from a terminal
to see the error.
```

**关键：update 阶段（Python/pip）成功，但 rebuild 阶段（Electron/npm）失败。**

## 根因分析

### 子问题 1：GUI 上下文中找不到 npm

macOS GUI 应用（包括 Hermes Desktop 的更新进程）从 `launchd` 继承环境变量，
**不会**加载 shell profile（`~/.zshrc` 等）。如果 Node.js 通过 Homebrew 安装在
`/opt/homebrew/bin/`，GUI 进程的默认 PATH 不含该目录。

诊断：
```bash
# 终端内能找到 npm，但 GUI 进程不行
which npm                          # → /opt/homebrew/bin/npm ✓
launchctl getenv PATH              # → 通常为空，或不含 /opt/homebrew/bin
```

### 子问题 2：lock 文件版本不匹配

当 Node.js 版本升级后，`package-lock.json` 中锁定的依赖版本可能不再满足
`package.json` 中的 semver 约束。典型错误：

```
npm error `npm ci` can only install packages when your package.json and
package-lock.json or npm-shrinkwrap.json are in sync.
npm error Invalid: lock file's @types/node@24.13.1 does not satisfy
@types/node@24.13.2
```

`hermes desktop` 内部使用 `npm ci`（严格模式），要求 lock 文件精确匹配。

## 修复步骤

### 1. 设置 GUI 可见的 PATH（使用 launchctl，非符号链接）

```bash
# 当前会话生效
launchctl setenv PATH "/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

# 持久化到 ~/.zshrc（每次开终端自动 re-set）
echo '
# 持久化 GUI 应用 PATH（Hermes Desktop rebuild 需要 npm）
launchctl setenv PATH "/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
' >> ~/.zshrc
```

> ⚠️ **不要创建 `~/.local/bin/node` 符号链接**作为修复手段。
> 如果之前因 MCP ABI 问题已移除这些符号链接，重新创建会复现 MCP 问题。
> `launchctl setenv` 是正确的方式——让现有 Homebrew 安装对 GUI 进程可见。

### 2. 修复 lock 文件

```bash
cd ~/.hermes/hermes-agent/apps/desktop
npm install --package-lock-only
```

### 3. 重建 Desktop app

```bash
hermes desktop --build-only
```

验证产物：
```bash
ls ~/.hermes/hermes-agent/apps/desktop/release/mac-arm64/Hermes.app
```

## 与 MCP 符号链接问题的关系

MCP ABI 不匹配时，修复方案 B 是移除 `~/.local/bin/node` 符号链接（见
`references/mcp-nodejs-abi-mismatch.md`）。移除后，GUI rebuild 阶段找不到
npm 是**预期结果**——`launchctl setenv` 解决 PATH 问题，无需恢复符号链接。
