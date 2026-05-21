# Hermes Plugin 打包规范

> 本文件记录 Hermes 插件开源发布的标准文件结构和文档约定。
> 适用于 `~/.hermes/plugins/<name>/` 下的所有插件项目。

## 必选文件

| 文件 | 用途 | 说明 |
|------|------|------|
| `plugin.yaml` | 插件元数据 | `name` / `version` / `description` / `entry_point` |
| `__init__.py` | 插件入口 | 实现 `register(ctx)` 等钩子 |
| `README.md` | 英文文档 | 面向国际用户 |
| `README.zh-CN.md` | 中文文档 | 面向中文用户 |
| `LICENSE` | 许可证 | MIT / Apache-2.0 / 等 |
| `.gitignore` | Git 忽略规则 | 排除 `__pycache__` / `*.pyc` / `.DS_Store` 等 |

## 可选目录

| 目录 | 用途 | 示例 |
|------|------|------|
| `scripts/` | 配套 Shell 脚本 | `hermes-mattermost-enhancer.sh`（独立可执行的安装/修复脚本） |
| `references/` | API 契约 / 设计文档 | `api-contracts.md` |
| `templates/` | 模板文件 | 配置文件模板 |
| `assets/` | 静态资源 | 截图 / 图标 |

## 文档编辑流程：先中文后英文

> ⚠️ **关键工作流**：编辑文档时，**先改中文版（README.zh-CN.md），等中文定稿后再同步到英文版**。不要在两边同时改——中英来回切换容易导致内容不一致、遗漏修改。用户审阅中文版确认无误后，再一次性同步翻译到英文。

实际操作流程：
1. 所有修改只在 `README.zh-CN.md` 进行
2. 用户审阅中文版、提出修改意见、反复打磨直到满意
3. 中文版定稿后，一次性将全部改动同步翻译到 `README.md`
4. 提交时两个文件一起 commit

## 脚本双语输出规范

所有面向用户的脚本输出消息采用**英语为主、中文为辅**的双语格式。规则：

| 消息类型 | 格式 | 示例 |
|---------|------|------|
| 标题/分区头（较长） | 英语占一行，中文缩进下一行 | `🔍 Checking if your Hermes fully supports Mattermost...`<br>`   （正在检查你的 Hermes 是否完整支持 Mattermost）` |
| 单行结果/标签 | `English text（中文）` | `Approval cards work ✅ (Hermes knows who to DM)（审批卡片能正常发送 — Hermes 知道发给谁）` |
| 交互式提示 | `English question? [Y/n]（中文问句？）` | `Restart now? [Y/n]（是否现在重启？）` |
| help 文本 | `command — English description（中文描述）` | `check — Check if fixes are applied (default)（检查修复是否生效，默认）` |

**核心原则：**
- 英语永远是第一行/第一个括号前的内容
- 中文放在括号内或缩进下一行，作为辅助理解
- `_do_patch()` 的 `label` 参数也遵循此规范：`"Fix: approval card not being delivered（修复「审批卡片收不到」的问题）"`
- 状态消息同样双语：`"already applied ✅, skipping（已经好了，跳过）"` / `"applied successfully ✅（修复成功）"` / `"failed ❌, check if Hermes is properly installed（修复失败，请检查 Hermes 是否正常安装）"`

## 文档写作风格 — 面向小白用户

README 的读者是**普通用户**（非开发者），文档要让读者读完能回答三个问题：

1. **这是什么？**（一句话能说清）
2. **我要不要用？**（看完功能就知道）
3. **怎么用起来？**（跟着步骤 5 分钟搞定）

### 功能描述规范

| ❌ 禁止（技术黑话） | ✅ 正确（用户视角） |
|-------------------|-------------------|
| "Thread root_id Fix — CRT mode root_id correctly points to thread root post" | "Thread 回复跑偏：原来回复会跳到频道里，现在正确出现在 Thread 中" |
| "send_typing Thread Routing" | "正在输入提示：原来 Thread 里等回复却看不到 Typing 标志，现在正确显示" |
| "MEDIA Silent Skip" | "文件缺失不刷屏：原来找不到文件会贴一大段错误信息，现在静默跳过" |

