---
name: open-source-compliance
description: 开源项目合规化检查清单 — 从私有项目到 GitHub 公开仓库的完整流程。涵盖凭证脱敏、LICENSE/SECURITY/PRIVACY 文档、.gitignore 审查、双语 README、泄漏扫描、Skill Reference 内容审计。
triggers:
  - 开源项目
  - GitHub 发布
  - 开源合规
  - 合规化
  - open source
  - LICENSE
  - SECURITY.md
  - PRIVACY.md
  - 凭证脱敏
  - 敏感信息扫描
  - 路径脱敏
  - 破碎引用
  - reference 审计
  - skill 清理
  - git filter-branch
  - 历史清理
  - 通用性审计
  - 平台特化
  - 分离通用内容
---

# 开源项目合规化

将私有项目发布到 GitHub 前的合规化检查流程。

## 检查清单

### 1. 凭证脱敏

- [ ] **扫描硬编码凭证**：`grep -rn 'private_key\|api_key\|secret\|password\|token' --include='*.py' --include='*.js' --include='*.json' --include='*.yml'`
- [ ] **项目 ID 脱敏**：将 GCP/AWS 项目 ID 替换为 `your-project-id` 等占位符
- [ ] **config.json → config.example.json**：真实配置加入 `.gitignore`，提供脱敏示例文件
- [ ] **密钥文件排除**：确保 `.gitignore` 覆盖密钥文件名（注意：同名目录也要排除，如 `vertex-key.json/`）
- [ ] **路径脱敏**：`grep -rn '/Users/\|/home/' --include='*.md' --include='*.py' --include='*.sh' --include='*.yml' . | grep -v '.git/'` 扫描个人主目录路径，替换为 `<SKILL_DIR>`、`~/` 或通用占位符
- [ ] **Git 历史扫描**：如果仓库曾有凭证提交过，需 `git filter-branch` 或 BFG 清除

### 2. .gitignore 审查

```gitignore
# 必须排除的类别
*.env                          # 环境变量
config.json                    # 含项目 ID 的真实配置
*-key.json / *-key.json/       # 密钥文件（文件和同名目录）
data/*                         # 运行时数据
!data/.gitkeep                 # 保留目录结构
__pycache__/                   # Python 缓存
.DS_Store                      # macOS
```

**易漏项**：`.gitignore` 只排除文件不排除同名目录。如果密钥文件可能是目录（空目录占位），需加 `filename/` 规则。

### 3. 合规文档

| 文件 | 内容 | 必须 |
|------|------|------|
| `LICENSE` | MIT / Apache 2.0 等 | ✅ |
| `SECURITY.md` | 漏洞报告流程 + 凭证处理策略 | ✅ 处理凭证的项目 |
| `PRIVACY.md` | 数据存储位置 + 出站流量声明 + 删除方法 | ✅ 有 Web UI 或收集数据的项目 |
| `CODE_OF_CONDUCT.md` | 社区行为准则 | ⚠️ 期望有社区贡献的项目 |

### 4. 双语 README

- `README.md`（英文主版）+ `README.zh-CN.md`（中文版），互链切换
- **编辑流程**：先定稿中文版（更自然），再同步英文版
- 顶部加语言切换链接：`[中文文档](README.zh-CN.md) | English`

### 5. 最终泄漏验证

```bash
# 检查 staged 内容中是否有残留凭证
git diff --cached | grep '^+' | grep -i 'project-id-pattern\|private_key.*BEGIN\|client_email.*@'

# 确认敏感文件未被跟踪
git ls-files | grep -E 'config\.json|key\.json|\.env$'

# 检查破碎的内部引用（文档中引用了不存在的文件）
for f in $(git ls-files -- '*.md'); do
  grep -oP '\[.*?\]\(([^)]+)\)' "$f" | grep -oP '(?<=\().*(?=\))' | grep -v '^https\?://' | while read ref; do
    target=$(dirname "$f")/"$ref"
    [ -f "$target" ] || echo "  ⚠️ $f → $ref (文件不存在)"
  done
done
```

