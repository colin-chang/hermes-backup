# MiniMax M3 × Hermes Agent 集成状态

> 最后更新：2026-06-08 | PR #37152 仍 OPEN

## 模型能力

| 维度 | 状态 |
|------|------|
| Tool Calling / Function Call | ✅ 官方支持（OpenAI 兼容 + Anthropic SDK） |
| Interleaved Thinking | ✅ 原生支持 |
| 1M 上下文 | ✅ MSA 稀疏注意力 |
| 官方文档 | `platform.minimaxi.com/docs/guides/text-m3-function-call` |

## Hermes 已知问题

### 问题根因

MiniMax API 已弃用 `max_tokens`，要求改用 `max_completion_tokens`。Hermes 的 `_max_tokens_param()` 只对 OpenAI/Azure/GitHub Copilot 发 `max_completion_tokens`，对 custom provider（包括通过 ZenMux / OpenClaw 等代理访问 MiniMax）仍发已弃用的 `max_tokens`。

### 影响表现

```
Hermes → max_tokens（弃用参数）
MiniMax → 使用很小的默认输出上限
Tool Call JSON 参数被截断 → 破损 JSON
message_sanitization.py → 替换为 {} → 工具调用失败
```

日志特征：
```
WARNING agent.message_sanitization: Unrepairable tool_call arguments
for execute_code — replaced with empty object
```

### GitHub 追踪

- **Issue**: [#37151](https://github.com/NousResearch/hermes-agent/issues/37151) — `_max_tokens_param should use max_completion_tokens for MiniMax models`
- **PR**: [#37152](https://github.com/NousResearch/hermes-agent/pull/37152) — `fix(agent): use max_completion_tokens for MiniMax`（**OPEN，未合并**）
- **标签**: `P2` `type/bug` `provider/minimax` `comp/agent`
- **修复量**: 2 文件，+23 行

### 临时 Workaround

在 `config.yaml` 的 `custom_providers` 中给 MiniMax 模型显式设置 `max_tokens`：

```yaml
custom_providers:
  - name: zenmux
    # ...
    models:
      minimax/minimax-m3:
        context_length: 512000
        max_tokens: 131072    # 官方推荐 128K，避开截断
```

> 即使 Hermes 发的仍是 `max_tokens`（非 `max_completion_tokens`），值够大就不会触发 MiniMax 的小默认上限。

### 影响范围

- 不做工具调用的纯文本对话 → 不受影响
- 只做短 JSON 参数的工具调用（如简单搜索） → 可能不受影响
- 长代码片段的工具调用（如 `execute_code`、`write_file`） → 高概率截断

## 补充：MiniMax M3 作为主力模型的注意事项

1. Reasoning 风格 verbose — 每轮 tool call 前有长思考，token 消耗高
2. Reddit 上有反馈 M3 在 Hermes 中 "completely unpredictable"（部分场景行为不稳定）
3. 建议先在小范围测试，确认稳定后再切主力
4. 通过 ZenMux 代理访问时，确认 ZenMux 是否正确转发 `max_completion_tokens`
