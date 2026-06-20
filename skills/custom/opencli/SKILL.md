---
name: opencli
description: OpenCLI 集成 — 100+ 站点适配器数据获取 + Chrome CDP 浏览器自动化。通过 terminal 调用 opencli CLI。复用用户现有 Chrome 登录态，无需独立实例。
version: 1.0.0
platforms: [macos]
metadata:
  hermes:
    tags: [browser, web, automation, site-adapters, chrome, cdp, opencli]
    category: custom
---

# OpenCLI Skill

## 概述

OpenCLI 是一个 AI Agent 浏览器工具，核心价值在于 **复用你现有 Chrome 的登录态，通过 100+ 站点适配器直接调用网站 API**（零 LLM Token 成本）+ **通用 DOM 快照引擎驱动任意网页**。

本 Skill 与 `tool-selection-strategy` Skill 配合使用：
- **本 Skill**：教 Hermes 如何使用 `opencli` CLI 命令
- **`tool-selection-strategy`**：定义 Hermes 工具 vs OpenCLI CLI 的选择优先级

---

## 架构

```
┌─ 平台数据获取（站点适配器）──────────────────────────────────────┐
│ terminal("opencli <site> <command>")                              │
│ 100+ 站点 × 数百命令，用真实 Cookie 直接调网站 API                │
│ 复用你现有 Chrome（Browser Bridge 扩展 + 本地 daemon）            │
└──────────────────────────────────────────────────────────────────┘

┌─ 浏览器自动化（opencli-browser）─────────────────────────────────┐
│ terminal("opencli browser <session> <command>")                   │
│ navigate / click / type / fill / extract / snapshot / screenshot   │
│ AI Agent 可直接操控你已登录的 Chrome 页面                          │
└──────────────────────────────────────────────────────────────────┘

┌─ CLI Hub + 桌面应用 ─────────────────────────────────────────────┐
│ terminal("opencli <tool> <args>") — gh/docker/obsidian/notion 等  │
│ terminal("opencli <app> <cmd>") — Cursor/ChatGPT/Codex 等桌面应用  │
└──────────────────────────────────────────────────────────────────┘
```

### 安装与验证

```bash
npm install -g @jackwener/opencli
# 安装 Chrome Web Store 扩展: https://chromewebstore.google.com/detail/opencli/ildkmabpimmkaediidaifkhjpohdnifk
opencli doctor
```

---

## 工具选择原则（⚠️ 强制执行）

```
你需要做什么？
├── 获取平台数据（搜索推文/查知乎热榜/看雪球股票/YouTube 字幕等）
│   → 使用 terminal("opencli <site> <command> [args]")
│     100+ 站点适配器，直接调网站 API，零 Token 成本
│
├── 通用网页交互（导航/填表/点击/截图）
│   → 优先使用 Hermes 内置 browser_* 工具
│     （browser_navigate / browser_snapshot / browser_click 等）
│     如需用户登录态，用 opencli browser <session> open <url> 替代
│
├── 需要 JavaScript 执行或网络请求捕获
│   → terminal("opencli browser <session> eval '<js>'")
│     或 terminal("opencli browser <session> network")
│
└── 桌面应用 / CLI 工具
    → terminal("opencli <app> <command>")
      或 terminal("opencli <tool> <args>")
```

---

## Site Adapters 速查表（100+ 站点）

> ⚠️ 完整可用命令以 `opencli list` 为准。以下为常用映射。

### 搜索
| 命令 | 用途 |
|------|------|
| `opencli google search "query"` | Google 搜索 |
| `opencli brave search "query"` | Brave 搜索 |
| `opencli google news` | Google 新闻 |
| `opencli google-scholar search "query"` | Google 学术 |
| `opencli baidu-scholar search "query"` | 百度学术 |
| `opencli yahoo search "query"` | Yahoo 搜索（Bing 后端） |

> **中文搜索策略**：搜索中文品牌名/产品对比/消费评测时，Google 为主要选择。OpenCLI 没有独立的 Baidu Web Search adapter，但 Google 对中文 SEO 站点的索引质量通常优于 Bing。详见 `references/chinese-search-strategy.md`。

### 社交媒体
| 命令 | 用途 |
|------|------|
| `opencli twitter search "query"` | Twitter/X 搜索推文 |
| `opencli twitter timeline` | Twitter 时间线 |
| `opencli twitter profile [user]` | Twitter 用户信息 |
| `opencli twitter bookmarks` | Twitter 书签 |
| `opencli twitter trending` | Twitter 趋势 |
| `opencli reddit search "query"` | Reddit 搜索 |
| `opencli reddit frontpage` | Reddit 首页 |
| `opencli reddit subreddit "name"` | Reddit 子版块 |
| `opencli reddit read <url>` | Reddit 帖子和评论 |
| `opencli weibo search "query"` | 微博搜索 |
| `opencli weibo hot` | 微博热搜 |
| `opencli xiaohongshu search "query"` | 小红书搜索 |
| `opencli xiaohongshu note <url>` | 小红书笔记详情 |
| `opencli zhihu search "query"` | 知乎搜索 |
| `opencli zhihu hot` | 知乎热榜 |
| `opencli zhihu question <id>` | 知乎问题详情 |
| `opencli jike feed` | 即刻动态 |
| `opencli linkedin search "query"` | LinkedIn 搜索 |
| `opencli linkedin people-search "query"` | LinkedIn 人脉搜索 |
| `opencli hupu hot` | 虎扑热门帖子 |
| `opencli hupu search "query"` | 虎扑搜索 |

