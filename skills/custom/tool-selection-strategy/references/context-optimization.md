# 上下文优化指南

## 上下文消耗构成（按 token 占比排序）

每次对话的 system prompt 包含以下固定开销，**每轮都完整发送**（即使有 prefix caching，上下文窗口占用不减免）：

| 组件 | 估计 token | 说明 |
|------|:---:|------|
| **工具定义** | 80K-150K | 30+ 工具 × 各自的完整 JSON Schema + 使用说明。最大头 |
| SOUL.md + 角色系统 | 5K-8K | 角色定义、切换规则、工具选择策略、Computer Use 规则 |
| Skills 列表 | 3K-5K | 80+ skill 的 name + description |
| Memory + User Profile | ~1.5K | 持久记忆 + 用户画像 |
| 加载的 Skill 全文 | 视情况 | 如 hermes-agent ≈ 15K tokens |

## 各工具集 token 消耗估算

| 工具集 | 估计 token | 包含的子工具 |
|--------|:---:|------|
| **browser** 🌐 | ~15K | navigate, click, type, snapshot, scroll, press, back, console, cdp, dialog, vision, get_images |
| **cronjob** ⏰ | ~8K | 全部 action + delivery 模式 + 参数 |
| **computer_use** 🖱️ | ~5K | macOS 桌面控制完整 API |
| **delegation** 👥 | ~5K | batch/单任务 + 全部 toolset 枚举 |
| **execute_code** ⚡ | ~5K | 完整 Python SDK API 文档 |
| session_search | ~4K | 三种查询形态 + FTS5 语法 |
| web | ~3K | web_search + web_extract |
| terminal | ~3K | shell 执行 + background/PTY |
| file | ~2K | read/write/search/patch |
| code_execution | ~3K | Python sandbox |
| image_gen | ~2K | 图像生成 |
| tts | ~2K | 文字转语音 |
| vision | ~2K | 图像分析 |
| 其余（skills, todo, memory, clarify, messaging） | ~1K each | 轻量工具 |

## 压缩机制

Hermes 自动压缩在上下文超过阈值时触发：

```yaml
compression:
  threshold: 0.35      # 超过 35% 上下文窗口时触发（默认 0.50）
  target_ratio: 0.15   # 压缩到当前用量的 15%（默认 0.20）
```

### 典型现象：31% → 4%

当上下文在阈值附近时，一轮超长回复（如加载大 Skill + 详细分析）可能推动超过阈值，触发压缩。压缩后只保留摘要，导致上下文从 31% 骤降到 ~4%。这是正常行为，不是 bug。**降低 threshold 可以避免这种剧烈波动。**

## 诊断工作流

```bash
# 1. 查看当前 token 分布
/usage

# 2. 查看压缩配置
hermes config | grep -A3 "^compression:"

# 3. 查看已启用工具集
hermes tools list

# 4. 调整压缩阈值（避免过山车体验）
hermes config set compression.threshold 0.35
hermes config set compression.target_ratio 0.15
```

## 优化优先级

1. **裁剪工具集**（收益最大）：`hermes tools` 交互式禁用不用的工具
   - 优先关：browser（~15K）、computer_use（~5K）、image_gen（~2K）、tts（~2K）
   - 保留核心：web、terminal、file、skills、memory、session_search、cronjob
2. **下调压缩阈值**：从 0.50 → 0.35，更早触发、更平缓压缩
3. **精简 SOUL.md**：工具选择策略等长段落可抽到独立 Skill 按需加载
4. **按平台禁用 Skill**：`hermes skills config` 关掉当前场景不需要的 skill

## 注意事项

- 工具变更需 `/reset`（新会话）生效——不会在当前会话中应用
- 压缩使用 `auxiliary.compression` 配置的模型（当前：deepseek/deepseek-v4-pro）
- DeepSeek 可能有 prefix caching，但上下文窗口占用不减免
- Memory 块有 2.2K 字符限制，User Profile 有 1.4K 限制，不要超限
