---
name: bb-browser
description: BB Browser 集成 — 36 平台登录态数据获取 + Chrome CDP 浏览器自动化。通过 terminal 调用 bb-browser CLI。
version: 1.0.0
platforms: [macos]
metadata:
  hermes:
    tags: [browser, web, automation, site-adapters, chrome, cdp]
    category: custom
---

# BB Browser Skill

## 概述

BB Browser 是一个 AI Agent 浏览器工具，核心价值在于 **用真实 Chrome 登录态直接访问 36 个平台的数据**（无需 API Key、无需 Cookie 导出、无需反爬对抗）。

本 Skill 与 `tool-selection-strategy` Skill 配合使用：
- **本 Skill**：教 Hermes 如何使用 `bb-browser` CLI 命令
- **`tool-selection-strategy`**：定义 Hermes `browser_*` 工具 vs BB Browser CLI 的选择优先级

---

## 架构：CDP 直连 + CLI 补充（★ 推荐模式）

通过 `browser-configure.sh` 一键配置后，Hermes 使用双层架构：

```
┌─ 浏览器自动化 ─────────────────────────────────────────────────┐
│ Hermes browser_* 工具 → CDP(9222) → BB Browser Chrome（独立）  │
│ BROWSER_CDP_URL 自动写入 ~/.hermes/.env，每轮对话生效             │
│                                                                 │
│ Daemon 管理 Chrome 生命周期 + 最小化 profile 同步（6 个文件）     │
└────────────────────────────────────────────────────────────────┘

┌─ 平台数据获取 ─────────────────────────────────────────────────┐
│ terminal("bb-browser site <platform>/<command>")                │
│ 103 条命令 × 36 平台，用真实 Cookie 直接调网站 API              │
└────────────────────────────────────────────────────────────────┘
```

### 一键配置

```bash
~/.hermes/scripts/browser-configure.sh bb-browser
```

该脚本自动完成：
1. 修补 `--use-mock-keychain`（防止 Cookie 解密失败）
2. 从主 Chrome 同步 6 个关键 profile 文件（Cookies / Login Data 等）
3. 修复 Local State gaia 一致性
4. 启动 daemon + Chrome 实例（CDP 端口 9222）
5. 将 `BROWSER_CDP_URL` 写入 `~/.hermes/.env`

> 主 Chrome 登录任何新网站后，重新运行脚本即可同步登录态。

### 何时重新运行脚本

- 首次配置时（必须）
- 主 Chrome 登录了新网站/重新登录
- BB Browser 更新后（自动修补 `--use-mock-keychain`）
- 切换主 Chrome profile 时

---

## 工具选择原则（⚠️ 强制执行）

```
你需要做什么？
├── 通用网页交互（导航/填表/点击/截图）
│   → 优先使用 Hermes 内置 browser_* 工具
│     （browser_navigate / browser_snapshot / browser_click 等）
│
├── 获取平台数据（搜索推文/查知乎热榜/看雪球股票/YouTube 字幕等）
│   → 使用 terminal("bb-browser site <platform>/<command> [args]")
│     这是 BB Browser 的独特价值，Hermes 内置工具做不到
│
├── 需要 JavaScript 执行或网络请求捕获
│   → 使用 terminal("bb-browser eval '<js>'")
│     或 terminal("bb-browser network requests --with-body --json")
│
└── 需要独立 Chrome 实例的原始 CDP 控制
    → BB Browser daemon 管理的 Chrome 已通过 BROWSER_CDP_URL 接入
      Hermes browser_* 工具自动路由到该实例，无需手动干预
```

---

## Site Adapters 速查表（36 平台 103 命令）

> ⚠️ 完整可用命令以 `bb-browser site list` 为准。部分平台（如小红书）暂无社区 adapter，需通过 Hermes `browser_*` 工具直接操作。详见 `references/platform-inventory.md`。

### 搜索
| 命令 | 用途 |
|------|------|
| `bb-browser site google/search "query"` | Google 搜索 |
| `bb-browser site baidu/search "query"` | 百度搜索（★ 中文品牌/产品对比首选） |
| `bb-browser site bing/search "query"` | Bing 搜索（⚠️ 中文品牌名分词严重错误，勿用） |
| `bb-browser site duckduckgo/search "query"` | DuckDuckGo |
| `bb-browser site sogou-wechat/search "query"` | 搜狗微信搜索 |

> **中文搜索策略**：搜索中文品牌名/产品对比/消费评测时，Baidu 是唯一可靠选择。Bing 会将"蕉内"拆成"蕉"（香蕉），Google adapter 返回乱码。详见 `references/chinese-search-strategy.md`。