### 附加：Skill Reference 审计（Hermes Skill 专属）

当开源项目是 **Hermes Skill 集合** 时，仅做凭证/路径扫描不够——`references/` 目录下的 Markdown 文件可能包含大量个人生活信息，这些信息不会被 `grep` 的模式匹配到。

按以下 5 类逐一审计每个 `references/*.md` 文件：

| 类型 | 内容特征 | 处理 |
|------|----------|------|
| **A. 角色记忆/用户档案** | `role-memory.md`、`user-context.md`（Agent 运行时记忆） | **全部删除** — 含家庭、财务、健康等隐私 |
| **B. 个人生活信息** | 移民策略、时间线、法律条文研究、书信风格指南 | **全部删除** — 他人无法复用，泄露个人计划 |
| **C. 个人财务/税务** | CRA 银行信息、税务研究、投资标的记录 | **全部删除** |
| **D. 项目特定** | 仅当前开发项目（如专门的 side project）相关的架构/数据文档 | **全部删除** — 与其他用户无关 |
| **E. 本地环境** | 含本地域名、Docker 配置路径、插件审计清单 | **删除或脱敏** — 视通用程度决定 |

**审计脚本（一键扫描 Git 追踪的所有 references）：**

```bash
# 批量扫描 references 目录中可能的个人信息
for f in $(git ls-files '*/references/*.md'); do
  if head -5 "$f" | grep -qiE 'role.memory|user.context|user profile|专属|用户档案|家庭|移民|孩子|CRA|OINP'; then
    echo "🔴 PRIVATE: $f"
  else
    echo "🟢 CHECK-MANUALLY: $f"
  fi
done
```

> ⚠️ 上述脚本仅作初筛——最终需要人工逐文件确认。很多文件不含明显的个人关键词但仍含私人信息。

**角色 Skill 的特殊规则：**
- `role-*/SKILL.md` → 可保留：角色切换模式本身是可复用的通用技术
- `role-*/references/role-memory.md` → **必须删除**：Agent 运行时记忆
- `role-*/references/user-context.md` → **必须删除**：含真实个人信息

### 6. GitHub 推送

```bash
# 首次推送
gh repo create RepoName --public --source . --push --description "..."

# 或已有仓库
git remote add origin git@github.com:user/RepoName.git
git push -u origin main
```

### 7. 通用性审计：分离平台特化内容

**最容易被忽视的合规步骤**：一个 skill 的 `references/` 目录可能包含大量文档，但并非所有文档都适合作为「通用开源项目」发布。以下内容即使不含凭证/个人信息，也应**排除在开源仓库之外**，但必须**保留在本地 skill 目录内**（gitignored），绝不能移到外部孤岛目录。

| 内容类型 | 示例 | 处理 |
|---------|------|------|
| **平台特化集成文档** | `references/hermes/`（Hermes Agent 专用集成指南、Cron 模式、open 验证） | **保留在 skill 内，gitignore** |
| **个人事故复盘** | 某次 Cron 推送失败的竞态条件分析、LaunchAgent 部署记录 | **保留在 skill 内，gitignore** |
| **平台 Hub 发布经验** | Hermes Skills Hub 安全扫描机制记录 | **保留在 skill 内，gitignore** |
| **本机环境假设** | 硬编码 `/Users/xxx/.hermes/` 路径、特定模型名（`doubao-seed-2.0-pro`） | 替换为 `<SKILL_DIR>` 或通用描述 |

**判断标准**：问自己——「一个素未谋面的 macOS 用户，用 Claude Code 或 Codex 而非 Hermes Agent，这份文档对他有用吗？」如果答案是否定的，**从 Git 中移除**，但 **不移动文件**——文件留在 skill 目录内，用 `.gitignore` 排除。

