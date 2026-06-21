---
name: shell-theme-compatibility
description: "诊断和修复 Shell 主题在特定终端模拟器中的字符显示异常（乱码/方框），涵盖 Powerline/Nerd Font 依赖主题与 Electron/Chromium-based 终端的兼容性问题。"
version: 1.0.0
platforms: [macos, linux]
metadata:
  hermes:
    tags: [terminal, font, shell, theme, troubleshooting, electron, powerline, nerd-font]
    category: custom
---

# Shell 主题兼容性诊断

当用户在某个终端模拟器中看到乱码/方框/问号替代了原本的图标字符时，按照本流程诊断和修复。

## 触发条件

- 用户在某个终端（CodeX 内置终端 / VS Code 集成终端 / Cursor / Windsurf / Hyper 等）中看到 `□` `?` 或空白替代了预期字符
- 用户说"XX 终端里字符显示不正常，但 Ghostty/iTerm2 正常"
- 用户使用 oh-my-zsh 的 `agnoster` / `powerlevel10k` / `spaceship` 等主题

## 诊断流程

### Step 1: 确认主题是否依赖特殊字体

```bash
grep ZSH_THEME ~/.zshrc
```

需要 Nerd Font / Powerline 字体的常见主题：
- `agnoster` — 大量 Powerline 分隔符和图标
- `powerlevel10k` — 可配置，默认使用 Nerd Font 图标
- `spaceship` — 使用 Unicode 特殊符号
- `pure` — 纯 ASCII，**不需要**特殊字体 ✅

不需要特殊字体的安全主题：
- `robbyrussell` — oh-my-zsh 默认
- `gentoo` — 简洁彩色提示符

### Step 2: 确认用户是否安装了 Nerd Font

```bash
ls ~/Library/Fonts/*[Nn]erd* 2>/dev/null
ls ~/Library/Fonts/*Powerline* 2>/dev/null
ls /Library/Fonts/*[Nn]erd* 2>/dev/null
```

常见 Nerd Font 命名模式：`MapleMono-NF-*`, `Meslo LG M * for Powerline`, `FiraCode Nerd Font *`

### Step 3: 判断终端模拟器的渲染引擎

| 终端 | 渲染引擎 | 用户字体 fallback |
|------|---------|-----------------|
| Ghostty | macOS 原生 CoreText | ✅ 自动搜索 `~/Library/Fonts/` |
| iTerm2 | macOS 原生 CoreText | ✅ 自动搜索用户字体 |
| Terminal.app | macOS 原生 CoreText | ✅ 自动搜索用户字体 |
| Kitty | 独立渲染引擎 | ✅ 支持 fontconfig fallback |
| Alacritty | 独立渲染引擎 | ✅ 支持 fontconfig fallback |
| **CodeX 内置终端** | Electron/Chromium | ❌ 不搜索用户字体 |
| **VS Code 集成终端** | Electron/Chromium (xterm.js) | ⚠️ 需显式配置 `terminal.integrated.fontFamily` |
| **Cursor 集成终端** | Electron/Chromium (xterm.js) | ⚠️ 需显式配置 |
| **Windsurf 集成终端** | Electron/Chromium (xterm.js) | ⚠️ 需显式配置 |
| **Hyper** | Electron/Chromium (xterm.js) | ⚠️ 需显式配置 |

### Step 4: 选择修复方案

**方案 A（推荐，最稳）：换主题**
```bash
# 在 ~/.zshrc 中将 agnoster 替换为纯 ASCII 主题
ZSH_THEME="gentoo"        # 简洁彩色，无特殊字符
# ZSH_THEME="robbyrussell"  # 经典默认
```
生效：`source ~/.zshrc` 或新开终端。

**方案 B（保留颜值）：按终端类型动态切换主题**
在 `~/.zshrc` 中添加条件判断，让原生终端用 agnoster，Electron 终端降级：
```bash
# 检测终端应用名称（macOS）
TERM_APP=$(osascript -e 'tell application "System Events" to get name of first process whose frontmost is true' 2>/dev/null)
case "$TERM_APP" in
  Codex|Code|Cursor|Windsurf)
    ZSH_THEME="gentoo"
    ;;
  *)
    ZSH_THEME="agnoster"
    ;;
esac
```
⚠️ 注意：`osascript` 方法在非交互式 shell 初始化中可能不可靠，仅作思路参考。

**方案 C（IDE 场景）：显式配置终端字体**
- VS Code: `settings.json` → `"terminal.integrated.fontFamily": "MapleMono NF CN"`
- Cursor: 同上
- CodeX 桌面应用：目前不暴露终端字体设置（硬编码为 Menlo/Lucida Console），只能用方案 A

## 参考文件

- `references/codex-terminal-font.md` — CodeX 桌面应用终端字体问题详细分析
