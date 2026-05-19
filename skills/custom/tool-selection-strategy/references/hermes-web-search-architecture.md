# Hermes Web Search 后端架构（2026-05 源码分析）

## 调用链路

```
web_search tool 调用
  → tools/web_tools.py: web_search_tool()
    → _get_search_backend() 读取 web.search_backend 或 web.backend
    → agent/web_search_registry.py: get_provider(backend) 获取 provider 实例
    → provider.search(query, limit) 执行搜索
    → 返回 JSON: {success: true/false, data/error}
    → 直接透传给 LLM（无引擎层 retry/fallback）
```

## Provider 选择逻辑（`web_search_registry.py::_resolve`）

1. **Explicit config 优先**：`web.search_backend` > `web.backend` > 自动探测
2. **自动探测**：按 `firecrawl → parallel → tavily → exa → searxng → brave-free → ddgs` 顺序选第一个可用的
3. 一旦 provider 被选中并调用，返回值直接透传——不再做 provider 切换

## Brave Free 提供者

- 文件：`plugins/web/brave_free/provider.py`
- 端点：`https://api.search.brave.com/res/v1/web/search`
- 认证：`BRAVE_SEARCH_API_KEY` 环境变量
- 配额：2,000 queries/month, 1 QPS
- 能力：`supports_search()=True`, `supports_extract()=False`
- 错误处理：HTTP 错误 → `{success: false, error: "Brave Search returned HTTP {code}"}`；网络错误 → `{success: false, error: "Could not reach Brave Search: ..."}`
- **无引擎层 fallback**：返回 `success: false` 后不做任何自动切换

## 降级链的实现

| 层 | 行为 | 自动？ |
|----|------|--------|
| Provider 选择 | 启动时按 config/探测选 provider | ✅ 自动 |
| 调用失败 | 返回 error JSON 给 LLM，不做 provider 切换 | ❌ 无自动 |
| dokobot 降级 | LLM 收到 error 后，按 Skill 指令手动调用 `dokobot search/read` | ❌ Agent 手动 |
