# .gitignore 维护模式（Hermes dotfiles 专用）

## 核心原则

### 1. 否定模式优先于逐目录列举

**痛点**：每新增一个内置 skill 目录就要手动加一行 ignore 规则。
**改善**：用 `skills/*` + `!skills/custom/` 两行替代。

```gitignore
# 忽略全部 skills，仅保留 custom/
skills/*
!skills/custom/
# 独立仓库（在 custom 下但不由本仓库管理）
skills/custom/image2webp-skill/
skills/custom/nomad-imessage/
```

#### ⚠️ 为什么不能用 `skills/`？

Git 官方文档（gitignore(5)）明确规定：

> *"It is not possible to re-include a file if a parent directory of that file is excluded. Git doesn't list excluded directories for performance reasons, so any patterns on contained files have no effect."*

| 写法 | Git 行为 | 结果 |
|------|---------|------|
| `skills/` | 匹配目录本身，Git 停止扫描内部 | ❌ `!skills/custom/` 是死代码——Git 根本不会看到它 |
| `skills/**` | 递归匹配内容，但 Git 仍可能跳过扫描 | ❌ 同上，实测同样失效 |
| `skills/*` | 仅匹配直接子级，Git **继续扫描目录内部** | ✅ negation 可以生效 |

**验证方法**：
```bash
# 如果输出 non-zero（"ignored"），说明 negation 未生效
git add --dry-run skills/custom/role-china-insider/SKILL.md
# 预期：add 'skills/custom/...'（可以添加 = negation 生效）
```

上游子目录规则（如 `skills/.archive/`）被上层 `skills/*` 覆盖后即为冗余，应删除。

### 2. SQLite WAL 文件用通配符合并

```gitignore
# ❌ 冗余
state.db
state.db-shm
state.db-wal

# ✅ 合并
state.db*
```

### 3. 已追踪文件的 ignore 不生效

`.gitignore` 只影响未追踪文件。文件一旦被 `git add` / commit，ignore 规则对它无效。

**修复**：`git rm --cached <file>` — 从索引删除但保留本地文件。

**自查命令**：
```bash
# 检查某文件是否已被 Git 追踪
git ls-files --error-unmatch <file>

# 列出某目录下所有被追踪的文件
git ls-files <dir>/
```

## Desktop 安装产物（必须忽略）

Hermes Desktop 首次安装/启动时会在 `~/.hermes/` 落盘大量运行时文件，
全部应由 `.gitignore` 排除：

```gitignore
# Desktop 安装产物
node/                       # 内置 Node.js 运行时（~200MB / ~5000 文件）
bootstrap-cache/            # Desktop 启动缓存
hermes-setup                # macOS 安装器二进制（~11MB Mach-O）
desktop-build-stamp.json    # 构建戳（每次启动刷新）
.install_method             # 安装方式记录
.update_exit_code           # 更新流程退出码
```

这些文件在 Desktop 安装后首次 `git status` 时会产生数千条 untracked 噪音。
Desktop 更新时 `node/` 和 `hermes-setup` 可能被替换，始终不应纳入版本管理。

### 安装后验证

```bash
# 确认所有 Desktop 产物已被正确忽略
cd ~/.hermes
git check-ignore node/ bootstrap-cache/ hermes-setup \
  desktop-build-stamp.json .install_method .update_exit_code
# 预期：每行输出对应路径名（命中 ignore 规则）
```

## 运行时空目录（非 Desktop 专属）

```gitignore
# 运行时空目录
pairing/          # 网关配对状态
hooks/            # 运行时 hooks（预留给未来扩展）
```

这些目录是 Hermes 运行时自动创建的，包含临时状态数据，不应纳入版本管理。它们通常为空或仅含临时文件。

## 注意事项

- `workspace/` **不应** gitignore — 用户手动放置的工作文件，需纳入代码追踪。误加后用户会明确要求移除。
- `Processes.json`（大写 P）在大小写不敏感文件系统（APFS）上能匹配 `processes.json`，但在 Linux 等大小写敏感系统上会失效，应统一为小写。
- Desktop 安装产物（`node/`、`hermes-setup` 等）详见上方「Desktop 安装产物」节。

修改 `.gitignore` 后自查：
- [ ] 是否存在已覆盖的子目录规则（如 `skills/*` 已 ignore，`skills/.archive/` 冗余）
- [ ] **否定模式 `!` 是否实际生效**（父目录未被排除导致 Git 无法扫描内部 — 用 `git add --dry-run` 验证，非 `git check-ignore`）
- [ ] 是否存在被 glob 覆盖的单文件规则（如 `gateway.*` 已覆盖 `gateway_state.json`）
- [ ] 是否有已追踪文件需要 `git rm --cached`
- [ ] **禁止用 `skills/` + `!skills/custom/` 组合**——被排除的父目录内否定无效，必须用 `skills/*`
