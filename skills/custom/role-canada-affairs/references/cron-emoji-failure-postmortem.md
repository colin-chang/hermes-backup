# Cron Emoji 拦截事故复盘

> **日期**: 2026-05-21 ~ 2026-05-22  
> **Cron Job**: `2e081401e374`（加拿大移民日报）  
> **影响**: iMessage 推送连续多日静默失败

## 故障时间线

| 日期 | 发送方式 | 结果 | 原因 |
|------|---------|------|------|
| 5/16-5/19 | `cat > file << 'EOF'`（HEREDOC 写文件） | ✅ 正常 | HEREDOC 不在命令行暴露 emoji |
| 5/20 | `skill_view` 不可用 | ⚠️ 静默跳过 | Subagent 无 tools 加载 skill，放弃发送 |
| 5/21 | `terminal` + `python3 -c` 内联日报 | ❌ 安检拦截 | emoji ZWJ 被误判零宽攻击字符 |
| 5/22 17:00 | Cron 启动阶段被拦 | ❌ 整 Job 被拒 | Skill 文档含 ZWJ emoji → runtime scanner |
| 5/22 多次尝试 | execute_code / HEREDOC 合并调用 | ❌ 多种失败 | execute_code 名字写成 tool 名而非 toolset 名 → 不可用 |

## 三层拦截机制

### Layer 1：Cron Prompt Scanner（create/update 时）
`_scan_cron_prompt()` — 在 cron job 创建/更新时扫描用户提供的 prompt。有 `_EMOJI_ZWJ_RE` 正则剥离 emoji ZWJ。

### Layer 2：Runtime Assembled Prompt Scanner（执行时）⭐ 5/22 17:00 故障根因
`_scan_assembled_cron_prompt()` (`cron/scheduler.py:999`) — cron 执行时，将 **prompt + 所有加载的 Skill 全文** 拼在一起扫描。Skill 文件中的 ZWJ emoji 会被扫到，导致整个 cron job 被拒。

### Layer 3：Terminal 工具级安全扫描（执行时）⭐ 5/21 故障根因
`terminal` 工具执行 `python3 -c` 时会扫描代码内容。日报内联含 ZWJ emoji → 触发 Zero-width characters + Variation selector 检测 → 审批弹窗 → 无人值守超时。

### execute_code — 已解决

根因不是 `check_sandbox_requirements` 检查失败，而是配置写错了名字。`enabled_toolsets` 需要 tool**set** 名（`code_execution`），不是 tool 名（`execute_code`）。`terminal`/`web`/`browser` 碰巧同名所以正常，`execute_code` 是唯一例外。

已修复：`cron/jobs.json` 中 `"execute_code"` → `"code_execution"`。

## 最终修复方案

1. **配置修正**：`cron/jobs.json` 的 `enabled_toolsets` 中 `"execute_code"` → `"code_execution"`
2. **源头清 ZWJ**：模板中 女性法官组合emoji → `⚖️`，所有含 ZWJ 的组合 emoji 替换为基础 emoji
3. **Skill 文档禁 ZWJ**：nomad-imessage 的 SKILL.md 和 references 中不留含 ZWJ 的 emoji
4. **`execute_code` 直接内联发送**：不写文件，日报放 Python 字符串中，一次调用完成，Markdown 原样保留

## 教训

- **Skill 文档会被 runtime 扫描**——写事故记录/代码示例时勿含 ZWJ emoji
- **execute_code 不流向 cron 子代理**——不要依赖 execute_code 做 cron 发送
- **非确定性发送方式很危险**——同一 prompt 模型不同天选不同路径（HEREDOC vs python3 -c）
- **Prompt 必须锁死步骤**——"分两次独立调用"、"严禁合并"、"严禁 python3 -c 内联"必须大写加粗
- **`enabled_toolsets` 不等于子代理工具集**——cron job 配了 execute_code，子代理拿不到