### 社交媒体
| 命令 | 用途 |
|------|------|
| `bb-browser site twitter/search "query"` | Twitter/X 搜索推文 |
| `bb-browser site twitter/feed` | Twitter 时间线 |
| `bb-browser site twitter/user "handle"` | Twitter 用户信息 |
| `bb-browser site reddit/search "query"` | Reddit 搜索 |
| `bb-browser site reddit/hot` | Reddit 热门 |
| `bb-browser site reddit/thread "url"` | Reddit 帖子和评论 |
| `bb-browser site weibo/search "query"` | 微博搜索 |
| `bb-browser site weibo/hot` | 微博热搜 |
| `bb-browser site xiaohongshu/search "query"` | 小红书搜索 |
| `bb-browser site zhihu/search "query"` | 知乎搜索 |
| `bb-browser site zhihu/hot` | 知乎热榜 |
| `bb-browser site zhihu/question "id"` | 知乎问题详情 |
| `bb-browser site jike/feed` | 即刻动态 |
| `bb-browser site linkedin/search "query"` | LinkedIn 搜索 |
| `bb-browser site linkedin/profile` | LinkedIn 个人资料 |
| `bb-browser site hupu/thread "id"` | 虎扑帖子 |

### 开发者
| 命令 | 用途 |
|------|------|
| `bb-browser site github/search "repo"` | GitHub 仓库搜索 |
| `bb-browser site github/issues "owner/repo"` | GitHub Issues |
| `bb-browser site github/repo "owner/repo"` | GitHub 仓库信息 |
| `bb-browser site stackoverflow/search "query"` | StackOverflow 搜索 |
| `bb-browser site hackernews/top` | HackerNews 热榜 |
| `bb-browser site hackernews/thread "id"` | HN 帖子详情 |
| `bb-browser site v2ex/top` | V2EX 热帖 |
| `bb-browser site csdn/search "query"` | CSDN 搜索 |
| `bb-browser site devto/top` | Dev.to 热门 |
| `bb-browser site npm/search "package"` | npm 包搜索 |
| `bb-browser site pypi/search "package"` | PyPI 包搜索 |
| `bb-browser site arxiv/search "query"` | arXiv 论文搜索 |

### 视频
| 命令 | 用途 |
|------|------|
| `bb-browser site youtube/search "query"` | YouTube 搜索 |
| `bb-browser site youtube/video "id"` | YouTube 视频信息 |
| `bb-browser site youtube/transcript "id"` | YouTube 完整字幕 |
| `bb-browser site youtube/comments "id"` | YouTube 评论 |
| `bb-browser site bilibili/search "query"` | B 站搜索 |
| `bb-browser site bilibili/video "id"` | B 站视频信息 |
| `bb-browser site bilibili/popular` | B 站热门 |

### 金融
| 命令 | 用途 |
|------|------|
| `bb-browser site xueqiu/stock "symbol"` | 雪球个股行情 |
| `bb-browser site xueqiu/hot-stock [n]` | 雪球热门股票 |
| `bb-browser site xueqiu/feed` | 雪球动态 |
| `bb-browser site eastmoney/stock "symbol"` | 东方财富个股 |
| `bb-browser site eastmoney/hot` | 东方财富热点 |
| `bb-browser site eastmoney/newsflash` | 东方财富快讯 |
| `bb-browser site yahoo-finance/search "symbol"` | Yahoo 财经搜索 |

### 新闻
| 命令 | 用途 |
|------|------|
| `bb-browser site bbc/headlines` | BBC 头条 |
| `bb-browser site reuters/headlines` | 路透社头条 |
| `bb-browser site 36kr/newsflash` | 36氪快讯 |
| `bb-browser site toutiao/hot` | 今日头条热榜 |

### 娱乐 / 知识 / 购物 / 工具
| 命令 | 用途 |
|------|------|
| `bb-browser site douban/movie "id"` | 豆瓣电影 |
| `bb-browser site douban/search "query"` | 豆瓣搜索 |
| `bb-browser site imdb/search "query"` | IMDb 搜索 |
| `bb-browser site wikipedia/summary "topic"` | Wikipedia 摘要 |
| `bb-browser site wikipedia/search "query"` | Wikipedia 搜索 |
| `bb-browser site smzdm/search "query"` | 什么值得买搜索 |
| `bb-browser site producthunt/trending` | ProductHunt 趋势 |
| `bb-browser site boss/search "query"` | BOSS 直聘搜索 |
| `bb-browser site youdao/translate "text"` | 有道翻译 |
| `bb-browser site gsmarena/search "phone"` | GSMArena 手机参数 |
| `bb-browser site genius/search "song"` | Genius 歌词搜索 |