**SKILL.md 同步清理**：
- 故障排查表中移除指向已删除（从 Git 跟踪中移除的）`references/hermes/` 的交叉引用
- 「自动化集成」章节移除特定平台工具名（`execute_code` → "Python 函数调用"）
- 「参考」章节移除全部平台特化文档链接

**操作流程**：
```bash
# 0. 提取可复用内容（先提取再删除！）
#    检查要删除的每个 reference 文件，如有通用价值的内容（排查步骤、常见陷阱、Shell 写法），
#    提取到 README 或 SKILL.md 中，再删除原文件。否则知识随文件一起湮灭。

# 1. 用 .gitignore 排除非通用目录/文件（文件不动！）
echo 'references/hermes/' >> .gitignore
echo 'references/<platform-specific>.md' >> .gitignore

# 2. 从 Git 跟踪中删除（文件仍保留在本地磁盘）
git rm --cached references/hermes/hermes-integration.md references/hermes/cron-delivery-pattern.md ...

# 3. 清理 SKILL.md + README 中的交叉引用
#    同时删除 Documentation 表格中指向已删除文件的行，避免 GitHub 404
# 4. 提交 .gitignore 更新 + 删除
# 5. 若已发布过，需重写 Git 历史（见下方常见陷阱 #7）
```

**⚠️ 先提取再删除**：被移除的 reference 文件中常有排查经验、Shell 写法陷阱等通用知识。如果直接 `git rm` 而不先审查并提取到 README/SKILL.md，这些知识会随文件一起消失——且 Git 历史重写后无法恢复。典型模式：
- `send-debugging-guide.md` → 提取 Shell `|| &&` 优先级陷阱 + 排查命令 → 合并到 README Troubleshooting 章节
- `imessage-fda-bridge.md` → 提取 FDA 继承原理 → 补充到 README 架构描述

### 8. Reference 文件含非凭证类个人信息

`grep` 扫描凭证和路径只能抓到 `api_key`、`/Users/` 这类机械模式。以下内容会**通过全部自动化扫描**但绝不应公开：

- Agent 角色记忆文件（`role-memory.md`）— 含家庭结构、居住地、职业、时间线
- 用户档案文件（`user-context.md`）— 含 Google Sheet ID、项目路径、技术栈偏好
- 移民策略/时间线 — 含具体登陆日期、签证类型、城市名称
- 书信风格指南 — 含夫妻称呼习惯、家庭语境
- 项目特定架构文档 — 含 `/Users/Colin/Developer/...` 的绝对路径

**教训：自动化扫描是必要条件，不是充分条件。开源前必须做人工逐文件审计。**

添加 `.github/workflows/release.yml`，通过 `workflow_dispatch` 触发自动发布：更新版本号 → 提交 → 打 tag → 推送 → 创建 GitHub Release。

```bash
# 触发发布
gh workflow run release.yml -F version=v1.0.0
```

> 完整模板 + 常见陷阱见 `references/github-release-workflow.md`。

**关键要点**：
- `git tag -af`（不是 `-a`）— 幂等，避免 tag 已存在时报错
- "Commit version bump" 步骤用 `&& echo || commit` 代替 `|| commit` — 避免无变更时 exit 1
- 用 `softprops/action-gh-release@v2` 创建 GitHub Release，自动生成 Release Notes

## 常见陷阱

### 1. 密钥文件是目录而非文件

某些工具或脚本可能将 `key.json` 创建为目录（空目录占位），`.gitignore` 的 `key.json` 规则只排除同名文件。需加 `key.json/` 排除目录。

### 2. 全局 select/input 样式含敏感字段

表单样式中的 `input, textarea, select` 可能影响非表单页面的共享组件（导航栏下拉框）。用 `:not()` 排除。

### 3. test_*.py 中硬编码项目 ID

测试脚本常包含真实 GCP/AWS 项目 ID，脱敏时容易遗漏。

### 4. config.json 只排除不够

