---
name: hermes-config-management
description: Hermes 配置文件维护 — config.yaml 安全编辑/注释保护/节点排序 + cron jobs.json 排障与清理
version: 1.0.0
category: custom
---

# Hermes 配置管理

当用户要求分析、修改、还原或优化 `~/.hermes/config.yaml` 或 `.gitignore` 时使用。
也适用于 Hermes 安装后产生的运行时文件追踪/排除需求（如 Desktop 安装产物、Node.js 运行时、缓存目录）。

## 核心原则

### 文件保护机制
- `write_file` 工具对 `config.yaml` 会返回 `"Write denied: ... is a protected system/credential file."`
- **必须使用 `terminal` + heredoc** 来写入配置文件：
  ```bash
  cat > /Users/Colin/.hermes/config.yaml << 'CONFIG_EOF'
  ...content...
  CONFIG_EOF
  ```

### 注释保护
- YAML 标准解析器（PyYAML、ruamel 默认模式）**不保留注释和格式**
- 任何 `load → modify → dump` 操作都会抹掉所有注释
- `hermes config set` 走 patch 模式，不触发此问题
- **配置还原/重构时，始终以 `git show HEAD:config.yaml` 为基底**，只注入真实变更

### 配置最小化原则
- **config.yaml 中只保留偏离内置默认值的配置项**
- 默认值在 `hermes_cli/config.py` 的 `DEFAULT_CONFIG` 字典中定义
- 任何与 `DEFAULT_CONFIG` 值相同的条目都是冗余噪音，必须移除
- Desktop 安装器/更新器会全量写入 150+ 默认值 — 每次更新后都要清理

### 变更分类
分析 diff 时必须区分：
| 类型 | 示例 | 处理 |
|------|------|------|
| 真实内容变更 | key 改名、节点增删、值修改 | 保留 |
| 格式退化 | 缩进变化、注释丢失、空行压缩 | 还原 |
| 尾部空格清理 | `context_pct  \n` → `context_pct\n` | 可接受 |

## 工作流程

### 1. 分析阶段
```bash
git diff config.yaml          # 查看完整差异
git show HEAD:config.yaml     # 获取 committed 版本
read_file config.yaml         # 读取当前版本
```
逐项标记每处 diff 属于「真实变更」还是「格式退化」。

### 2. 重构阶段
- 以 `git show HEAD:config.yaml` 为基底
- 逐项应用真实变更
- 保持原版缩进（block style：`  - item`）
- 保持原版分区注释和行内注释
- 保持原版空行节奏

### 3. 节点排序优化
优化原则（在尊重现有分区的前提下）：
- **使用频率高** → 前置
- **一次性/静态配置** → 后置
- **同分区内按逻辑流排序**（核心→执行→网络→…）
- **辅助模型按字母序**排列子节点

推荐分区内顺序：
```
行为层：agent → terminal → web → compression → sessions → approvals → cron
管理层：platform_toolsets → curator → onboarding → updates
辅助模型：按功能名字母序（approval → compression → curator → … → web_extract）
```

### 4. 验证阶段
```bash
git diff config.yaml  # 确认 diff 只包含预期变更
```

## 常见问题

### Desktop 安装器全量覆写 config.yaml（⚠️ 高频陷阱）

安装 Hermes Desktop 后，安装器会**完全覆写** `config.yaml`，产生以下破坏：

| 破坏项 | 严重性 | 说明 |
|--------|:---:|------|
| **API Key 展开为明文** | 🔴 | `${ZENMUX_API_KEY}` → `sk-ss-...28ad` |
| **所有注释被删除** | 🔴 | 分区标题（`═══` / `───`）、行内注释全灭 |
| **auxiliary 段消失** | 🔴 | 9 个辅助模型配置全部被删 |
| **display 段消失** | 🔴 | 语言/流式/Bell/成本/运行时 Footer 配置全丢 |
| **150+ 默认值写入** | 🟡 | `terminal.docker_*`、`browser.*`、`checkpoints.*` 等全部落盘 |
| **custom_providers 结构改写** | 🟡 | `base_url` → `api`，数组 → 字典 |
| **模型目录自动添加模型** | 🟡 | `model_catalog` 可能自动发现并写入新模型（如 `claude-fable-5`），需评估是否保留 |

**恢复流程：**

