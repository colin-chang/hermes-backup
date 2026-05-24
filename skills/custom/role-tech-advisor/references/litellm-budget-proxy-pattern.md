# liteLLM 预算代理模式

> 为 LLM API 接入轻量计费中间层的可复用模式。
> 适用场景：有固定预算（赠金/优惠券），需要实时拦截避免超额消费。

## 核心架构

```
客户端 → FastAPI 代理 (:8899) → liteLLM SDK → 上游 API (Vertex/OpenAI/...)
              │
              ├─ 优惠券账本 (JSON 文件)
              ├─ FIFO 消费策略（先到期先扣）
              └─ 超预算 → HTTP 402
```

## 关键组件

### 1. store.py — 优惠券账本

数据模型：
```python
@dataclass
class Coupon:
    id: str            # 唯一标识
    amount: float      # 面额
    remaining: float   # 剩余额度
    expires_at: str    # ISO 过期时间

@dataclass  
class Store:
    coupons: list[Coupon]
    adjustments: list[Adjustment]  # 审计记录
```

核心规则：
- **多券叠加**：总可用 = sum(未过期券.remaining)
- **FIFO 消费**：优先消耗最早到期的券
- **到期自动作废**：`expired` 属性实时判断，不依赖 cron
- **余额校正**：`adjust()` 支持正负值，有审计记录
- **调用历史**：`store_history.jsonl` 逐行追加，保留最近 200 条

⚠️ 时区陷阱：`datetime.fromisoformat()` 返回 offset-naive，需 `.replace(tzinfo=timezone.utc)` 后再与 `datetime.now(timezone.utc)` 比较。

### 2. proxy.py — FastAPI 代理

端点设计：
| 方法 | 路径 | 说明 |
|------|------|------|
| `POST` | `/v1/chat/completions` | OpenAI 兼容，含预算拦截 + 模型白名单 |
| `GET` | `/usage` | 优惠券汇总 + 每张券详情 |
| `GET` | `/coupons` | 同 usage |
| `POST` | `/coupons/add` | 添加优惠券 `{amount, expires_at, description}` |
| `POST` | `/coupons/adjust` | 余额校正 `{amount, reason}` |
| `DELETE` | `/coupons/{id}` | 删除优惠券 |
| `GET` | `/health` | 健康检查 + 模型列表 |

**模型白名单**：`config.json` → `models: [...]` 字段控制，不在白名单的模型返回 400。

### 3. liteLLM 集成要点

```python
# 调用
response = litellm.completion(
    model="vertex_ai/gemini-3.1-flash-lite",
    messages=[...],
    vertex_project="...",
    vertex_location="global",
)

# 计费（自动匹配 Vertex AI on-demand 定价）
cost = litellm.completion_cost(completion_response=response)

# ⚠️ 关键：litellm 返回 ModelResponse 对象，不是 dict！
resp_dict = response.model_dump()  # 转 dict 再取 usage/choices
```

### 4. Hermes 接入

在 `~/.hermes/config.yaml` 添加（block-style YAML，共 13 个模型）：
```yaml
custom_providers:
  - name: vertex-budget
    base_url: http://localhost:8899/v1
    api_key: noop
    model: gemini-3.1-flash-lite
    models:
      gemini-3.5-flash:
        context_length: 1048576
      gemini-3.1-flash-lite:
        context_length: 1048576
      gemini-3.1-pro-preview:
        context_length: 1048576
      gemini-3.1-pro-preview-customtools:
        context_length: 1048576
      gemini-3-flash:
        context_length: 1048576
      gemini-2.5-pro:
        context_length: 2097152
      gemini-2.5-flash:
        context_length: 1048576
      gemini-2.5-flash-lite:
        context_length: 1048576
      gemini-2.5-flash-live-api:
        context_length: 1048576
      gemini-2.0-flash:
        context_length: 1048576
      gemini-2.0-flash-lite:
        context_length: 1048576
      gemini-1.5-pro:
        context_length: 2097152
      gemini-1.5-flash:
        context_length: 1048576
```

### 5. Docker 部署

```dockerfile
FROM python:3.11-slim
# ... 标准 FastAPI 部署 ...
ENV HOST=0.0.0.0  # ⚠️ 必须：容器内 bind 127.0.0.1 会导致端口映射失效
```

`docker-compose.yml` 关键配置：
- 端口映射：`"8899:8899"`
- 数据持久化：`./data:/app/data`
- 凭证只读挂载：`./key.json:/app/key.json:ro`
- 环境变量注入：`HOST=0.0.0.0`、`GOOGLE_APPLICATION_CREDENTIALS`

## 已知陷阱

1. **liteLLM ModelResponse 非 dict**：`resp.get("usage")` 返回 `None`，必须 `.model_dump()` 先转 dict
2. **datetime 时区比较**：offset-naive vs offset-aware 导致 `TypeError`，必须标准化为 UTC
3. **Docker 127.0.0.1 vs 0.0.0.0**：FastAPI 默认 bind `127.0.0.1` 在容器内无法被宿主机端口映射访问
4. **模型名前缀**：liteLLM 需要 `vertex_ai/` 前缀，而对外暴露的 API 用裸模型名——在 `proxy.py` 内部拼接前缀
5. **凭证路径**：Docker 内路径与宿主机不同，通过 volume mount + 环境变量解耦
6. **数据持久化路径陷阱**：`store.py` 默认 `STORE_PATH` 指向 `/app/store.json`，但 volume 挂载在 `/app/data/`。数据写入容器根目录重启即丢。修复：默认路径改为 `data/store.json`，启动时 `mkdir(exist_ok=True)` 确保目录存在。
7. **YAML 示例用 block style**：`custom_providers.models` 一律用 `key:\n  context_length: N` 而非 `key: {context_length: N}`。用户配置文件用 block style，教程示例必须匹配。
