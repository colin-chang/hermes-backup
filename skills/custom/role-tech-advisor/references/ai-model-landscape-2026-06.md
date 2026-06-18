# AI 模型编程能力全景（2026-06-01 快照）

> 数据来源：LLMReference、Anthropic 官方、Labellerr、腾讯云实测、搜狐四强横评、Lushbinary M3 Guide  
> 下次更新时务必先查最新版本号——模型更新以天为单位

---

## Claude Opus 4.8（2026-05-28 发布）

- SWE-bench Pro: 69.2%（vs 4.7 的 64.3%）
- SWE-bench Verified: 88.6%
- Terminal-Bench 2.1: 74.6%
- OSWorld-Verified: 83.4%（Computer Use 最强）
- GPQA Diamond: 93.6%
- USAMO 2026: 96.7%（最大跃升）
- 新特性：Dynamic Workflows（并行子 Agent 编排）、Effort Control（Low~Max 五档）、Fast 模式降价 3×
- 价格：$5/$25 per M tokens（Fast: $10/$50）
- 已知降级：Prompt 注入防御从 6.0%→9.6%

## Claude Sonnet 4.6（2026-02-17，最新正式 Sonnet）

- SWE-bench Verified: 79.6%
- 价格：$3/$15 per M tokens
- 独有能力：Computer Use、Parallel Agents
- Sonnet 4.7/4.8 无官方发布，仅有泄漏传闻

## MiniMax M3（2026-06-01 发布，⚠️ 数据为厂商自报）

- SWE-bench Pro: 59.0%
- Terminal-Bench 2.1: 66.0%
- BrowseComp: 83.5
- 上下文：1M（MSA 稀疏注意力，9x 更快 prefill）
- 多模态：文本+图像+视频输入
- 价格：$0.30/$1.20（促销）/ $0.60/$2.40（标准）
- 开放权重（商业许可有限制）

## GLM 5.1（2026-04-10 发布）

- SWE-bench Pro: 58.4%
- Terminal-Bench 2.0: 63.5
- Chatbot Arena: 1472
- Code Arena Elo: 1530（全球第三）
- 上下文：200K
- 架构：MoE 754B/40B active
- 价格：$0.98/$3.08 per M tokens
- 优势：源码理解深度、长程 Agent 8 小时连续工作
- 痛点：服务稳定性（429）、涨价后性价比淡化

## DeepSeek V4 Pro（2026-04-24 发布）

- SWE-bench Pro: 55.4%
- Terminal-Bench 2.0: 67.9
- GPQA Diamond: 90.1%
- HLE: 37.7%
- 上下文：1M（CSA+HCA 混合注意力）
- 架构：MoE 1.6T/49B active
- 价格：$0.43/$0.87 per M tokens（最低）
- MIT 协议
- 优势：STEM 推理、性价比、1M 上下文
- 痛点：预览版不稳定、大文件处理弱、SWE-bench 垫底

---

## 编程能力总排名

| 梯队 | 模型 | 关键指标 | 阵营 |
|------|------|---------|------|
| S | Claude Opus 4.8 | SWE-bench Verified 88.6% | 闭源 |
| A | Claude Sonnet 4.6 | SWE-bench Verified 79.6% | 闭源 |
| B+ | MiniMax M3 | SWE-bench Pro 59.0% ⚠️ | 开源 |
| B | GLM 5.1 | SWE-bench Pro 58.4% | 开源 |
| B- | DeepSeek V4 Pro | SWE-bench Pro 55.4% | 开源 |

## 性价比排名

DeepSeek V4 Pro ($0.87) ≫ M3 促销 ($1.20) > Sonnet 4.6 ($15) ≫ Opus 4.8 ($25)

国产开源模型价格是 Claude 的 1/20~1/30。

---

## ⚠️ MiniMax M3 在 Hermes Agent 中的已知问题

### 工具调用（Function Calling）不兼容

M3 的 OpenAI 兼容层有历史遗留 Bug（M2/M2.5 时代即存在），导致在 Hermes 中**无法正常发起工具调用**：

| 缺陷 | 表现 | 影响 |
|------|------|------|
| tool_call_id 格式非标准 | OpenAI 要求 9 位字母数字，MiniMax 返回函数名+索引等非常规字符串 | Hermes 工具调度器 ID 校验失败 |
| JSON arguments 格式错误 | 未转义引号、格式不规范 | JSON parser 抛异常 |
| XML/纯文本回退 | 工具调用被输出为 XML 或纯文本而非 `tool_calls` JSON | Hermes 看不到 tool_call，误认为模型在说人话 |

**影响范围**：M3 在 Hermes 中**只能用于纯文本任务**（auxiliary 任务：mcp、session_search、skills_hub 等），**不能作为主模型**（主模型必须能调用工具）。

**缓解方案**：
- 等待 MiniMax 修复 OpenAI tool_call 兼容性（关注 GitHub Issues）
- 或等 ZenMux/Hermes 添加 MiniMax 原生 provider（原生 tool calling 格式正常）
- 纯文本辅助任务可继续使用 M3

### 上下文窗口架构：512K 保证 vs 1M 上限

M3 使用 MSA（MiniMax Sparse Attention），上下文分为两段：

| 区间 | 注意力模式 | 信息保真度 | 定价 |
|------|-----------|-----------|------|
| ≤512K | **全密集注意力**（标准 Transformer） | 100% 完美 | $0.60/M |
| 512K~1M | **稀疏注意力**（KV-block Top-k 选择） | 可能丢失多跳推理 | $1.20/M（限量） |

**Hermes 配置建议**：`context_length: 512000`，将模型锁定在最高质量区。

**对比 DeepSeek V4 Pro**：V4 从头到尾都是 CSA+HCA 混合注意力（CSA 每 4 token 压缩 + HCA 每 128 token 压缩），没有质量分界线，1M 上下文行为一致可预测。KV Cache 仅 ~2% 标准架构，FLOPs 为 V3 的 27%。
