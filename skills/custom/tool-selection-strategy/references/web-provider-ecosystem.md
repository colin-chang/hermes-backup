# Hermes Web Provider 生态全景（2026-05 实测 + 源码分析）

> 涵盖全部 8 个内置 provider 的能力矩阵、config key 优先级、以及自建免费 Extract Provider 的成本收益评估。

---

## 一、Config Key 优先级（完整链）

三个 capability 各有独立 key，`web.backend` 作为共享回退：

```
web_search 选 provider:
  web.search_backend    ← 最优先（per-capability）
    ↓ 未设置
  web.backend           ← 共享回退
    ↓ 也未设置
  自动探测（按 legacy 优先级 + 可用性）

web_extract 选 provider:
  web.extract_backend   ← 最优先
    ↓ 未设置
  web.backend           ← 共享回退
    ↓ 也未设置
  自动探测（capability-filtered）

web_crawl 选 provider:
  web.crawl_backend     ← 最优先
    ↓ 未设置
  web.backend           ← 共享回退
```

**关键源码**：`tools/web_tools.py:167-202`（`_get_search_backend` / `_get_extract_backend` / `_get_capability_backend`）

---

## 二、8 个 Provider 能力矩阵

| Provider | 类型 | 认证方式 | Search | Extract | Crawl |
|----------|------|----------|--------|---------|-------|
| **firecrawl** | paid · gateway | `FIRECRAWL_API_KEY` | ✅ | ✅ | ✅ |
| **parallel** | paid | `PARALLEL_API_KEY` | ✅ | ✅ | ❌ |
| **tavily** | paid | `TAVILY_API_KEY` | ✅ | ✅ | ✅ |
| **exa** | paid | `EXA_API_KEY` | ✅ | ✅ | ❌ |
| **searxng** | self-hosted | `SEARXNG_URL` | ✅ | ❌ | ❌ |
| **brave-free** | free · 2k/月 | `BRAVE_SEARCH_API_KEY` | ✅ | ❌ | ❌ |
| **ddgs** | free · 无需 key | `ddgs` Python 包 | ✅ | ❌ | ❌ |
| **xai** (Grok) | paid · OAuth/API | `XAI_API_KEY` 或 OAuth | ✅ | ❌ | ❌ |

**核心约束**：只有 4 个 provider 支持 extract（firecrawl/tavily/exa/parallel），全部付费。

**自动探测优先级**（均未配置 config key 时）：
```
firecrawl → parallel → tavily → exa → searxng → brave-free → ddgs
```
按 capability 过滤——extract 探测时 search-only 的 provider 会被跳过。

---
## 三、典型配置场景

### 场景 A：纯免费（仅 search）← 当前配置

```yaml
web:
  backend: brave-free
```

**运行策略**：`web_search` 用于 URL 发现 → **跳过 `web_extract`**（必定失败）→ 直接用 `dokobot read --local` 读取页面内容。

> 为什么跳过 web_extract：brave-free 是 search-only，`web_extract` 每调用必返回错误。直接走 dokobot 省去每次 ~114 tokens 的失败 round-trip。

### 场景 B：search 免费 + extract 付费
```yaml
web:
  search_backend: brave-free
  extract_backend: firecrawl
```

### 场景 C：全功能付费
```yaml
web:
  backend: firecrawl   # 或 tavily
```

---

## 四、web_extract 失败 → dokobot 降级链

当 `web.backend = brave-free`（search-only）时，`web_extract` 的执行路径：

```
1. _get_extract_backend() → web.backend = "brave-free"
2. brave-free.supports_extract() = False
3. → 触发 "search-only backend" 分支
4. → 返回明确错误：
   "Brave Search (Free) is a search-only backend and cannot extract URL content.
    Set web.extract_backend to firecrawl, tavily, exa, or parallel."
5. LLM 收到 error → 按 tool-selection-strategy 降级到 dokobot read --local
```

**这是设计行为，不是 bug。** brave-free 是 free tier 的代价——只有 search 没有 extract。

---

## 五、自建免费 Extract Provider 评估结论

### 实测数据（Rust Blog + React Docs）

| 路径 | Token 消耗 | 延迟 |
|------|-----------|------|
| dokobot read（当前） | ~3,000-3,175 tokens | 5-15s |
| readability extract（自建） | ~1,514-2,547 tokens | 1-3s |
| 节省 | 20-50% | ~5-10s |

每次 web_extract 失败 + 降级的额外开销：~114 tokens + 1 额外 Agent 轮次。

### 结论：**不建议自建**

1. **不经济**：Token 节省在 DeepSeek 定价下忽略不计，延迟改善对异步 Agent 意义有限
2. **不完整**：永远需要 dokobot 处理 JS/SPA 页面（占比越来越高）
3. **维护负债**：反爬升级、encoding edge case、Cloudflare 拦截等持续消耗精力
4. **当前方案够用**：降级链已是 Hermes 设计的一部分，~114 tokens 开销微不足道

### 如果硬要做：Hybrid Provider

封装降级链到 Provider 内部（HTTP 先试 → 失败静默切 dokobot），让 LLM 永远只看到干净的成功返回。但架构上 dirty（Provider 内调 terminal）。

---

## 六、Provider 插件开发要点

Hermes 支持用户自定义 provider：`~/.hermes/plugins/web/<name>/provider.py`

- 实现 `WebSearchProvider` ABC（`agent/web_search_provider.py`）
- 注册入口：`__init__.py` 中调 `PluginContext.register_web_search_provider()`
- 需启用：`plugins.enabled` 中加入该插件名
- 配置引用：`web.extract_backend: <name>`（name 由 provider 的 `name` property 决定）
- 参考实现：`plugins/web/brave_free/provider.py`（137 行，最简示例）