---

## CLI 通用选项

所有 `bb-browser` 命令支持以下选项：

| 选项 | 作用 | 示例 |
|------|------|------|
| `--json` | JSON 格式输出（Agent 必备） | `--json` |
| `--jq <expr>` | jq 风格过滤 | `--jq '.items[:5]'` |
| `--tab <id>` | 指定标签页（多 tab 并发） | `--tab c416` |

---

## BB Browser 浏览器自动化命令（备选）

当 Hermes 内置 `browser_*` 工具不可用或需要互补时使用：

| 命令 | Hermes 等效工具 | 何时用 bb-browser |
|------|----------------|-------------------|
| `bb-browser open <url>` | `browser_navigate` | 无需快照的快速打开 |
| `bb-browser snap -i` | `browser_snapshot` | 需要非无障碍树格式 |
| `bb-browser click @3` | `browser_click` | 当 Hermes CDP 连接中断 |
| `bb-browser fill @5 "text"` | `browser_type` | 同上 |
| `bb-browser eval "js"` | `browser_console(expression=)` | 复杂 JS 表达式 |
| `bb-browser screenshot` | `browser_vision` | 原始截图文件 |
| `bb-browser network requests --json` | 无等效 | 捕获网络请求（独家） |
| `bb-browser console --clear` | `browser_console` | 更精细的控制台控制 |
| `bb-browser errors --clear` | `browser_console` | 独立 JS 错误查看 |

---

## 管理命令

```bash
# 更新社区 adapter 库
bb-browser site update

# 推荐匹配的 adapter（基于浏览历史）
bb-browser site recommend

# 查看 adapter 用法
bb-browser site info <name>

# 列出所有可用 adapter
bb-browser site list

# 查看 daemon 状态
bb-browser daemon status

# 编写新 adapter 教程
bb-browser guide
```

---

## 注意事项

1. **Daemon 必须先启动**：执行 `~/.hermes/scripts/browser-configure.sh bb-browser` 一键完成 daemon 启动 + 登录态同步 + CDP 配置
2. **登录态同步**：主 Chrome 登录态变更后，重新运行 `browser-configure.sh bb-browser`
3. **`--json` 是 Agent 的默认输出格式**：不加 `--json` 时输出为人类可读格式，Agent 解析困难
4. **Site adapters 运行在 daemon 的 Chrome 实例中**，不会影响你的日常浏览
5. **`--jq` 过滤比 pipe 到 `jq` 更高效**，因为过滤在进程内完成，减少数据传输

---

## 故障排查

| 问题 | 解决方案 |
|------|----------|
| `bb-browser: command not found` | `npm install -g bb-browser` |
| "Daemon HTTP 400: No page target found" | Chrome 实例刚重启无 tab，先用 Hermes `browser_navigate` 打开任意页面，或 `bb-browser open URL` |
| Daemon 连接失败 | `bb-browser daemon status` 检查状态，必要时 `bb-browser daemon start` |
| Cookie 解密失败 / 所有网站未登录 | 重新运行 `browser-configure.sh bb-browser` 同步 profile + 修补 `--use-mock-keychain` |
| Chrome 启动带 `--use-mock-keychain` | 重新运行脚本自动修补，或手动从 `/opt/homebrew/lib/node_modules/bb-browser/dist/cli.js` 删除第 171 行的 `"--use-mock-keychain",` |
| Site adapter 不存在 | `bb-browser site update` 更新社区 adapter 库，`bb-browser site list` 查看完整列表。某些平台 adapter 可能尚未贡献，可通过 `bb-browser guide` 自行编写 |
| Site adapter 返回空 | 检查是否在对应平台登录了（登录态来自主 Chrome profile 同步） |
| 登录态不同步 | 主 Chrome 重新登录后运行 `browser-configure.sh bb-browser` |
| `browser_*` 工具不工作 | 检查 `BROWSER_CDP_URL` 是否已写入 `~/.hermes/.env`，daemon 是否运行且 CDP 端口可达：`curl -s http://127.0.0.1:9222/json/version` |
| Daemon uptime 为 0s，No tabs | 正常——daemon 以 on-demand 方式管理 Chrome 实例，send 第一条 browser 命令时自动激活。如持续 0s，说明 Chrome 进程未成功启动，检查 `ps aux | grep "Google Chrome.*bb-browser"` |
