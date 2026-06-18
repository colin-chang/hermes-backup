---
name: homebrew-maintenance
description: "Homebrew 维护 — Tap 管理、僵尸安装检测、批量清理。当用户询问 brew tap/list/cleanup 或卸载遗留问题时使用。"
version: 1.0.0
platforms: [macos]
prerequisites:
  commands: [brew]
---

# Homebrew 维护

macOS Homebrew 的日常维护：Tap 审计、僵尸包检测、批量清理。

## 触发条件

- 用户询问"装了哪些 tap"、"这个 tap 有什么包"、"brew 清理"
- 怀疑有残留安装、已删除但 brew 仍记录的包
- 需要审计哪些 Tap 还在用、哪些可以 untap

## Tap 审计：列出第三方 Tap 及其已安装包

```bash
brew tap                                    # 列出所有第三方 Tap
```

交叉匹配每个 Tap 下实际安装的 Formula/Cask（参考 `references/tap-audit.sh`）：
- 遍历各 Tap 的 `Formula/*.rb` 和 `Casks/*.rb`
- 对每个 `.rb` 用 `brew list --formula <name>` 或 `brew list --cask <name>` 判断是否已装
- 注意部分 Tap 的 `.rb` 文件在仓库根目录而非 `Formula/` 子目录

## 僵尸安装检测

Cask 的典型僵尸模式：
- `brew list --cask` 显示已安装
- 但 Caskroom 下的 `.app` 是符号链接 → `/Applications/XXX.app` 且目标不存在（用户手动删了 .app 但没走 `brew uninstall`）

```bash
# 检测僵尸 Cask
ls -la /opt/homebrew/Caskroom/<name>/*/   # 看 .app 符号链接是否断链
find /Applications -name "*<AppName>*"     # 确认实际 .app 不存在
```

## 清理僵尸安装

```bash
# 1. 强制卸载（brew 跳过实际文件删除步骤）
brew uninstall --cask --force <name>

# 2. 如果 sudo 步骤失败（残留 LaunchAgents 等需权限的文件）
rm -rf /opt/homebrew/Caskroom/<name>      # 手动清 Caskroom

# 3. 确认从列表消失
brew list --cask | grep <name> || echo "已清除 ✅"
```

## 删除 Tap（必须先清空包）

```bash
# brew untap 会拒绝删除仍有已安装包的 Tap，必须先卸载
brew uninstall <tap/name>            # 逐个卸载
brew untap <user/tap>                # 再删 Tap
```

空 Tap（无已安装包）可直接 `brew untap`。

## 安装时间追溯

```bash
# 从 INSTALL_RECEIPT.json 的 time 字段读取 Unix 时间戳
python3 -c "
from datetime import datetime
import json
receipt = '/opt/homebrew/Cellar/<name>/<version>/INSTALL_RECEIPT.json'
ts = json.load(open(receipt))['time']
print(datetime.fromtimestamp(ts).strftime('%Y-%m-%d %H:%M'))
"
```

## Skill 依赖检查

清理前检查 Hermes skill 是否依赖该 CLI：
```bash
search_files pattern="\b<command>\b" target="/Users/Colin/.hermes/skills" output_mode=content
```

## Tap 信任策略警告（非官方 Tap 警告抑制）

Homebrew 在收紧第三方 Tap 信任，`brew update` 会逐 Tap 打印：

```
Warning: Tap amir1376/tap is allowed by default.
Homebrew will require explicit trust for non-official taps in a future release.
Set `HOMEBREW_REQUIRE_TAP_TRUST=1` to require explicit trust now or
`HOMEBREW_NO_REQUIRE_TAP_TRUST=1` to keep allowing by default.
Hide these hints with `HOMEBREW_NO_ENV_HINTS=1` (see `man brew`).
```

**这不是错误，是策略预告。** 三类解决方案：

| 方案 | 命令 | 效果 |
|------|------|------|
| 消除噪音（推荐） | `export HOMEBREW_NO_ENV_HINTS=1` | 隐藏提示，行为不变 |
| 拥抱新策略 | `export HOMEBREW_REQUIRE_TAP_TRUST=1` | 立即要求显式信任，不信任的 tap 报错 |
| 明确允许 | `export HOMEBREW_NO_REQUIRE_TAP_TRUST=1` | 声明允许所有第三方 tap |

建议写入 `~/.zshrc` 持久化。如果需排查哪个 Tap 在制造警告，先 `brew tap` 列出所有第三方 Tap，再 `brew tap-info <user/tap>` 查看每个 Tap 提供的内容。

## 注意事项

- 用 `write_file` + `bash /tmp/script.sh` 执行多步骤脚本，避免 heredoc 引号转义问题
- `brew info <name>` 默认可能解析为 Cask 而非 Formula，同名冲突时用 `--formula` / `--cask` 明确指定
- tool-selection-strategy 优先用 `search_files` + `terminal` 而非 `web_search` 解决本地 brew 问题
