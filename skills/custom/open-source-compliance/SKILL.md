---
name: open-source-compliance
description: 开源项目合规化检查清单 — 从私有项目到 GitHub 公开仓库的完整流程。涵盖凭证脱敏、LICENSE/SECURITY/PRIVACY 文档、.gitignore 审查、双语 README、泄漏扫描。
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
  - config.example.json
---

# 开源项目合规化

将私有项目发布到 GitHub 前的合规化检查流程。

## 检查清单

### 1. 凭证脱敏

- [ ] **扫描硬编码凭证**：`grep -rn 'private_key\|api_key\|secret\|password\|token' --include='*.py' --include='*.js' --include='*.json' --include='*.yml'`
- [ ] **项目 ID 脱敏**：将 GCP/AWS 项目 ID 替换为 `your-project-id` 等占位符
- [ ] **config.json → config.example.json**：真实配置加入 `.gitignore`，提供脱敏示例文件
- [ ] **密钥文件排除**：确保 `.gitignore` 覆盖密钥文件名（注意：同名目录也要排除，如 `vertex-key.json/`）
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
```

### 6. GitHub 推送

```bash
# 首次推送
gh repo create RepoName --public --source . --push --description "..."

# 或已有仓库
git remote add origin git@github.com:user/RepoName.git
git push -u origin main
```

## 常见陷阱

### 1. 密钥文件是目录而非文件

某些工具或脚本可能将 `key.json` 创建为目录（空目录占位），`.gitignore` 的 `key.json` 规则只排除同名文件。需加 `key.json/` 排除目录。

### 2. 全局 select/input 样式含敏感字段

表单样式中的 `input, textarea, select` 可能影响非表单页面的共享组件（导航栏下拉框）。用 `:not()` 排除。

### 3. test_*.py 中硬编码项目 ID

测试脚本常包含真实 GCP/AWS 项目 ID，脱敏时容易遗漏。

### 4. config.json 只排除不够

仅将 `config.json` 加入 `.gitignore` 不够——如果文件已被 Git 跟踪，`.gitignore` 不生效。需先 `git rm --cached config.json` 再 commit。

## 参考文件

- `references/checklist-template.md` — 可复制的合规检查清单模板
