# GitHub Actions 自动发布工作流

当用户要求"发布版本 X.Y.Z"时，通过 `workflow_dispatch` 触发自动发布，避免手动操作。

## 完整 Workflow 模板

```yaml
name: Release

on:
  workflow_dispatch:
    inputs:
      version:
        description: 'Version tag (e.g. v1.1.0)'
        required: true
        type: string

permissions:
  contents: write

jobs:
  release:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0

      - name: Validate version format
        run: |
          if [[ ! "${{ inputs.version }}" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            echo "❌ Version must match vX.Y.Z (e.g. v1.1.0)"
            exit 1
          fi

      - name: Update SKILL.md version
        run: |
          VERSION=$(echo "${{ inputs.version }}" | sed 's/^v//')
          sed -i "s/^version: .*/version: ${VERSION}/" SKILL.md

      - name: Commit version bump
        run: |
          git config user.name "github-actions[bot]"
          git config user.email "github-actions[bot]@users.noreply.github.com"
          git add SKILL.md
          git diff --staged --quiet && echo "No changes to commit" || git commit -m "Release ${{ inputs.version }}"

      - name: Create tag
        run: |
          git tag -af "${{ inputs.version }}" -m "Release ${{ inputs.version }}"

      - name: Push
        run: |
          git push origin main
          git push origin "${{ inputs.version }}"

      - name: Create GitHub Release
        uses: softprops/action-gh-release@v2
        with:
          tag_name: ${{ inputs.version }}
          name: ${{ inputs.version }}
          generate_release_notes: true
```

## 触发方式

```bash
# 在项目目录下执行
gh workflow run release.yml -F version=v1.1.0
```

## 工作流执行步骤

1. **校验版本格式** — 必须是 `vX.Y.Z`
2. **更新 SKILL.md** — 将 frontmatter 中的 `version:` 字段更新为新版本号
3. **提交版本号变更** — 仅当 SKILL.md 有变化时才 commit（幂等）
4. **打 tag** — 使用 `git tag -af`（强制覆盖，幂等）
5. **Push** — `main` 分支 + 新 tag
6. **创建 GitHub Release** — 使用 `softprops/action-gh-release@v2`，自动生成 Release Notes

## ⚠️ 常见陷阱

### 1. tag 已存在导致 workflow 失败

**现象**：先手动 `git tag vX.Y.Z && git push origin vX.Y.Z`，再触发 workflow。Workflow 在 "Create tag" 步骤报错：`fatal: tag 'vX.Y.Z' already exists`

**修复**：使用 `git tag -af` 代替 `git tag -a`。`-f` 强制更新已存在的 tag，使步骤幂等。

### 2. "Commit version bump" 无变更时失败

**现象**：SKILL.md 版本号已经是对的（用户手动改了），`git diff --staged --quiet` 返回 exit 1（有未暂存变更？不，是没有变更时 `||` 短路评估问题）。

**修复**：
```bash
# ❌ 错误 — git diff --staged --quiet 无变更时 exit 0，但 || 做反了
git diff --staged --quiet || git commit -m "..."

# ✅ 正确 — 显式处理两种分支
git diff --staged --quiet && echo "No changes to commit" || git commit -m "..."
```

### 3. sed 跨平台兼容（macOS vs Linux）

GitHub Actions runner 是 `ubuntu-latest`（Linux），`sed` 不需要 macOS 的 `-i ''` 空备份扩展名：

```bash
# ❌ macOS 特化 — 在 Linux runner 上报错
sed -i '' "s/^version: .*/version: ${VERSION}/" SKILL.md

# ✅ 跨平台 — 仅 Linux（GitHub Actions）直接用 -i
sed -i "s/^version: .*/version: ${VERSION}/" SKILL.md

# ✅ 兼容写法 — 如果将来换 macOS runner
sed -i '' "s/..." SKILL.md 2>/dev/null || sed -i "s/..." SKILL.md
```

### 4. README 中的版本 badge 不会自动更新

README.md 里的 `![GitHub Release](https://img.shields.io/github/v/release/...)` badge 是动态的 — 它自动显示最新 Release，不需要手动更新。

## 首次发布流程

```bash
# 1. 合规检查（参考本 Skill 1-5 步）
# 2. 提交所有文件
git add -A && git commit -m "v1.0.0: Initial release"

# 3. 创建 GitHub 仓库
gh repo create user/repo-name --public --source . --push --description "..."

# 4. 触发 workflow 发布
gh workflow run release.yml -F version=v1.0.0
```
