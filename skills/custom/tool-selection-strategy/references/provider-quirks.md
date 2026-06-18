# Provider-Specific Quirks & Known Issues

> 记录各模型提供商与 Hermes 集成时的已知坑和 Workaround。
> 本文件为 `tool-selection-strategy` 的补充——当选择模型时需考虑这些兼容性问题。

---

## MiniMax M3（2026.6 发布）

### Tool Calling 兼容性问题

**症状**：Tool Call 参数被截断（JSON 破损），Hermes 替换为空 `{}`。

**根因**：MiniMax API 已弃用 `max_tokens` 参数，要求用 `max_completion_tokens`。
Hermes 的 `_max_tokens_param()` 对 `custom` provider 仍然发 `max_tokens`，
MiniMax 使用很小的默认输出上限截断长参数。

**日志特征**：
```
WARNING agent.message_sanitization: Unrepairable tool_call arguments
for execute_code — replaced with empty object
```

**Workaround**（零成本）：
```yaml
# config.yaml → custom_providers
models:
  minimax/minimax-m3:
    context_length: 512000
    max_tokens: 131072    # ← 官方推荐值（128K），避开 MiniMax 小默认值
```

**正式修复**：
- Issue: [NousResearch/hermes-agent#37151](https://github.com/NousResearch/hermes-agent/issues/37151)
- PR: [#37152](https://github.com/NousResearch/hermes-agent/pull/37152)（截至 2026.6.8 未合并）
- 修复内容：`run_agent.py:_max_tokens_param()` 对 MiniMax 模型名发送 `max_completion_tokens`

**影响范围**：通过 `custom` provider（如 ZenMux）接入 MiniMax M3 时受影响。
直接使用 MiniMax 官方 provider 路径不受此影响（因为 Hermes 对直连 provider 有专门处理）。

**辅助任务风险**：M3 用于 mcp/session_search/skills_hub 等辅助任务时，
参数通常较短，截断概率低；用于主力模型做复杂 tool call 时风险较高。

---

## 文件维护规则

- 已知 bug 有正式修复（PR 已合并）→ 移除此条目
- 新发现 provider 兼容性问题 → 追加新条目
- 每个条目必须包含：症状、根因、Workaround、修复状态