### 开发者
| 命令 | 用途 |
|------|------|
| `opencli github whoami` | GitHub 登录状态 |
| `opencli stackoverflow search "query"` | StackOverflow 搜索 |
| `opencli stackoverflow hot` | SO 热门问题 |
| `opencli stackoverflow read <url>` | SO 问题和回答 |
| `opencli hackernews top` | HackerNews 首页 |
| `opencli hackernews best` | HN 最佳 |
| `opencli v2ex hot` | V2EX 热门 |
| `opencli v2ex latest` | V2EX 最新 |
| `opencli arxiv search "query"` | arXiv 论文搜索 |
| `opencli arxiv paper <id>` | arXiv 论文详情 |
| `opencli npm search "package"` | npm 包搜索 |
| `opencli pypi package "name"` | PyPI 包信息 |
| `opencli devto latest` | Dev.to 最新文章 |

### 视频
| 命令 | 用途 |
|------|------|
| `opencli youtube search "query"` | YouTube 搜索 |
| `opencli youtube channel <id>` | YouTube 频道信息 |
| `opencli youtube comments <id>` | YouTube 评论 |
| `opencli bilibili search "query"` | B 站搜索 |
| `opencli bilibili ranking` | B 站排行榜 |
| `opencli bilibili download <BV>` | B 站视频下载（需 yt-dlp） |

### 金融
| 命令 | 用途 |
|------|------|
| `opencli xueqiu stock <symbol>` | 雪球个股行情 |
| `opencli xueqiu watchlist` | 雪球自选股 |
| `opencli xueqiu search "symbol"` | 雪球股票搜索 |
| `opencli eastmoney quote <symbol>` | 东方财富实时行情 |
| `opencli eastmoney rank` | 东财涨跌排行 |
| `opencli eastmoney sectors` | 板块排行 |
| `opencli yahoo-finance quote <symbol>` | Yahoo 财经行情 |

### 新闻
| 命令 | 用途 |
|------|------|
| `opencli 36kr hot` | 36氪热榜 |
| `opencli 36kr news` | 36氪快讯 |
| `opencli toutiao hot` | 今日头条热榜 |
| `opencli bbc news` | BBC 头条 |
| `opencli reuters search "query"` | 路透社搜索 |

### 娱乐 / 知识 / 购物 / 工具
| 命令 | 用途 |
|------|------|
| `opencli douban movie-hot` | 豆瓣电影热榜 |
| `opencli douban book-hot` | 豆瓣图书热榜 |
| `opencli imdb search "query"` | IMDb 搜索 |
| `opencli wikipedia search "topic"` | Wikipedia 搜索 |
| `opencli wikipedia page "topic"` | Wikipedia 全文 |
| `opencli smzdm search "query"` | 什么值得买搜索 |
| `opencli producthunt hot` | ProductHunt 热门 |
| `opencli boss recommend` | BOSS 直聘推荐 |
| `opencli 1688 search "query"` | 1688 商品搜索 |
| `opencli amazon search "query"` | Amazon 搜索 |

---

## CLI 通用选项

所有 `opencli` 命令支持以下选项：

| 选项 | 作用 | 示例 |
|------|------|------|
| `-f json` | JSON 格式输出（Agent 必备） | `-f json` |
| `-f csv` | CSV 格式 | `-f csv` |
| `-f md` | Markdown 表格 | `-f md` |
| `-v` | 显示详细调试步骤 | `-v` |

> ⚠️ OpenCLI 使用 `-f json` 而非 `--json`，与 bb-browser 的 CLI 习惯不同。

---

## 管理命令

```bash
# 列出所有可用命令
opencli list

# 检查连接状态
opencli doctor

# 管理 Chrome profile（多 profile 场景）
opencli profile list
opencli profile rename <contextId> work
opencli profile use work

# 安装社区插件
opencli plugin install github:user/opencli-plugin-name
opencli plugin list
opencli plugin update --all
```

---

## 注意事项

1. **Browser Bridge 扩展必须安装且启用**：从 Chrome Web Store 安装后，运行 `opencli doctor` 验证连接
2. **复用你现有 Chrome 登录态**：OpenCLI 通过 Browser Bridge 扩展直接操作你的真实浏览器，无需重新登录
3. **`-f json` 是 Agent 的默认输出格式**：不加 `-f json` 时输出为人类可读表格
4. **Site adapters 运行在你的主 Chrome 中**，与日常浏览共享登录态
5. **`opencli browser` 需要指定 session**：`opencli browser <session> <command>`，session 是任意命名（如 `work`）
6. **Daemon 自动启动**：首次使用时会自动启动本地 daemon（端口 19825）

---

## 故障排查

| 问题 | 解决方案 |
|------|----------|
| `opencli: command not found` | `npm install -g @jackwener/opencli` |
| "Extension not connected" | 确保 Browser Bridge 扩展已安装且启用，`opencli doctor` 诊断 |
| "Unauthorized" / 空数据 | Chrome 登录态可能过期，在 Chrome 中重新登录目标网站 |
| Daemon 连接失败 | `curl localhost:19825/status` 检查状态，必要时重启 |
| 多 Chrome profile 混乱 | `opencli profile list` 查看已连接 profile，`opencli profile use <id>` 指定默认 |

> **从 bb-browser 迁移？** 详见 `references/bb-browser-migration.md`，包含完整命令语法对照与架构差异。