**核心原则：** 说人话、举场景、标截图位。每个功能：
- 先描述**用户会遇到什么问题**（痛点）
- 再描述**安装插件后变成什么样**（改善）
- 用 `> 📸 \`[截图位]\`` 标记照片位置

### 功能与 Bug 修复分开

- **功能表**：用户主动使用的特性（`/model`、`/new`、DM 审批）→ 放前面，详细描述
- **Bug 修复表**：不需要用户操作的自动修复 → 放后面，简单表格（Bug 描述 + 实际影响 + 修复后），不要让用户操心

> ⚠️ **关键原则：Bug 修复表要囊括项目修复的所有 Bug，不论修复方是插件还是配套脚本。**
>
> 常见遗漏：配套脚本修复的 Bug（如 `_progress_reply_to` 路由修复）容易被忽略——因为心理上会按"插件修的 / 脚本修的"做分类，忘记脚本修复同样是项目价值的一部分。用户不关心 Bug 是谁修的，只关心 Bug 修没修。编写 Bug 表时，对照配套脚本的每个 patch，确保每一条都在表中有对应的 Bug 条目。
>
> **区分 Typing 标志 vs 工具链进度**：这是两个不同的 Bug，容易混淆但绝不能合并。
> - **Typing 标志**（"Hermes 正在输入..." 三个点）— 用户发送消息后、AI 开始思考时的指示器。插件 `adapter.py` 覆写 `send_typing()` 修复。
> - **工具链进度**（多步任务的中间提示："正在搜索..."、"正在读文件..."）— AI 调用多个工具时每一步的进度反馈。配套脚本修改 `run.py` 的 `_progress_reply_to` 修复。
> 两个 Bug 的症状不同（一个在思考阶段、一个在执行阶段）、修复方不同、代码位置不同。Bug 表中各占一行，不能合并。

### 架构解释：用比喻，不写架构图

插件和配套脚本的关系，用大白话比喻解释（"机器人 → 大脑 → 插件=新技能 / 源码=骨架改不了"），不要让用户读 UML 或类继承关系。

### 截图位约定

```markdown
> 📸 `[截图位]` — 描述这张截图应该展示什么
```

描述要具体到"这个截图里应该出现什么元素"，方便后续补图时一眼就知道拍什么。

## 文档净化原则

插件文档是**通用开源文档**，不得包含本机专属信息：

| ❌ 禁止 | ✅ 正确做法 |
|---------|------------|
| "替代原 Patch 6/7/10c" | "修复了 DM 审批 user_id 传入问题" |
| 个人路径（`~/.hermes/scripts/hermes-patches.sh`） | 插件仓库路径（`./scripts/hermes-mattermost-enhancer.sh`） |
| "迁移后 mattermost.py 从 1292→852 行" | 描述功能变化，不涉及行数 |
| 本机 Hermes 配置细节 | 通用配置说明 |

## 配套脚本用户提示规范

配套脚本的所有输出消息必须面向**非技术用户**，让他们能理解"正在检查什么"和"结果意味着什么"。禁止出现技术术语（patch、user_id、Platform.MATTERMOST、已应用/未应用）。

### `check` 输出规范

每条检查项遵循三段式结构：

```
检查项标题（大白话问句）
  OK 分支：场景化描述 + ✅ + 括号内解释对用户意味着什么
  FAIL 分支：场景化描述 + ⚠️ + 括号内解释会有什么影响
```

**对照示例：**