仅将 `config.json` 加入 `.gitignore` 不够——如果文件已被 Git 跟踪，`.gitignore` 不生效。需先 `git rm --cached config.json` 再 commit。

### 5. 主目录路径不是凭证，但仍是个人信息

`/Users/Colin/…` 或 `/home/alice/…` 不会被 `grep private_key\|api_key` 扫描到，但暴露了用户名和目录结构。必须在合规化阶段单独扫描 `grep -rn '/Users/\|/home/'` 并替换为 `<SKILL_DIR>` 或 `~/`。

### 6. 文档中的内部引用指向不存在的文件

`.md` 文件中的 `[链接](references/some-file.md)` 在本地可能正常工作（文件存在于你的机器上），但发布到 GitHub 后文件缺失会导致 404。`git status` 显示 untracked 不代表文件已被 commit——需用 `git ls-files` 确认文件被跟踪，或用脚本检查每个引用目标的 `[ -f ]` 状态。

### 7. 已发布的非通用文件需从 Git 历史中彻底抹除

仅 `git rm` + 新 commit 不够——文件仍残留在历史 commit 中。必须用 `git filter-branch` 重写全部历史：

```bash
# 重写历史，永久移除文件
git filter-branch --force --index-filter \
  'git rm --cached --ignore-unmatch \
    references/hermes/hermes-integration.md \
    references/hermes/cron-delivery-pattern.md \
    ...' \
  --prune-empty --tag-name-filter cat -- --all

# 清理 filter-branch 备份（否则旧历史仍可恢复）
git for-each-ref --format='%(refname)' refs/original/ | xargs -n 1 git update-ref -d
git reflog expire --expire=now --all
git gc --prune=now --aggressive

# 强制推送
git push origin main --force
git push origin --delete v1.0.0 v1.1.0  # 删除旧 tag
git push origin --tags --force           # 推送重写后的 tag

# 删除旧 GitHub Release
gh release delete v1.0.0 --yes
```

**⚠️ 注意**：历史重写后，所有协作者必须 `git fetch --force` + `git reset --hard origin/main`。tags 需要 `git fetch --tags --force`。

**⚠️ filter-branch 前必须处理工作区变更**：若当前有未暂存/未提交的变更（如 `.gitignore` 编辑），filter-branch 会拒绝执行（「您有未暂存的变更」）。需先 `git stash`。但 filter-branch 会重写 stash ref，导致 `git stash pop` 失败（「不像是一个储藏提交」）。**正确流程**：

```bash
# 1. 暂存当前变更
git stash push -m "temp: before filter-branch"

# 2. 执行 filter-branch（会重写 stash ref → 导致 stash 损坏）
git filter-branch --force ...

# 3. 清理 + 丢弃损坏的 stash
git for-each-ref --format='%(refname)' refs/original/ | xargs -n 1 git update-ref -d
git reflog expire --expire=now --all
git gc --prune=now --aggressive
git update-ref -d refs/stash   # stash 已被 filter-branch 损坏，手动删除

# 4. 重新应用 stash 内容（手动，因为 pop 失败）
# 回忆 stash 中改了什么，重新编辑文件
```

### 8. 把非通用文件移到外部孤岛目录

将 `references/hermes/` 移出到 `~/.hermes/references/<skill>-local/` 看似干净，实则会创建一个**没有任何程序读取的孤岛目录**——SKILL.md 的交叉引用已被清理，文件在新位置对 Agent 无意义。正确做法：

- **文件不动**：保留在 skill 的 `references/hermes/` 内
- **用 `.gitignore` 排除**：`echo 'references/hermes/' >> .gitignore`
- **从 Git 跟踪中移除**：`git rm --cached references/hermes/*.md`
- 结果：文件本地可用（Agent 可读），开源仓库不泄露

## 参考文件

- `references/checklist-template.md` — 可复制的合规检查清单模板
- `references/github-release-workflow.md` — GitHub Actions 自动发布工作流模板 + 常见陷阱
