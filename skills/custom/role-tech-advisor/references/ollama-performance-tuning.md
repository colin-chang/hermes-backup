# Ollama 本地模型性能调优指南

> 基于 M2 Pro + 32GB 实测数据，适用于 Apple Silicon Mac。

## 核心原理

### Prefill 是 Apple Silicon 上本地推理的头号瓶颈

- **Prefill（Prompt 处理）**：纯 CPU/ANE 密集型，Apple Silicon 没有独立 GPU → 是大模型的阿喀琉斯之踵
- **Generation（Token 生成）**：相对快，M2 Pro 可达 20-30 tok/s
- **KV Cache 预分配**：上下文长度直接决定内存占用量和 prefill 延迟

实测数据（qwen3.5 9.7B Q4_K_M）：

| num_ctx | Prefill 速度 (12 tok prompt) | 影响 |
|---------|------------------------------|------|
| 262,144 (默认) | **4 tok/s** | 聊天都卡 |
| 16,384 | 53 tok/s | 基本流畅 |
| 4,096 | 56 tok/s | 快但上下文短 |

长 prompt 场景（qwen2.5-coder 7.6B，20K diff）：

| num_ctx | Prefill 耗时 | 总耗时 |
|---------|-------------|--------|
| 32,768 (默认) | 82.8s | 88.1s |
| 4,096 | 12.4s | 15.3s |

### 诊断命令

```bash
# 查看模型实际参数
ollama show <model>          # context length / quantization / parameters

# 性能测试（模拟实际场景）
curl -s http://localhost:11434/api/generate -d '{
  "model": "qwen2.5-coder:latest",
  "prompt": "<你的真实 prompt>",
  "stream": false,
  "options": {"num_predict": 50}
}' | python3 -c "
import json,sys; d=json.load(sys.stdin)
print(f'Prompt: {d[\"prompt_eval_count\"]} tok / {d[\"prompt_eval_duration\"]/1e9:.1f}s = {d[\"prompt_eval_count\"]/(d[\"prompt_eval_duration\"]/1e9):.0f} tok/s')
print(f'Gen: {d[\"eval_count\"]} tok / {d[\"eval_duration\"]/1e9:.1f}s = {d[\"eval_count\"]/(d[\"eval_duration\"]/1e9):.0f} tok/s')
print(f'Total: {d[\"total_duration\"]/1e9:.1f}s')
"
```

## 优化方案：Modelfile 创建优化版模型

### Docker 式分层机制

Ollama 的 `ollama create` 完全复用了 Docker 镜像的分层设计：

- 模型权重（GGUF）存在 `~/.ollama/models/blobs/sha256-xxx`
- Manifest（JSON）存在 `~/.ollama/models/manifests/registry.ollama.ai/library/<模型名>/<tag>`
- 创建新 tag 时，权重层完全复用（digest 一致 → 不占额外磁盘）
- 只新增一个 35-100 字节的 params 层包含 `num_ctx` 等参数

### Modelfile 模板

```dockerfile
FROM qwen3.5:latest
PARAMETER num_ctx 8192       # 上下文窗口（最大瓶颈参数）
PARAMETER num_predict 256    # 最大输出 token 数
PARAMETER temperature 0.1    # 降低随机性，适合代码/Agent 场景
SYSTEM "You are a coding assistant. Output ONLY what is requested. Be extremely concise."
```

### 不同场景的推荐配置

| 场景 | num_ctx | num_predict | 模型选择 |
|------|---------|-------------|---------|
| Git commit message | 4096 | 128 | qwen2.5-coder (7.6B) |
| Agent 多步操作 | 4096 | 256 | qwen2.5-coder (7.6B) |
| 日常聊天 | 16384 | 2048 | qwen3.5 (9.7B) |
| 长文档分析 | 32768 | 4096 | qwen3.5 (9.7B)，预期较慢 |

## VS Code Copilot 集成

### 日志位置

```
~/Library/Application Support/Code/logs/<日期>/window<编号>/exthost/GitHub.copilot-chat/GitHub Copilot Chat.log
```

关键日志行格式：
```
ccreq:<id>.copilotmd | <status> | <model> | <ms>ms | [copilotLanguageModelWrapper]
```

Status 含义：
- `success` — 正常
- `length` — **响应被 Copilot 拒绝**（输出过长，触发 Summarizer 崩溃 `Response too long`）
- 无 status（error 行）— 模型请求超时或失败

### settings.json 配置

```json
"github.copilot.chat.models": [
    {
        "name": "qwen2.5-coder:agent (Agent模式)",
        "vendor": "ollama",
        "family": "qwen2.5-coder",
        "version": "agent",
        "maxInputTokens": 4096,
        "maxOutputTokens": 256
    }
]
```

### 已知限制

1. **Agent 模式不适合本地模型**：Agent 操作需要多次串行模型调用，每步 16-21s，5 步 = 80-100s。云模型每步 1-3s。建议 Agent 操作用云模型，简单对话用本地模型。
2. **Summarizer 崩溃**：Copilot 内部的对话摘要器对本地模型输出长度敏感，`num_predict` 超过 512 容易触发 `Response too long` 错误。
3. **SYSTEM prompt 可能被覆盖**：VS Code Copilot 通过 API 调用时会传入自己的 system prompt，Modelfile 中的 SYSTEM 不一定生效。但 `num_predict` 和 `num_ctx` 参数始终生效。

### 当前本地模型清单（Colin's Mac）

```
qwen2.5-coder:agent   → Agent模式 (4096 ctx, 256 tok)
qwen2.5-coder:commit  → Git提交  (4096 ctx, 128 tok)
qwen3.5:agent         → Agent模式 (8192 ctx, 256 tok)
qwen3.5:chat          → 日常对话 (16384 ctx, 2048 tok)
```
