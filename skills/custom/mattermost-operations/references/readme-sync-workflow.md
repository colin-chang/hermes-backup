# README 文档同步工作流

> 在插件代码（adapter.py / scripts/*.sh）发生修改后，如何将变更同步到中英文 README。

## 触发条件

- 插件代码有未发布的 commit（`git log <last-tag>..HEAD` 非空）
- 新增/修改/删除 adapter 覆写或 shell patch
- Bug 编号、实现方式、脚本补丁数量发生变化

## 工作流（5 步）

### 第 1 步：提取代码变更

```bash
cd ~/.hermes/plugins/mattermost-enhancer
git diff v<last-version>..HEAD --stat          # 概览
git diff v<last-version>..HEAD -- adapter.py    # adapter 变更
git diff v<last-version>..HEAD -- scripts/      # 脚本变更
```

### 第 2 步：映射变更 → 文档条目

对每条 adapter 变更，判断属于哪类：

| 变更类型 | 是否需要文档 | 示例 |
|---------|-------------|------|
| 新增 public override | ✅ 检查 Bug 表是否覆盖 | `send_multiple_images()` → Bug #10 |
| 新增 private 方法 | ❌ 内部重构，无需文档 | `_build_callback_url()` |
| 方法签名变化 | ✅ 可能影响功能描述 | `_derive_reply_to()` 影响 media 路由 |
| import 清理 / 代码格式 | ❌ 无需文档 | `import os as _os` → `import os` |

对每条脚本变更：

| 变更类型 | 是否需要文档 | 示例 |
|---------|-------------|------|
| 新增 patch | ✅ Bug 表新增条目或扩展描述 | P6 新增 (批量图片) |
| patch 迁移至主脚本 | ✅ 更新 README 的 "已消除" 列表和脚注 | P50/P53/P55 |
| patch 标记为可选 | ✅ 更新 Bug 表的实现方式列 | P1 → "Shell Patch（可选）" |
| patch 移入 adapter | ✅ Bug 表改 "Adapter 覆写"，更新脚本 "内置检查" | WebSocket 心跳 |
| 检查输出变更 | ⚠️ 更新 Step 4 的描述文字 | check 从 4 项→6 项 |

### 第 3 步：脚本 header ↔ README 交叉核对（⚠️ 必做）

这是**最容易被跳过的步骤**，也是 README 与脚本脱节的头号根因。脚本 header 注释是 "活跃 patch" 的**权威数据源**，README Bug 表必须与之对齐。

```bash
# 1. 读取脚本 header 中的「活跃 patch」列表
read_file(path='scripts/hermes-mattermost-enhancer.sh', limit=50)

# 2. 逐条对比 P1-Pn 与 README Bug 表
#    对于每条 Px，在 README 中搜索其描述关键词：
search_files(pattern='Px 的描述关键词', file_glob='README*.md')
```

**对照维度：**

| 脚本 header | README Bug 表 | 不一致时 |
|------------|---------------|---------|
| patch 数量（如 "活跃 patch 6 个"） | Bug 表中 Shell Patch 条目数 | README 扩展脚注或新增条目 |
| patch 描述 (Px label) | Bug 描述的措辞 | 以脚本描述为准对齐 |
| "已消除" 列表 | Bug 表脚注中的 "迁至主脚本" 说明 | 确保数量和内容匹配 |
| "内置检查" 列表 | Bug 表中 Adapter 覆写条目 | 确保每项都有对应 Bug # |

**本步骤发现的常见脱节：**
- patch 新增但 README 无对应 Bug：补充脚注说明（如 P6 批量图片）
- patch 迁移但 README 未更新数量：更新 "插件 vs 脚本" 节
- patch 重编号（如 P5 原=评论合并→现=Session 串台）：全面检查交叉引用

**互补 patch 模式（complementary patch）：**
当 shell patch 修复的是 bundled adapter 中某方法的 Thread 路由，而插件 adapter 已覆写同类单文件方法时，该 patch 与已有 Bug 是**互补**关系而非新增 Bug。处理方式：
- 不分配新 Bug 编号
- 在 Bug 表脚注中说明（如 "P6 修复 `send_multiple_images()`，与 Bug #5 互补"）
- 在 "插件 vs 脚本" 节和 FAQ "不装脚本" 中列出影响

### 第 4 步：编辑中文版

按 `plugin-doc-and-script-conventions.md` 的规则，**只改中文版**：

1. **Bug 表**：增删条目、调整编号、更新实现方式列
2. **"插件 vs 脚本" 节**：更新二者分工描述、补丁数量、上游 PR 链接
3. **Step 4**：更新路径、`check` 输出描述、术语（"修复"→"补丁"）
4. **FAQ**：更新影响范围描述

### 第 5 步：验证 + 同步英文

```bash
# 验证：确保 GitHub 仓库名引用（badge / install 命令）未被误改
search_files(pattern='hermes-plugin-mattermost-enhancer', file_glob='*.md')

# 验证：确保本地 cd 路径全部指向正确目录名
search_files(pattern='cd ~/.hermes/plugins', file_glob='*.md')
```

中文版定稿后，一次性同步翻译到 `README.md`。注意：
- 英文版如已有不同的结构（如 Bug 编号重组），先确认中文版是否要跟随
- 结构差异未解决时，只同步事实性修正（路径、术语），不动结构

## 常见陷阱

### 路径混淆

- **GitHub 仓库名**（`hermes-plugin-mattermost-enhancer`）：用于 badge URL、`hermes plugins install` 命令 → **永远不改**
- **本地目录名**（`mattermost-enhancer`，即 `plugin.yaml` 的 `name` 字段）：用于 `cd` 路径 → 代码安装后的实际目录

### 术语不一

脚本内部统一用 "补丁/patches"，README 面向用户可用 "修复"。但 Step 4 直接引用脚本行为，必须与脚本输出对齐。

### 遗漏重复路径

README 中同一路径可能出现多次（"插件 vs 脚本" 节 + Step 4 节），需用 `replace_all=true` 或逐处查找修复。

### 文件在读取后被修改导致 patch 匹配失败

当 README 在 agent 读取后被其他进程（如后台 restructure）修改时，`patch` 工具的 `old_string` 可能不再存在。症状：patch 返回 success 但文件内容未变（匹配到了错误位置或未匹配）。

**预防：** 在关键 patch 前，先 `read_file` 确认目标文本确实存在。如果文件在短时间内被多次编辑，每轮 patch 后重新 `read_file` 确认结果。

### Bug 编号重组后遗漏交叉引用

当 Bug 表按实现方式重新编号（Adapter #1-5 → Shell Patch #6-10 → 主脚本 #11）时，所有引用旧编号的段落（"插件 vs 脚本"、FAQ、Step 4）必须同步更新。

## 检查清单

- [ ] `git diff` 中的每条 adapter override 在 Bug 表中有对应条目
- [ ] `git diff` 中的每个新增 shell patch 在 Bug 表中有对应条目
- [ ] 脚本 header "活跃 patch" 列表与 README Bug 表完全对齐（数量 + 描述）
- [ ] 脚本 header "已消除" 列表与主脚本修复脚注一致
- [ ] Bug 实现方式列（Adapter/Shell Patch）与实际修复方式一致
- [ ] 所有 `cd` 路径指向本地目录名（非 GitHub 仓库名）
- [ ] Step 4 的补丁数量描述与脚本实际输出一致
- [ ] FAQ 的影响范围描述与 Bug 表标注一致
- [ ] README 简介段落（"💀 这是什么？"/"What Is This?"）不引用已从 Bug 表移除的 Bug（Bug 重组后最常见遗漏）
- [ ] 中英文两版的路径和术语已对齐（或结构差异已记录）