| 元素 | ❌ 旧 | ✅ 新 |
|------|------|------|
| Header | `Mattermost Enhancer Patches 状态` | `🔍 正在检查你的 Hermes 是否完整支持 Mattermost...` |
| 检查项标题 | 无（直接出结果） | `── 检查 ①：审批卡片能不能发到你的私信 ──` |
| OK 消息 | `DM 审批传入 user_id 参数` | `审批卡片能正常发送 ✅（Hermes 知道该把卡片发给谁）` |
| FAIL 消息 | `DM 审批传入 user_id 参数 — 未应用` | `审批卡片可能收不到 ⚠️（Hermes 还不知道该私信谁）` |
| 汇总行 | `状态: 1/2 patches 已应用` | `检查结果：1/2 项通过` |
| 最终建议 | `部分 patches 未应用，建议执行: $0 apply` | `还有一项修复没装完，建议运行：$0 apply` |

### `apply` 输出规范

| 元素 | ❌ 旧 | ✅ 新 |
|------|------|------|
| 开始消息 | `正在应用 Mattermost Enhancer 补丁...` | `正在修复 Hermes 在 Mattermost 里的两个小问题...` |
| 完成消息 | `补丁应用完成！` | `修复完成！` |
| 重启询问 | `是否立即重启 Hermes Gateway 让补丁生效？` | `修复需要重启 Hermes 才能生效。是否现在重启？` |
| 重启成功 | `Hermes Gateway 已重启 ✅` | `已重启 ✅ — 修复现在生效了！` |
| 重启失败 | `重启失败，请稍后手动执行 hermes gateway restart` | `重启失败，请稍后在终端手动执行：hermes gateway restart` |
| 跳过重启 | `请稍后手动执行 hermes gateway restart 让补丁生效` | `已跳过。修复已经安装好了，但需要重启后才能生效。` |

### `_do_patch()` 内部标签

标签本身也需是场景化描述（供 `apply` 和日志使用），不能是技术术语：

| ❌ 旧标签 | ✅ 新标签 |
|-----------|----------|
| `DM 审批传入 user_id 参数` | `修复「审批卡片收不到」的问题` |
| `工具进度消息进入 Mattermost Thread` | `修复「任务进度跑到频道里」的问题` |

内部状态消息同步改为人话：
- `已应用，跳过` → `已经好了 ✅，跳过`
- `已应用` → `修复成功 ✅`
- `应用失败` → `修复失败 ❌，请检查 Hermes 是否正常安装`

### 核心原则

每条消息回答两个问题：
1. **这是在检查/修复什么？**（用场景描述，不用技术术语）
2. **这对我意味着什么？**（括号内解释用户体感）

"patches"、"已应用/未应用"、"user_id"、"Platform.MATTERMOST" 等词**永远不出现在用户可见的输出中**。

## `hermes-patches.sh` 标签规范

`hermes-patches.sh` 的 `_patch_registry` 数组和 `apply_all()` 中的硬编码标签遵循相同规则——每条描述用户**实际看到的问题**，而非代码层面改了什么。

| ❌ 旧标签 | ✅ 新标签 |
|----------|----------|
| `自定义 provider (custom:*) 被误判为非聚合器` | `模型列表太乱：自定义 provider 显示了全部 100+ 模型而不是只显示你精选的几个` |
| `gateway_restart_notification 配置桥接遗漏` | `Gateway 重启提醒关不掉：明明设了 false 重启时还是收到那条消息` |
| `Cron job 存储中文被转义为 \uXXXX` | `定时任务中文变乱码：描述里的汉字全变成 \uXXXX 转义符` |
| `MEDIA 正则过宽导致误匹配非文件路径` | `聊天里莫名出现 (file not found: ...) 垃圾消息` |

**`show_status()` 输出格式：**
```
旧：Hermes Patches 状态检查 → 状态: N total patches 已应用 → 所有 patches 已应用
新：🔍 检查 Hermes 是否已打上所有修复补丁 → 结果：N 项已修复 → 全部修好了 ✨
```

**⚠️ 中文引号陷阱**：标签中不要使用中文双引号 `"..."` —— 在 `_patch_registry` 的 `|` 分隔格式中会被 shell 误解析。改用 `「」` 书名号或重写表述避开引号。本 session 实际遇到了此问题（`"Gateway 即将关闭"` → 改为 `Gateway 重启提醒关不掉`）。

