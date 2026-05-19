---
name: tool-selection-strategy
description: "定义信息获取与浏览器操作的工具优先级策略：Web Search → Dokobot 降级链，BB Browser 优先用于自动化操作。"
version: 1.0.0
metadata:
  hermes:
    tags: [tool-selection, web-search, dokobot, bb-browser, fallback, priority]
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

**优先级链：Web Search → Dokobot**

> 此链是 Agent 层指令——LLM 需主动检测失败并手动降级。

| 优先级 | 工具 | 适用场景 |
|--------|------|----------|
| 1️⃣ 首选 | `web_search` + `web_extract` | 公开信息、新闻、文档、通用搜索 |
| 2️⃣ 降级 | `dokobot read` / `dokobot search` | Web Search 失败、返回空结果、或目标页面需要 JS 渲染/登录态才能查看 |

### 降级触发条件（任一即降级）

- `web_search` 返回零结果或明显不相关的结果
- `web_extract` 无法提取目标页面内容（403、空内容、JS 渲染缺失）
- 目标页面明确需要登录态（如社交媒体私信、内部系统、付费文章）
- 目标页面是 SPA / 动态加载，`web_extract` 只拿到骨架 HTML

### 降级执行方式

```bash
# 优先用 local 模式（免费、无限制）
dokobot read '<URL>' --local

# 如果 local 模式不可用（Chrome 未打开 / bridge 未安装），使用远程模式
dokobot read '<URL>'
```

### 搜索降级

```bash
# Web Search 失败时
dokobot search '搜索关键词' --local
```

---

## 路径二：浏览器自动化（写操作）

**优先级：BB Browser（唯一首选）**

| 优先级 | 工具 | 适用场景 |
|--------|------|----------|
| 1️⃣ 唯一 | BB Browser MCP 工具 | 打开网页、填写表单、点击按钮、下拉选择、截图、批量操作 |

### 适用场景

- 填写并提交表单（登录、注册、搜索框）
- 点击按钮、链接、导航
- 选择下拉菜单、勾选复选框
- 页面截图保存
- 批量页面操作
- 需要 Site Adapter 一键调用的场景（`bb-browser site <name>`）

### 为什么不用 Dokobot 做自动化

Dokobot 是**只读工具**（read / search），不能修改页面、填写表单、点击按钮。自动化操作只能用 BB Browser。

### 为什么不用 Hermes 原生 browser 工具

BB Browser 的 Site 系统提供 36+ 平台的 CLI 化命令，比 Hermes 原生 browser 工具更高效：
- `bb-browser site twitter/search "关键词"` 一条命令完成搜索
- 自动 tab 管理、登录检测
- `bb-browser fetch` 带登录态的 HTTP 请求

对于 Site 系统未覆盖的网站，再使用 Hermes 原生 browser 工具（`browser_navigate` / `browser_click` / `browser_type` 等）。

---

## 决策流程图

```
任务是什么？
├── 获取信息（只读）
│   ├── 先用 web_search / web_extract
│   │   ├── 成功 → 返回结果
│   │   └── 失败/不完整 → 降级到 dokobot read/search
│   └── 目标需要登录态？→ 直接用 dokobot read --local
│
└── 浏览器操作（写操作）
    ├── Site 有对应 adapter？→ bb-browser site <name>
    └── Site 无 adapter？→ BB Browser MCP 工具 或 Hermes 原生 browser 工具
```

> **参考文档**：`references/hermes-web-search-architecture.md` — Hermes Web Search 引擎层调用链路、Provider 选择逻辑、Brave Free 配额限制、引擎层 vs Agent 层职责边界。

---

## ⚠️ 常见错误（每次工具选择前必须自查）

1. **用 `web_extract` 抓 SPA 页面** → 只拿到空壳 HTML，应该降级到 `dokobot read`
2. **用 Dokobot 填写表单** → Dokobot 是只读的，应该用 BB Browser
3. **Web Search 失败后直接放弃** → 必须降级到 Dokobot，不要跳过
4. **BB Browser 做简单信息获取** → 杀鸡用牛刀，简单获取用 web_search 即可
5. **误以为引擎会自动降级** → `web_search` 的 Brave 超限/报错只是返回 `success: false` JSON，引擎不做 provider 切换或 dokobot 自动调用。降级是 LLM Agent 的主动行为，不是自动机制。
6. **🚫 web_search/web_extract 失败后直接调浏览器工具（`browser_navigate` / `browser_cdp` 等）** → **这是最严重的违规**。信息获取路径和浏览器自动化路径是两条独立闭环，永不相交。失败后只能降级 `dokobot read --local` → `dokobot read`（远程），绝不能跨越到浏览器工具。

> **注意**：SOUL.md 的「工具选择原则」章节已强化为强制执行规范，优先级高于本 Skill。两者冲突时以 SOUL.md 为准。
