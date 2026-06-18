# BB Browser × Hermes 集成参考

> 调研日期：2026-05-27 | BB Browser v0.13.3

## 架构概览

```
AI Agent (Hermes / Claude Code / Codex)
       │ CLI (唯一可用路径)
       ▼
bb-browser CLI ──HTTP──▶ Daemon ──CDP WebSocket──▶ 真实 Chrome
                           │
                    ┌──────┴──────┐
                    │ Per-tab     │
                    │ event cache │
                    │ (network,   │
                    │  console,   │
                    │  errors)    │
                    └─────────────┘
```

## MCP Server 状态：已移除 ❌

| 验证方式 | 结论 |
|----------|------|
| `bb-browser --help`（v0.13.3） | 无 `--mcp` 参数 |
| npm keywords | 不含 "mcp" |
| npm description | "CLI for AI agents"（不再是 "CLI + MCP server"） |
| GitHub README（main 分支） | **仍保留 MCP 配置示例 — 文档过时，未同步更新** |

**结论：BB Browser v0.13.3 的 MCP Server 已移除。唯一可用集成方式是 CLI 调用。**

## BB Browser 的两层能力

### Layer 1：浏览器自动化（与 Hermes 高度重叠）

```bash
bb-browser open <url>        # 导航
bb-browser snap -i            # 快照
bb-browser click @3           # 点击
bb-browser fill @5 "text"     # 输入
bb-browser eval "document..." # JS 执行
bb-browser screenshot         # 截图
```

**→ Hermes 内置 `browser_*` 工具已覆盖这些功能，无需额外调用 BB Browser。**

### Layer 2：Site Adapters（BB Browser 独有价值）

```bash
bb-browser site <platform>/<command> [args]
```

36 平台 × 103 条命令，用真实浏览器登录态直接调网站 API：

| 类别 | 平台 | 代表命令 |
|------|------|----------|
| 搜索 | Google, Baidu, Bing, DuckDuckGo | `site google/search "..."` |
| 社交 | Twitter/X, Reddit, 微博, 小红书, 知乎, LinkedIn, 即刻, 虎扑 | `site twitter/search "..."` / `site zhihu/hot` |
| 新闻 | BBC, Reuters, 36kr, 头条, 东方财富 | `site 36kr/newsflash` |
| 开发 | GitHub, StackOverflow, HN, CSDN, V2EX, npm, PyPI, arXiv | `site github/search "..."` |
| 视频 | YouTube, Bilibili | `site youtube/transcript ID` |
| 金融 | 雪球, 东方财富, Yahoo Finance | `site xueqiu/hot-stock 5` |
| 招聘 | BOSS 直聘, LinkedIn | `site boss/search "..."` |
| 知识 | Wikipedia, 知乎 | `site wikipedia/summary "..."` |

## Hermes 内置 browser 工具速查

Hermes 默认通过 `agent-browser` CLI（Vercel）驱动本地 Chromium：

| 工具 | 功能 |
|------|------|
| `browser_navigate` | 导航到 URL |
| `browser_snapshot` | 无障碍树快照（含可交互元素 ref） |
| `browser_click` | 点击元素 |
| `browser_type` | 输入文字 |
| `browser_scroll` | 滚动页面 |
| `browser_press` | 按键（Enter/Tab/Escape 等） |
| `browser_back` | 后退 |
| `browser_get_images` | 获取页面图片列表 |
| `browser_vision` | 截图 + 视觉 AI 分析 |
| `browser_console` | Console 输出 / JS 表达式执行 |
| `browser_cdp` | 原始 CDP 透传（需 `/browser connect`） |
| `browser_dialog` | 处理 JS 弹窗 |

> 需要登录态时：`/browser connect` 直连本地 Chrome CDP，之后所有 browser_* 工具操作真实浏览器。

## 工具选择矩阵

| 场景 | 推荐工具 | 原因 |
|------|---------|------|
| 打开网页、填表单、点按钮 | Hermes `browser_*` | 内置、零延迟、无需额外命令 |
| 需要登录态的网页交互 | `/browser connect` + Hermes `browser_*` | 直连真实 Chrome |
| 搜 Twitter 推文 | `terminal("bb-browser site twitter/search ...")` | 用 Cookie 直接调 Twitter API |
| 刷知乎热榜 | `terminal("bb-browser site zhihu/hot")` | 一条命令出 JSON |
| 查雪球股票 | `terminal("bb-browser site xueqiu/hot-stock 5")` | 实时行情 |
| YouTube 字幕 | `terminal("bb-browser site youtube/transcript ID")` | 全文字幕提取 |
| 一般网页内容抓取 | `web_search` + `web_extract` | 最快最便宜 |
| 需要 JS 渲染的页面 | 降级到 `dokobot read --local` | 真实浏览器渲染 |
| 带 Cookie 的 HTTP 请求 | `terminal("bb-browser fetch URL --json")` | 用登录态发 fetch |