## 项目命名

- GitHub 仓库名应与插件目录名一致
- 推荐格式：`hermes-plugin-<feature-name>`（如 `hermes-plugin-mattermost-enhancer`）
- `plugin.yaml` 中 `name` 字段同步使用该名称

## 安装方式文档规范\n\n插件 README 中的安装步骤必须使用 Hermes 官方命令，不得让用户手动 `git clone` + 编辑 config.yaml。\n\n| ❌ 旧方式 | ✅ 新方式 |\n|----------|----------|\n| `git clone ... ~/.hermes/plugins/xxx` + 手动编辑 `plugins.enabled` | `hermes plugins install owner/repo --enable` |\n\n- `--enable` 自动将插件加入 `config.yaml` 的 `plugins.enabled`，用户无需手动改配置\n- 手动安装方式可保留为备选提示（`> 💡 也可以手动安装：...`）\n- 配套脚本路径必须与 `hermes plugins install` 创建的目录名一致（即 repo name，如 `hermes-plugin-mattermost-enhancer`）\n\n## Bug 编号交叉引用\n\n当 README 的不同章节引用 Bug 表中的编号时（如\"插件 vs 脚本\"章节引用\"Bug #4 和 Bug #5\"），**每次 Bug 表增删条目后必须检查所有交叉引用**。常见错误：\n\n- Bug 表新增条目导致编号后移，但\"插件 vs 脚本\"章节仍引用旧编号\n- Typing 标志（Bug #3）和工具链进度（Bug #5）是两个不同 Bug，交叉引用时容易张冠李戴\n\n## 版本管理

- 插件 `plugin.yaml` 中维护语义化版本（`major.minor.patch`）
- 每次发布前更新 README 中的版本引用
- Git tag 与版本号对齐：`v2.0.0` / `v2.1.0`

## 环境变量文档规范

插件 README 中的环境变量配置段必须与代码实际读取的变量严格一致。编写或修改文档时，对照插件源码和 `.env` 文件做三重校验。

### 信息来源优先级

1. **代码是唯一真相源**：搜索 `_os.getenv(` 列出所有实际读取的变量及其默认值
2. **`.env` 是实际配置**：对照 `.env` 文件确认用户实际填的值
3. **README 是衍生文档**：根据 1 和 2 反推 README 该写什么

### 文档编写规则

| 规则 | ❌ 错误 | ✅ 正确 |
|------|--------|--------|
| **代码读的变量必须写** | 漏掉 `MATTERMOST_CALLBACK_URL`（代码有默认值但 Docker 必须覆盖） | 列出所有 `_os.getenv()` 读取的变量 |
| **区分必填/可选** | 标题写"可选"，实际含必填变量 | 用注释分界：`# ═══ 必填 ═══` / `# ═══ 可选 ═══` |
| **格式与实际文件一致** | 文档用 `export VAR="val"`，实际 `.env` 是 `VAR=val` | 文档格式与用户要编辑的文件格式一致（`.env` 用键值对，不用 `export`） |
| **Docker 特例说明** | "可选" 标签掩盖 Docker 下的必填要求 | 用 `🔧 Docker 部署` / `💻 本地部署` 标注不同场景 |
| **回调 URL 必须解释用途** | 只写变量名不写用途 | 说明这个变量被谁用、在什么流程中起作用 |
| **判断必填/可选的标准** | 以"代码有默认值"为判断依据 | 以"默认值在所有部署场景下都能用吗"为判断依据 |

### 常见遗漏：回调 URL

`MATTERMOST_CALLBACK_URL` 是频率最高的文档遗漏点：

