---
name: tool-selection-strategy
description: "定义信息获取与浏览器操作的工具优先级策略：Web Search → Dokobot 降级链，有 Site Adapter 优先用 BB Browser site CLI，通用交互用 Hermes browser_* 工具。"
version: 1.4.0
metadata:
  hermes:
    tags: [tool-selection, web-search, dokobot, browser-automation, bb-browser, fallback, priority]
---

# 工具选择策略

## 核心原则

**信息获取**和**浏览器自动化**是两条完全不同的任务路径，工具选择必须沿各自路径的优先级链执行。

---

## ⚠️ Agent 行为 vs 引擎机制（关键概念）

本 Skill 描述的「降级链」是 **Agent（LLM）层行为指令**，不是 Hermes 引擎的自动 fallback：

| 层 | 机制 | 说明 |
|----|------|------|
| **引擎层** | Provider 选择 + 错误透传 | `web_search` 调用的后端（如 brave-free）由 config 决定。若 provider 调用失败（HTTP 429/5xx），错误以 `{success: false, error: "..."}` JSON 原样返回给 LLM——**引擎不做 provider 切换或重试** |
| **Agent 层** | tool result 解析 + 降级执行 | LLM 收到 `success: false` 后，**主动**调用 `terminal("dokobot search ...")` 完成降级。这是本 Skill 指导 LLM 执行的行为 |

这意味着：
- `web_search` 返回错误时，LLM 必须自己识别失败并手动执行降级——不会自动发生
- 如果 LLM 没有加载本 Skill 或忽略了 tool result 中的 `success: false`，降级就不会执行
- Brave 免费层配额：2,000 次/月、1 QPS，超限返回 HTTP 429

---

## 路径一：信息获取（只读）

**核心策略：Web Search 发现 URL → Dokobot 读取内容**

> 关键认知：当前环境 `web.search_backend = brave-free`（search-only provider），**`web_extract` 永远会失败**（错误："is a search-only backend"）。因此跳过 `web_extract`，直接从 `web_search` 结果中提取 URL 交给 `dokobot read`。

### 执行流程（强制执行顺序）

| 步骤 | 工具 | 做什么 | 何时跳过 |
|------|------|--------|----------|
| 1️⃣ | `web_search` | 搜索关键词，获取候选 URL 列表 + snippet | — |
| 2️⃣ | 判断 | 阅读 snippet，判断哪些 URL 需要全文 | snippet 已足够回答 → 直接回复，跳过步骤 3 |
| 3️⃣ | `dokobot read --local` | 抓取目标 URL 的完整页面内容 | — |

### 判断是否需要全文（步骤 2 的关键决策）

| 场景 | 处理 | 理由 |
|------|------|------|
| snippet 已包含确切答案（日期、数字、简单事实） | ✅ 直接回答 | 不需要全文 |
| snippet 提示有技术细节/代码/深度分析 | → 步骤 3 | 需要看完整内容 |
| 需要最新信息（政策、新闻、行情） | → 步骤 3 | snippet 可能过时 |

### 降级触发条件（`web_search` 失败时）

- `web_search` 返回零结果或明显不相关的结果
- Brave Search API 返回 HTTP 429（配额超限）/ 5xx（服务不可用）
- `web_search` 返回 `success: false`

### 降级执行方式

```bash
# web_search 失败 → 用 dokobot search 做搜索
dokobot search '搜索关键词' --local

# 目标页面需要登录态 / JS 渲染 → 直接用 dokobot read
dokobot read '<URL>' --local
```

### 例外：有付费 extract provider 时

若后续配置了 `web.extract_backend: firecrawl`（或其他 extract-capable provider），则恢复标准流程：`web_search` → `web_extract` → 失败时才降级 `dokobot read`。但当前环境无此配置，本 Skill 据此优化。

---

## 路径二：浏览器操作

**核心原则：有 Site Adapter 的平台 → BB Browser site CLI 优先；通用交互 → Hermes browser_* 工具**

| 优先级 | 工具 | 适用场景 |
|--------|------|----------|
| 1️⃣ 首选 | `terminal("bb-browser site <platform>/<command>")` | 目标平台有 BB Browser Site Adapter 时，一条 CLI 直接调平台 API（36 平台 103 命令），效率远超手动浏览器操作 |
| 2️⃣ 补充 | Hermes 内置 `browser_*` 工具 | 通用网页交互（导航/填表/点击/截图/JS 执行），以及无 Site Adapter 的平台或需要精细步骤控制的场景 |

### Hermes 内置 browser 工具（首选）

Hermes 已内置 12 个 `browser_*` 工具。浏览器后端有三种模式，按推荐优先级排列：