1. 立即还原 committed 版本：`git checkout config.yaml`
2. 分析 Desktop 真正改了什么（不是格式退化）：
   ```bash
   # 保存 Desktop 版本做参考
   git stash
   git stash show -p > /tmp/desktop-config.diff
   git stash pop
   ```
3. 只注入真实变更项（通常仅 5-8 行），典型新增项：
   - `credential_pool_strategies: {}`
   - `code_execution.mode: project`
   - `streaming.cursor: " ▉"`
   - `_config_version: 28`
   - 模型目录自动发现的新模型（如 `claude-fable-5`）— **需逐个人工评估是否保留**
   > 📌 **兼容性确认**：旧 `custom_providers` 数组格式仍被 Hermes 完整支持（`get_compatible_custom_providers` 同时读取新旧格式并去重合并）。勿「迁移」到 `providers` 字典格式。详见 `references/custom-providers-backward-compat.md`。
- 快捷入口：`DEFAULT_CONFIG` 从 `hermes_cli/config.py` 第 **883** 行开始（见 `references/default-config-quick-ref.md`）
- ⚠️ 行号随版本漂移，始终以 `grep -n 'DEFAULT_CONFIG = {' hermes_cli/config.py` 定位为准
5. **清除 Desktop 写入的所有默认值**（核心原则：配置只保留非默认值）：
- 对照 `hermes_cli/config.py` 中的 `DEFAULT_CONFIG` 逐一核实
- Desktop 典型写入的默认值（必须移除）：
  - `credential_pool_strategies: {}`
  - `code_execution.mode: project`
  - `streaming.cursor: " ▉"`
  - `approvals.mcp_reload_confirm: true`
  - `onboarding.profile_build: ask`
  - `_config_version: 28`
  - `agent.reasoning_effort: medium`（不在 DEFAULT_CONFIG["agent"] 中，但 `cfg_get` 运行时默认返回 `"medium"`）
  - `mcp_servers.<name>.enabled: true`（`mcp_config.py` 中 `cfg.get("enabled", True)` 默认 True）
- 命令：`grep -n '"<key>":' hermes_cli/config.py` 定位默认值定义行，比对当前值
- **进阶**：部分配置项不在 `DEFAULT_CONFIG` 字典中但有运行时默认值，`grep DEFAULT_CONFIG` 找不到，需额外检查：
  - `cfg_get` 的 docstring 示例（`grep -n 'cfg_get.*<key>' hermes_cli/config.py`）中的 `default=` 参数揭示运行时默认
  - 实际调用点源码（如 `mcp_config.py` 中 `cfg.get("enabled", True)`）
  - 辅助函数行为（如 `hermes_constants.py` 的 `parse_reasoning_effort("")` 返回 `None`，但 UI 和 `cfg_get` 默认 `"medium"`）
   - 快捷入口：`DEFAULT_CONFIG` 从 `hermes_cli/config.py` 第 **803** 行开始（见 `references/default-config-quick-ref.md`）
6. 验证：`hermes config check`

> ⚠️ **验证阶段的预期误报**：移除 `_config_version` 后，`hermes config check` 会报告
> `Config version: 0 → 29 (update available)`。这是**无害的预期行为**——版本号由 Hermes
> 内部自动管理，不写入 config.yaml 才是正确状态。不要因为看到这个提示就把 `_config_version`
> 加回去。

### 工具未按预期禁用

当用户声称「某工具已禁用」但仍被调用时，逐项检查：

1. **`auxiliary` 段是否配置了 provider**：有 provider = 工具可用
2. **`platform_toolsets` 是否包含该工具所属 toolset**——部分 toolset 是**复合集合**：
   - `web` = `web_search` + `web_extract`（两者绑定）
   - 只写 `web_search` → 仅搜索可用，extract 不可用
   - 写 `web` → 两者都可用
3. **`disabled_tools` 段**：确认工具名拼写是否精确

> 📌 **典型案例**：用户以为 `web_extract` 已禁用，但 `auxiliary.web_extract` 配了 provider（`custom:zenmux`），且 `platform_toolsets.mattermost` 写了 `web`（而非单独的 `web_search`），导致 extract 仍在每次对话中被模型调用。

## 参考资料

