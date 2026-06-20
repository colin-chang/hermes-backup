# bb-browser → OpenCLI 迁移对照表

> 迁移日期：2026-06-20 | OpenCLI v1.8.4

## 命令语法映射

### 站点适配器（最重要）

| bb-browser | OpenCLI | 说明 |
|-----------|---------|------|
| `bb-browser site twitter/search "q"` | `opencli twitter search "q" -f json` | 格式变为 `-f json` 而非 `--json` |
| `bb-browser site twitter/feed` | `opencli twitter timeline -f json` | 命令名不同 |
| `bb-browser site twitter/user "h"` | `opencli twitter profile "h" -f json` | — |
| `bb-browser site reddit/search "q"` | `opencli reddit search "q" -f json` | — |
| `bb-browser site reddit/hot` | `opencli reddit frontpage -f json` | — |
| `bb-browser site reddit/thread "url"` | `opencli reddit read "url" -f json` | 直接传 URL |
| `bb-browser site zhihu/hot` | `opencli zhihu hot -f json` | — |
| `bb-browser site zhihu/search "q"` | `opencli zhihu search "q" -f json` | — |
| `bb-browser site zhihu/question "id"` | `opencli zhihu question "id" -f json` | — |
| `bb-browser site xueqiu/hot-stock 5` | `opencli xueqiu stock <symbol> -f json` | 按个股查，无 hot-stock |
| `bb-browser site xueqiu/stock "s"` | `opencli xueqiu stock "s" -f json` | — |
| `bb-browser site xueqiu/feed` | `opencli xueqiu feed -f json` | — |
| `bb-browser site weibo/search "q"` | `opencli weibo search "q" -f json` | — |
| `bb-browser site weibo/hot` | `opencli weibo hot -f json` | — |
| `bb-browser site xiaohongshu/search "q"` | `opencli xiaohongshu search "q" -f json` | — |
| `bb-browser site linkedin/search "q"` | `opencli linkedin search "q" -f json` | — |
| `bb-browser site hupu/thread "id"` | `opencli hupu detail "id" -f json` | 命令名不同 |
| `bb-browser site youtube/search "q"` | `opencli youtube search "q" -f json` | — |
| `bb-browser site youtube/transcript "id"` | 无直接等价，需 `opencli browser` 或 dokobot | YouTube adapter 无 transcript |
| `bb-browser site youtube/comments "id"` | `opencli youtube comments "id" -f json` | — |
| `bb-browser site bilibili/search "q"` | `opencli bilibili search "q" -f json` | — |
| `bb-browser site bilibili/popular` | `opencli bilibili ranking -f json` | — |
| `bb-browser site bilibili/video "id"` | — | OpenCLI 无单独视频信息命令 |
| `bb-browser site github/search "q"` | — | OpenCLI GitHub adapter 有限，优先用 `gh` CLI |
| `bb-browser site stackoverflow/search "q"` | `opencli stackoverflow search "q" -f json` | — |
| `bb-browser site hackernews/top` | `opencli hackernews top -f json` | — |
| `bb-browser site v2ex/top` | `opencli v2ex hot -f json` | — |
| `bb-browser site arxiv/search "q"` | `opencli arxiv search "q" -f json` | — |
| `bb-browser site npm/search "pkg"` | `opencli npm search "pkg" -f json` | — |
| `bb-browser site 36kr/newsflash` | `opencli 36kr news -f json` | — |
| `bb-browser site toutiao/hot` | `opencli toutiao hot -f json` | — |
| `bb-browser site eastmoney/hot` | `opencli eastmoney rank -f json` | — |
| `bb-browser site eastmoney/stock "s"` | `opencli eastmoney quote "s" -f json` | — |
| `bb-browser site boss/search "q"` | `opencli boss recommend -f json` | 推荐而非搜索 |
| `bb-browser site smzdm/search "q"` | `opencli smzdm search "q" -f json` | — |
| `bb-browser site douban/search "q"` | `opencli douban movie-hot -f json` | 热榜代替搜索 |
| `bb-browser site youdao/translate "t"` | — | OpenCLI 仅有 youdao/note（读公开笔记） |

### 搜索引擎

| bb-browser | OpenCLI | 说明 |
|-----------|---------|------|
| `bb-browser site baidu/search` | `opencli google search` | OpenCLI 无百度 adapters |
| `bb-browser site google/search` | `opencli google search` | 直接搜，无乱码问题 |
| `bb-browser site bing/search` | `opencli yahoo search` | Yahoo = Bing 后端，中文弱 |
| `bb-browser site duckduckgo/search` | `opencli brave search` | Brave 隐私搜索引擎 |

### 浏览器自动化

| bb-browser | OpenCLI | 说明 |
|-----------|---------|------|
| `bb-browser open <url>` | `opencli browser <s> open <url>` | 需要 session 参数 |
| `bb-browser snap -i` | `opencli browser <s> snapshot` | — |
| `bb-browser click @3` | `opencli browser <s> click @3` | — |
| `bb-browser fill @5 "t"` | `opencli browser <s> fill @5 "t"` | — |
| `bb-browser eval "js"` | `opencli browser <s> eval "js"` | — |
| `bb-browser screenshot` | `opencli browser <s> screenshot` | — |
| `bb-browser network requests` | `opencli browser <s> network` | — |

### 管理命令

| bb-browser | OpenCLI | 说明 |
|-----------|---------|------|
| `bb-browser site update` | — | 扩展自动更新 |
| `bb-browser site list` | `opencli list` | 列出所有可用命令 |
| `bb-browser site recommend` | — | 无等价 |
| `bb-browser daemon status` | `opencli doctor` | doctor 检查更多 |
| `bb-browser daemon start` | 自动启动 | daemon auto-start |
| `bb-browser guide` | — | 参考 GitHub docs |

## 架构差异

| 维度 | bb-browser | OpenCLI |
|------|-----------|---------|
| Chrome | 独立 managed Chrome | 复用现有 Chrome |
| 扩展 | 不需要（v0.11.1 后移除） | 需要 Browser Bridge 扩展 |
| 登录态 | 默认需重新登录 | 直接共享 |
| JSON 格式 | `--json` | `-f json` |
| Token 成本 | 适配器有 LLM 成本 | 适配器零 Token |
| 开源 | MIT | Apache-2.0 |