| 优先级 | 模式 | 登录态 | 配置方式 |
|--------|------|--------|----------|
| 1️⃣ | **BB Browser daemon Chrome CDP** | ✅ profile 同步 | `browser-configure.sh bb-browser` → `BROWSER_CDP_URL` |
| 2️⃣ | `/browser connect` 直连主 Chrome | ✅ 实时共享 | Hermes 会话中执行 `/browser connect` |
| 3️⃣ | 默认 agent-browser（Camofox） | ❌ 独立环境 | 无需配置，Hermes 默认后端 |

**推荐模式 1️⃣**（BB Browser CDP 直连）的优势：
- 无授权弹窗（与 `/browser connect` 的关键区别）
- 独立 Chrome 实例，与日常浏览完全隔离
- Daemon 自动管理生命周期
- 一条命令配置：`~/.hermes/scripts/browser-configure.sh bb-browser`
- 每轮对话自动生效，无需每次 `/browser connect`

> 详见 `references/bb-browser-integration.md` 的「CDP 直连」章节。

工具列表：

- `browser_navigate` — 导航到 URL
- `browser_snapshot` — 获取页面无障碍树快照
- `browser_click` — 点击元素
- `browser_type` — 输入文字
- `browser_scroll` / `browser_press` / `browser_back` — 导航操作
- `browser_vision` — 截图+视觉分析
- `browser_console` — Console / JS 执行
- `browser_cdp` — 原始 CDP 透传（需 `/browser connect`）
- `browser_dialog` — 处理弹窗
- `browser_get_images` — 获取页面图片

这些工具适用于所有通用网页交互场景：填表单、点按钮、截图表、抓动态页面。

> 需要登录态时：在 Hermes 会话中执行 `/browser connect` 直连本地 Chrome CDP，之后 `browser_*` 工具就能操作你的真实浏览器（带 Cookie/登录态）。

### BB Browser site CLI（补充 — 平台数据获取）

BB Browser 的核心差异化价值是 **36 个平台的 Site Adapter 系统**（103 条命令），用真实浏览器的登录态直接调用网站 API：

```bash
bb-browser site twitter/search "AI agent"
bb-browser site zhihu/hot
bb-browser site xueqiu/hot-stock 5
bb-browser site youtube/transcript VIDEO_ID
```

这些命令通过 `terminal` 工具调用。Agent 应在以下场景使用：
- 需要特定平台的数据（社交媒体、开发者社区、金融行情等）
- 目标平台需要登录态才能访问
- 用 Hermes 内置 browser 工具逐步操作太慢时

> ⚠️ **BB Browser v0.13.3 已移除 MCP Server**（`--mcp` flag 不再存在，README 文档过时未同步）。唯一可用的集成方式是 CLI 调用（通过 `terminal` 工具）。详见 `references/bb-browser-integration.md`。

### BB Browser 浏览器自动化命令（谨慎使用）

BB Browser 也有 `open` / `snap` / `click` / `fill` 等浏览器自动化命令，但**与 Hermes 内置 browser 工具高度重叠**。仅在 Hermes 内置工具不可用或特殊场景（如需要 `--openclaw` 模式）时使用。

### 工具选择决策

```
浏览器操作任务？
├── 特定平台数据获取（社交/开发者/金融/视频等）
│   ├── 平台有 BB Browser site adapter？
│   │   → terminal("bb-browser site <platform>/<command>") ← 首选！
│   │      一条命令出 JSON，无需逐步 navigate→snapshot→click
│   └── 无 adapter？
│       → Hermes 内置 browser_* 工具手动操作
│
├── 通用网页交互（填表/点按钮/截图/导航）
│   → Hermes 内置 browser_* 工具
│   → 需要登录态？CDP 直连已配置（BROWSER_CDP_URL）
│
└── 需要带 Cookie 的 HTTP 请求
    → terminal("bb-browser fetch URL --json")
```

---

## 决策流程图

```
任务是什么？
├── 获取信息（只读）
│   ├── 1. web_search 搜索关键词 → 拿 URL 列表 + snippet
│   ├── 2. 判断 snippet 是否够用？
│   │   ├── 够用 → 直接回答（不调用 extract/read）
│   │   └── 不够 → 3. dokobot read --local 抓取目标 URL 全文
│   └── web_search 失败？
│       └── dokobot search '关键词' --local（搜索+阅读一步到位）
│
└── 浏览器操作
    ├── 特定平台数据（36 平台 site adapter）？
    │   → terminal("bb-browser site <platform>/<command>") ← 首选！
    ├── 通用网页交互（导航/填表/点击/截图）？
    │   → Hermes 内置 browser_* 工具（CDP 直连已配置登录态）
    └── 带 Cookie HTTP 请求？
        → terminal("bb-browser fetch URL --json")
```