- `references/protected-files.md` — 配置文件保护机制与绕过方法
- `references/default-config-quick-ref.md` — DEFAULT_CONFIG 结构概览 + 常用键行号速查 + 默认值清单
- `references/custom-providers-backward-compat.md` — `custom_providers` 旧格式向后兼容性代码证据 + 字段映射
- `references/gitignore-patterns.md` — .gitignore 否定模式、通配符合并、冗余检测
- `references/hermes-patches-upstream-check.md` — 本地 patch 上游合入检查方法论 + 当前状态快照
- `references/patch-to-plugin-migration.md` — Shell patch 迁移到 adapter override 的判断框架与检查清单
- `references/cron-jobs-management.md` — Cron jobs 配置与排障：jobs.json 结构、no_agent 字段语义、模型排障流程
- `references/minimax-m3-hermes-integration.md` — MiniMax M3 × Hermes 集成状态：Tool Calling 已知问题、PR #37152 追踪、临时 Workaround
- `references/nodejs-path-conflict.md` — Node.js 版本冲突排障：Desktop 捆绑版 vs 系统版，NODE_MODULE_VERSION 不匹配，qmd MCP 修复流程
- `references/hermes-mcp-node-troubleshooting.md` — MCP 崩溃日志定位 + Node.js ABI 不匹配诊断 + Hermes Desktop 捆绑 Node.js 行为
- `references/busy-input-mode.md` — `display.busy_input_mode` 配置：interrupt/queue/steer 三种消息中断模式详解

## Patch 脚本维护

当涉及 Hermes 源码 patch 时遵循以下原则：

1. **新增 patch 前**先检查上游是否已合入：`git show HEAD:<file>` 对比
2. **迁移 patch 时**合并到目标目录现有脚本，不新建文件 — 见 memory「文件/脚本管理」
3. **删除已合入 patch 时**同步更新注册表 + apply 代码 + check_status + header 注释
4. **patch 分工**：通用 Bug Fix 放 `hermes-patches.sh`，MM 专属（修改 `run.py` 调用方）放 `hermes-mattermost-enhancer.sh`
5. **平台无关≠插件专属**：Gateway 通用层修复（`stream_consumer.py`、`base.py`）即使 Mattermost 触发了发现，也不归插件管 — 放在主脚本

### 输出格式规范

两个 patch 脚本必须统一使用以下格式（以主脚本 `hermes-patches.sh` 的 `show_status` 为准）：

#### check 输出结构（必须严格遵守）

```
═══════════════════════════════════════════════════
  🔍 Checking <target> patches...
     （正在检查 <target> 补丁）
═══════════════════════════════════════════════════

[INFO]  <built-in capability 1> — adapter override（<中文>）
[INFO]  <built-in capability 2> — adapter override（<中文>）

[OK]    Fix: <English>（修复「<中文>」的问题）
[OK]    Fix: <English>（修复「<中文>」的问题）
[WARN]  Fix: <English>（修复「<中文>」的问题）
[OPT]   Fix: <English>（修复「<中文>」的问题）

───────────────────────────────────────────────────
  Shell patches: X/Y required
  （Shell 补丁：X/Y 必需）
───────────────────────────────────────────────────

[OK]    All required patches applied ✨（所有必需补丁已生效）
```

#### 关键约束

| 约束 | 说明 |
|------|------|
| **平铺列表** | 不允许嵌套章节标题（如 `Check ①/②/③`），所有 patch 一行一标签 |
| **前缀体系** | `[OK]`（绿，已应用）、`[WARN]`（黄，未应用）、`[FAIL]`（红，真错误）、`[INFO]`（青，信息）、`[OPT]`（黄，可选未应用） |
| **check 标签** | 只输出 `[前缀] Fix: <描述>`，**不附带** emoji、括号解释、inline 操作建议 |
| **禁止 emoji** | 脚本输出中**完全不使用** emoji（`✅` `⚠️` `❌` 等），状态由颜色前缀传达 |
| **Built-in 前置** | adapter 覆写实现的能力用 `[INFO]` 前缀紧贴标题下方，不计入 Shell patches 计数 |
| **汇总行** | `Shell patches: X/Y required`，不拆分 `+ Z optional` 子计数 |
| **标签格式** | `Fix: <English description>（修复「<Chinese>」的问题）` — 与 apply 的 `_do_patch` label 参数完全一致 |

#### 用户面描述语言

