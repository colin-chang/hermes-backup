# CodeX 桌面应用终端字体问题

## 环境信息

- **CodeX 版本**: `149.0.7827.115` (Chromium-based)
- **安装路径**: `/Applications/Codex.app`
- **配置目录**: `~/.codex/`
- **应用数据**: `~/Library/Application Support/Codex/`
- **CLI 路径**: `/Applications/Codex.app/Contents/Resources/codex`
- **CLI 版本**: `codex-cli 0.142.0-alpha.6`

## 问题现象

CodeX 内置终端中，oh-my-zsh `agnoster` 主题的 Powerline 分隔符和图标显示为方框（□）或问号（?）。但 Ghostty 中正常。

## 根因

1. **主题依赖**: `agnoster` 主题使用 Powerline Private Use Area 字符（U+E0A0–U+E0D0），必须由 patched 字体提供
2. **用户已装 Nerd Font**: `~/Library/Fonts/` 下有 `MapleMono-NF-CN-*.ttf` 和 `Meslo LG M * for Powerline.ttf`
3. **Ghostty 正常**: macOS 原生 CoreText 渲染引擎会自动搜索 `~/Library/Fonts/` 做字体 fallback，找到了 Meslo/MapleMono
4. **CodeX 异常**: CodeX 是 Electron/Chromium 应用，Chromium 的文本渲染栈**不会**搜索用户安装的字体做 fallback。CodeX 的终端 CSS 硬编码了 `font-family: "Menlo", "Lucida Console", monospace`（位于 `/Applications/Codex.app/Contents/Resources/default_app/styles.css`），这两个字体都不包含 Powerline glyphs

## 已验证的修复

修改 `~/.zshrc`:
```
ZSH_THEME="gentoo"
```
生效后 CodeX 终端正常显示。`gentoo` 主题使用纯 ASCII 字符，零字体依赖。

## 未验证的替代方案

- CodeX 目前不暴露终端字体设置 UI
- 理论上可通过修改 `default_app/styles.css` 中的 `font-family` 添加 Nerd Font，但会随应用更新失效
- Chromium 字体配置可能可通过 `chrome://settings/fonts` 或命令行 flag 调整，但 CodeX 的 settings 页面不暴露此选项