> **参考文档**：
> `references/hermes-web-search-architecture.md` — Hermes Web Search 引擎层调用链路、Provider 选择逻辑、Brave Free 配额限制、引擎层 vs Agent 层职责边界。
> `references/web-provider-ecosystem.md` — 全部 8 个 Web Provider 的能力矩阵（search/extract/crawl）、config key 三层优先级、典型配置场景。
> `references/closed-platform-search.md` — 小红书/知乎/抖音等封闭平台的搜索模式：用搜索页提取帖子列表，放弃详情页。
> `references/bb-browser-integration.md` — BB Browser 架构、MCP 移除状态、与 Hermes 内置工具的关系矩阵、36 平台 Site Adapter 速查。
> `references/context-optimization.md` — 上下文消耗构成分析、各工具集 token 开销估算、压缩机制与配置调优、诊断工作流。

---

## ⚠️ 常见错误（每次工具选择前必须自查）

1. **🚫 在 search-only provider 环境下调用 `web_extract`** → 当前 `web.backend = brave-free` 不支持 extract。**永远不要调用 `web_extract`**——它会 100% 失败并浪费 ~114 tokens。`web_search` 拿到 URL 后直接 `dokobot read --local`。这是本 Skill 最重要的规则，违反 = 每轮都浪费一次 round-trip。
2. **用 Dokobot 填写表单** → Dokobot 是只读的，应该用 Hermes 内置 `browser_*` 工具
3. **Web Search 失败后直接放弃** → 必须降级到 `dokobot search --local`，不要跳过
4. **🚫 将 BB Browser site CLI 仅当作「备用方案」** → 当目标平台有 Site Adapter 时，`bb-browser site` 应**优先于** Hermes browser_* 工具，因为一条命令直接出 JSON 远比逐步 navigate→snapshot→click 高效。仅在无 adapter 或需要精细步骤控制时才降级到 Hermes browser_*。
5. **误以为引擎会自动降级** → `web_search` 的 Brave 超限/报错只是返回 `success: false` JSON，引擎不做 provider 切换或 dokobot 自动调用。降级是 LLM Agent 的主动行为，不是自动机制。
6. **🚫 web_search 失败后直接调浏览器工具（`browser_navigate` / `browser_cdp` 等）** → **这是最严重的违规**。信息获取路径和浏览器自动化路径是两条独立闭环，永不相交。失败后只能降级 `dokobot search --local` → `dokobot search`（远程），绝不能跨越到浏览器工具。
7. **SPA 页面搜索 vs 详情页差异**：部分 SPA 平台（如小红书）的搜索列表页可以被 dokobot 部分渲染（标题/作者/互动数据），但单条帖子详情页完全依赖 JS 动态渲染 → dokobot 抓取时会跳转到首页。遇到此类场景，优先从搜索列表页提取信息，不要反复尝试打开详情页。
8. **search-only provider 的正确用法**：当前环境 `web.backend = brave-free`（search-only）。`web_search` 用于发现 URL，然后用 `dokobot read --local` 读取内容。**不要在这之间插入 `web_extract`**——它永远失败。如果将来配置了 `web.extract_backend: firecrawl`，再恢复用 `web_extract`。
9. **🚫 误以为 BB Browser 有 MCP Server** → BB Browser v0.13.3 已移除 `--mcp` flag（README 文档过时未同步）。只能用 CLI 模式：`terminal("bb-browser ...")`。不要尝试配置 Hermes MCP 连接 BB Browser。详见 `references/bb-browser-integration.md`。
10. **BB Browser daemon "No page target found"** → daemon 刚启动时 Chrome 实例无 tab。先用 Hermes `browser_navigate` 打开目标页面（通过 BROWSER_CDP_URL 直连 daemon 的 Chrome），之后 site 命令自动复用 tab。不要反复重试 bb-browser open —— daemon 的 tab 管理由 browser_navigate 更可靠地完成。
11. **BB Browser daemon uptime=0s 但 CDP 可达** → daemon 以 on-demand 方式管理 Chrome，uptime 为 0s 是正常的（资源优化）。只要 `curl http://127.0.0.1:9222/json/version` 有响应且 BROWSER_CDP_URL 已配置，browser_* 工具即可正常工作。

> **与 SOUL.md 的关系**：SOUL.md 不再定义具体规则，仅做强制委托——"工具选择必须严格遵守 tool-selection-strategy 和 bb-browser Skill"。本 Skill 是工具选择策略的**唯一权威来源**。此前 SOUL.md 中的具体铁律曾因未同步而过时（声称 web_extract 可用、声称 BB Browser MCP 优先），教训：SOUL.md 不应镜像 Skill 内容，只应做纯引用。