向用户（含开发者）展示状态时，**禁止**描述实现机制（"adapter queries channel members"、"extra API call"、HTTP 细节等），只描述**用户能感知到的行为**：

- ❌ `adapter queries channel members — works but extra API call`
- ✅ `审批能用但慢半拍 — 运行 apply 可修复`
- ❌ `Hermes passes user_id directly, saves 1 API call`
- ✅ `审批直达 — Hermes 直接知道你是谁，一步到位`

#### 单行原则

状态描述 + 修复提示必须合并为一行，**不得**拆成两条 `[OPT]`/`[WARN]`：
- ❌ 第一行描述问题 + 第二行 `→ Run apply`
- ✅ `Fix: ... ⚠️ — run '$0 apply' to fix（修复「...」⚠️ — 运行 '$0 apply' 可修复）`

### Check Pattern 防误报

grep check pattern 必须足够精确，**只匹配 patch 自身的唯一签名**：

- ❌ `not grp["models"]` → 上游 `bool(api_key) or not grp["models"]` 也命中
- ✅ `bool.*api_key.*and not grp["models"]` → 需要 patch 特有的 `bool(api_key) and` 前缀
- ❌ `user_id=source.user_id` → 上游已有多处同名字符串（不同上下文）
- ✅ `user_id=source.user_id.*hasattr` → patch 特有的 `if hasattr(source, 'user_id')` 后缀

**验证方法**：回滚目标文件到上游 (`git checkout <file>`)，逐一跑 grep check——匹配到 0 行才是干净的 pattern。

### `_do_patch` 函数规范

**必须捕获 Python stdout 以区分 APPLIED 和 SKIP**——Python `sys.exit(0)` 对两者相同：

```bash
local output
output=$(python3 - "$file" 2>&1)
local rc=$?
if [[ $rc -eq 0 && "$output" == *"APPLIED"* ]]; then
    ok "$label — applied successfully"
elif [[ $rc -eq 0 && "$output" == *"SKIP"* ]]; then
    ok "$label — skipped, code already matches"
else
    warn "$label — failed"
fi
```

### Heredoc 转义陷阱（⚠️ 高频故障点）

bash `<<'PYEOF'`（单引号 heredoc）中 `\\n` **不会被** bash 解释为换行符，Python 收到的源码是两个字面字符 `\` 和 `n`。Python 再把 `"\\n"` 解析为字面反斜杠+n（两个字符），而非真正的换行符 `\n`。结果 `old in content` 永远为 False，patch 静默 SKIP。

| 写法 | bash 看到 | Python 收到 | Python 解析结果 | 匹配文件换行？ |
|------|----------|------------|---------------|-------------|
| `"line1\\nline2"` | `\\n`（两字符） | `\\n` | `\` + `n`（两字符） | ❌ 永不匹配 |
| `'''line1`<br>`line2'''` | 真实换行 | 真实换行 | `\n`（换行符） | ✅ |

**✅ 正确做法**：Python heredoc 内需要匹配换行的 `old_string` 必须用**三引号多行字符串**（`'''...'''` 或 `"""..."""`），让真实换行直接嵌入，禁止用 `\\n`。

```
# ❌ 坏 — \\n 永远不会匹配文件中的真实换行
old = "line1\\nline2"

# ✅ 好 — 三引号多行，换行从 heredoc 直接传入
old = '''line1
line2'''
```

**故障表现**：`check` 报 WARN（grep 未找到 patch 签名），但 `apply` 报告 `SKIP`（`old in content` 为 False）。表面上代码「看起来」一样，实则补丁从未生效。

**排查方法**：在 Python heredoc 中临时加 `print(repr(content[idx:idx+80]))` 对比 old_string 与文件中实际字符串的 repr。

### Python Patch 防重复条件

Python heredoc 中 `"<substring>" not in content` 防双打条件可能永假（上游其他地方已有同名字符串）：

- ❌ `"user_id=source.user_id" not in content` → 上游 3 处无关匹配，条件永假，patch 永远 SKIP
- ✅ `"user_id=source.user_id if hasattr" not in content` → 只匹配 patch 自身的完整行

**通用原则**：防重复条件必须和 check pattern 使用同样的独特签名。

### Q: 谁/什么操作会抹掉注释？
任何使用标准 YAML 库做 `load → dump` 的工具或脚本。`hermes config set` 不会（它用 patch）。
