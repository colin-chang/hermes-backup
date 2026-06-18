# BB Browser 平台 Adapter 清单

> 来源：`bb-browser site list` | BB Browser v0.13.3 | 更新于 2026-05-28
>
> 完整 adapter 列表运行 `bb-browser site list` 获取。`bb-browser site update` 拉取最新社区贡献。

## 已验证可用的平台（本次 session 实测）

| 平台 | 命令 | 验证方式 |
|------|------|----------|
| 小红书 | 无 native adapter（探索页直接 browser_navigate） | CDP 直连 + browser_snapshot 提取标题 |

## 已知的 36 个平台分类

### 搜索
Google, Baidu, Bing, DuckDuckGo, Sogou WeChat

### 社交媒体
Twitter/X, Reddit, Weibo, Xiaohongshu, Zhihu, Jike, LinkedIn, Hupu

### 新闻
BBC, Reuters, 36kr, Toutiao, Eastmoney

### 开发者
GitHub, StackOverflow, HackerNews, CSDN, cnblogs, V2EX, Dev.to, npm, PyPI, arXiv

### 视频
YouTube, Bilibili

### 金融
Xueqiu, Eastmoney, Yahoo Finance

### 娱乐/知识/购物/工具/招聘
Douban, IMDb, Genius, Qidian, Wikipedia, Open Library, SMZDM, ProductHunt, BOSS Zhipin, Youdao, GSMArena, Ctrip

## 平台特定适配说明

### 小红书（Xiaohongshu）
- `bb-browser site list` 中暂未见独立 adapter
- **替代方案**：Hermes `browser_navigate` 到 `https://www.xiaohongshu.com/explore` → `browser_snapshot` 提取标题/作者
- 搜索页（`/search_result?keyword=...`）可被渲染，详情页完全依赖 JS → 用浏览器自动化提取
- `dokobot read` 对详情页无效（SPA 跳转首页）

### 知乎（Zhihu）
- `bb-browser site zhihu/hot` — 热榜（已验证）
- `bb-browser site zhihu/search "query"` — 搜索
- `bb-browser site zhihu/question "id"` — 问题详情
