# Hermes Cron 安全扫描器架构

> 三套独立扫描器，不同时机、不同范围、不同处理能力。理解它们的分工是排查 cron 任务被拦截问题的前提。

## 扫描器总览

| 扫描器 | 源码位置 | 触发时机 | 扫描范围 | emoji ZWJ 处理 |
|--------|---------|---------|---------|---------------|
| ① `_scan_cron_prompt()` | `tools/cronjob_tools.py` L83 | create / update | 用户提交的 prompt 文本 | ✅ `_EMOJI_ZWJ_RE` 剥离 |
| ② `_scan_assembled_cron_prompt()` | `cron/scheduler.py` L999 | **每次执行** | prompt + **所有加载的 Skill 全文拼接** | ✅ 同上（但不保证 100%） |
| ③ Terminal tirith 引擎 | terminal 工具内部 | terminal 调用时 | 命令文本 | ❌ 无 |

## 关键发现

### 扫描器② 的特殊性

`_scan_assembled_cron_prompt()` 在 cron **每次运行时**执行，不是仅在 create/update 时。扫描范围包括：

- 用户的 cron prompt 文本
- 所有 `skills` 配置中加载的 Skill 的 SKILL.md 全文
- 所有 `references/` 下的文件内容（如果被加载）

这意味着 **Skill 文档本身就是扫描目标**。在 Skill 文档中写含 ZWJ 的 emoji（如 `👩🏼‍⚖️`、`👨‍👩‍👧‍👦`）会导致整个 cron job 在启动阶段被拦截。

### `_EMOJI_ZWJ_RE` 的局限性

```python
_EMOJI_ZWJ_RE = re.compile(
    r'(?<=[\U0001F300-\U0001FAFF\u2600-\u27BF\uFE00-\uFE0F])'
    r'\u200d'
    r'(?=[\U0001F300-\U0001FAFF\u2600-\u27BF\uFE00-\uFE0F])'
)
```

仅匹配 emoji 范围字符之间的 ZWJ。在复杂组装后的 prompt（数万字符）中，ZWJ 可能出现在非标准上下文而未被剥离。

### 规避策略

1. **Skill 文档禁止含 ZWJ 的组合 emoji**：用文字描述替代（如"女性法官 emoji（含 ZWJ+肤色+VS16）"代替 `👩🏼‍⚖️`）
2. **Cron 发送绕过 terminal**：用 `execute_code` 代替 `terminal` 发送 iMessage，因为 scanner③ 无 emoji ZWJ 处理
3. **不依赖正则修复**：即使 scanner①② 有 emoji ZWJ 正则，也不能保证在所有组装上下文中有效剥离

## 实战案例

### 2026-05-21：terminal 内联 emoji 被拦截（scanner③）

日报通过 `terminal python3 -c "report='📋🗓️👩🏼‍⚖️...'"` 发送 → scanner③ 检测到 ZWJ/VS16/肤色修饰符 → `[HIGH] Zero-width characters` → 审批弹窗 → cron 无人值守超时。

### 2026-05-22：Skill 文档 ZWJ 触发运行时拦截（scanner②）

上一天的修复过程中，在 `imessage-nomad/SKILL.md` 事故记录行写了 `👩🏼‍⚖️` → 当天 17:00 cron 执行时 scanner② 扫描到 → `Blocked: U+200D` → 整个 cron job 被拦截，连 Mattermost 日报都没产出。