- **代码默认值**：空字符串 → fallback 到 `http://{bind}:{port}/mattermost/callback`
- **为什么容易漏**：看上去"代码能 fallback 所以可选"
- **为什么必须写**：Docker 部署时 fallback 地址（`127.0.0.1`）容器无法访问宿主机，必须显式设为 `http://host.docker.internal:18065/mattermost/callback`
- **结论**：对自部署用户（主要是 Docker），这是**必填项**

## 检查清单

- [ ] `plugin.yaml` 中 `name` 与目录名一致
- [ ] **`config.yaml` 的 `plugins.enabled` 名与 `plugin.yaml` 的 `name` 一致**（⚠️ 高频故障点——名称不匹配 = 插件静默不加载）
- [ ] 首次安装后运行 `hermes plugins list` 确认 Status 为 `enabled`
- [ ] 中英文 README 内容同步、无本机专属信息
- [ ] Bug 表是否覆盖了配套脚本的所有修复项（对照脚本逐一检查，不允许遗漏）
- [ ] 环境变量文档与代码 `_os.getenv()` 调用一一对应，`.env` 格式一致
- [ ] 必填/可选分界明确，Docker 特例已标注
- [ ] 所有文件路径引用指向插件仓库自身（`./scripts/` / `./references/`）
- [ ] 配套脚本独立可执行，不依赖本机其他脚本
- [ ] `LICENSE` + `.gitignore` 就位
- [ ] Git remote URL 与仓库名一致

## ⚠️ 插件名称匹配故障（CRITICAL）

插件不被加载的最常见原因：`config.yaml` 的 `plugins.enabled` 中写的名称与 `plugin.yaml` 的 `name` 字段不匹配。

### 问题场景

| 位置 | 值 | 
|------|-----|
| 目录名 | `mattermost-enhancer` |
| `plugin.yaml` → `name` | `hermes-plugin-mattermost-enhancer` |
| `config.yaml` → `plugins.enabled` | `mattermost-enhancer` ← **不匹配！** |

结果：`hermes plugins list` 显示 `not enabled`，Gateway 使用内置适配器，插件完全静默不生效。

### 诊断

```bash
hermes plugins list | grep -i mattermost
# 如果 Status 列显示 "not enabled"，检查 config.yaml 和 plugin.yaml 的名称
```

### 修复

```bash
hermes plugins enable <plugin.yaml 中的 name>
hermes gateway restart
```

### 预防

- **检查清单首条**：配置名称必须与 `plugin.yaml` 的 `name` 字段严格一致
- **不要依赖目录名**：即使目录名与 `name` 不同，Hermes 也可能不加载（实测行为不确定）
- **安装后验证**：每次 `hermes plugins install --enable` 后运行 `hermes plugins list` 确认状态
- **日志确认**：Gateway 重启后搜索日志确认插件已注册（`grep 'Plugin.*registered' agent.log`）

## ⚠️ Shell registry 字符串中的转义陷阱

在 `_patch_registry` 数组（`|` 分隔格式）中修改标签时，grep pattern 的转义层级极易出错。

### `\"` vs `\\"` 误用

```bash
# ✅ 正确：\" 在 bash 双引号内 = 字面量双引号 "
"gateway/config.py|label|\"gateway_restart_notification\" in platform_cfg"

# ❌ 错误：\\" 在 bash 双引号内 = 字面量 \"（带反斜杠）
"gateway/config.py|label|\\"gateway_restart_notification\\" in platform_cfg"
```

错误版本会让 grep 搜索带反斜杠的 `\"gateway...\"` 而非源码中实际的 `"gateway..."`，导致 check 误报「还没装」。

**验证方法**：跑 `bash -n && ./script.sh check` 确认全部通过。

### 中文引号 `"..."` 干扰

`|` 分隔的 registry 字符串中不要使用中文双引号 `"..."`——会被 shell 误解析为分隔符的一部分，导致 label 被截断。改用 `「」` 书名号或重写表述。本 session 实测：`"Gateway 即将关闭"通知关不掉` → 输出只有 `✓ Gateway`，其余文本被错误路由到 grep pattern 字段。