## CDP 直连：BB Browser daemon Chrome → Hermes（★ 最佳实践）

自 BB Browser MCP 移除后，BB Browser 与 Hermes 的集成采用双层架构：

### 层 1：BB Browser daemon 管理 Chrome 生命周期

```bash
~/.hermes/scripts/browser-configure.sh bb-browser
```

脚本完成：
1. **修补 `--use-mock-keychain`**：BB Browser v0.13.3 的 `cli.js` 第 171 行包含此 flag，它让 Chrome 使用假 Keychain 密钥，导致 Cookie 解密失败、所有网站登录态丢失。脚本自动检测并删除。
2. **最小化 Profile 同步**：从主 Chrome 拷贝 6 个关键文件到 `~/.bb-browser/browser/user-data/Default/`：
   - `Cookies`（~1.3MB，最关键）、`Login Data`、`Login Data For Account`、`Web Data`、`Preferences`、`Secure Preferences`
3. **Local State gaia 一致性修复**：bb-browser 的 Local State 是单 profile 结构（`Default: bb-browser`），主 Chrome 是多 profile。直接覆盖会导致 Chrome 启动时 gaia_id 校验失败并清除 account_info。脚本从主 Chrome 提取 `gaia_name/user_name/gaia_id/name` 注入 bb-browser 的 Local State。
4. **启动 daemon**：daemon 在 `127.0.0.1:19824`（HTTP API）启动 Chrome，Chrome CDP 监听在 `127.0.0.1:9222`（默认）。
5. **写入 BROWSER_CDP_URL**：将 `ws://127.0.0.1:9222/devtools/browser/<uuid>` 写入 `~/.hermes/.env`。Hermes Gateway 每 turn 自动重载 `.env`，无需重启。

### 层 2：Hermes browser_* 工具通过 CDP 直连

```
Hermes browser_navigate/browser_snapshot/browser_click/...
       │
       ▼
BROWSER_CDP_URL=ws://127.0.0.1:9222/devtools/browser/<uuid>
       │
       ▼
BB Browser Chrome（独立实例，~/.bb-browser/browser/user-data/）
       │ 登录态来自主 Chrome profile 同步
       ▼
真实网站（带 Cookie，与主 Chrome 完全隔离）
```

### 层 3：BB Browser site CLI 补充平台数据

```bash
# 通过 terminal 工具调用
bb-browser site twitter/search "AI agent" --json
bb-browser site zhihu/hot --json
```

所有 site 命令运行在 daemon 的 Chrome 实例中（tab 自动管理），Agent 通过 `terminal` 工具调用，拿到 JSON 输出。

### 优势

- **无 `/browser connect` 弹窗**：每轮对话自动生效，无需每次授权
- **独立 Chrome 实例**：与日常浏览完全隔离，不会互相干扰
- **Daemon 管理生命周期**：Chrome 自动启停，崩溃自动恢复
- **一条命令配置**：`browser-configure.sh bb-browser`
- **登录态同步**：主 Chrome 登录任何新网站后，重新运行脚本即可同步

### macOS Cookie 加密保障

Chrome 在 macOS 上使用 Keychain 存储的 v10 加密密钥来加密 Cookies。关键：**v10 密钥绑定的是 macOS 用户账户，而非 user-data-dir 路径**。因此同一 macOS 用户下的任何 Chrome 实例（无论使用哪个 user-data-dir）都能从 Keychain 取出密钥并解密 Cookie。这与 Windows 的 App-Bound Encryption 不同（Windows 绑定安装路径）。

### 已知陷阱

| 问题 | 根因 | 修复 |
|------|------|------|
| Cookie 解密失败 | `--use-mock-keychain` 使用假密钥 | 从 cli.js 删除该 flag，`browser-configure.sh` 自动处理 |
| account_info 被清除 | Local State 的 gaia_id 与 Cookies 不一致 | 脚本自动同步 gaia_name/user_name/gaia_id |
| daemon "No page target found" | Chrome 实例刚启动，无 tab | 用 Hermes browser_navigate 打开任意页面即可 |
| 登录态过期不同步 | 主 Chrome 重新登录后未同步 | 重新运行 `browser-configure.sh bb-browser` |

## Hermes 集成方案总结

| 方案 | 状态 | 说明 |
|------|------|------|
| MCP 集成 | ❌ 不可行 | `--mcp` flag 已移除 |
| **CDP 直连 daemon Chrome** | **✅ ★ 推荐** | `browser-configure.sh bb-browser` → BROWSER_CDP_URL → browser_* 工具 |
| Hermes 内置 browser（默认） | ✅ 备选 | 默认 agent-browser 后端，无登录态 |
| `/browser connect` 直连主 Chrome | ✅ 备选 | 每次弹授权窗，适合临时调试 |
| Skill 教 Hermes 用 bb-browser CLI | 🟢 已实施 | `custom/bb-browser` Skill，教 Agent 在合适场景用 `terminal` 调 site 命令 |
