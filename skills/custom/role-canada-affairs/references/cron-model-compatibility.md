# Cron 任务模型兼容性测试

> 记录在加拿大移民日报 cron 任务中实际测试过的模型表现。
> 测试场景：cron job `2e081401e374`，包含工具调用、网页抓取、dokobot 等完整流程。
> 测试时间：2026-06-01

## 已知兼容模型

| 模型 | 工具调用 | API 次数 | 输出质量 | 备注 |
|------|---------|---------|---------|------|
| `bytedance/doubao-seed-2.0-pro` | ✅ 正常 | ~10 次 | 2239 字符完整报告 | 稳定可用，budget 友好 |
| `anthropic/claude-sonnet-4.6` | 未实测 | — | — | 技能推荐模型，推理能力最强 |

## 已知不兼容模型

| 模型 | 问题 | 复现次数 |
|------|------|---------|
| `minimax/minimax-m3` | 不执行工具调用（tool_turns=0），直接返回垃圾文本后就 stop。两次输出分别是 `]<]minimax[>[`（13字符）和 `]<]minimax[>[<tool_call>`（38字符）。system prompt 中的工具调用指令完全被忽略。 | 2/2 |

## 排查方法

检查模型是否在 cron 环境中正常工作的步骤：

```bash
# 1. 查看 cron 输出文件
ls -lt ~/.hermes/cron/output/2e081401e374/ | head -3

# 2. 检查是否输出了完整的报告标题
grep "📋 加拿大移民动态日报" ~/.hermes/cron/output/2e081401e374/<最新文件>

# 3. 查看 agent.log 中的 API 调用次数和工具使用
grep "cron_2e081401e374" ~/.hermes/logs/agent.log | grep "conversation_loop: Turn ended"

# 正常：api_calls > 5, tool_turns > 3
# 异常：api_calls = 1, tool_turns = 0
```
