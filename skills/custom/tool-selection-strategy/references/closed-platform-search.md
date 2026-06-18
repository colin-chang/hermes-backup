# 封闭平台搜索模式（Closed Platform Search Pattern）

## 问题

小红书、知乎、抖音等封闭平台：
- 搜索引擎（Google/Brave）几乎无法索引其内容
- `web_search` 返回空或仅返回首页 URL
- `web_extract` 拿到的是骨架 HTML（SPA）
- 帖子详情页重度 JS 渲染，dokobot 打开后常跳转到首页

## 解决方案：搜索页提取

对这类平台，**不要尝试打开帖子详情页**。直接在搜索页面提取帖子列表即可满足大部分需求（标题、作者、互动数据）。

### 适用场景

| 场景 | 方法 | 效果 |
|------|------|------|
| 搜索关键词 | `dokobot read --local '<搜索URL>'` | ✅ 帖子列表（标题+作者+互动+封面） |
| 打开单个帖子 | `dokobot read --local '<帖子URL>'` | ❌ 跳转首页/空白页 |
| 搜索结果翻页 | `dokobot read --local '<URL>&page=2'` | ⚠️ 取决于平台 |

### 已知平台 URL 模板

**小红书：**
```
dokobot read --local 'https://www.xiaohongshu.com/search_result?keyword=URL编码关键词&sort=general&type=51'
```
- `type=51` = 图文笔记
- 搜索结果直接包含完整的帖子标题、作者、点赞数、时间、封面图链接
- **帖子详情 URL 会重定向回首页**（安全限制 / JS 渲染）

**知乎、抖音**等其他平台类似——优先用搜索页，放弃详情页。

### 降级策略

如果搜索页也渲染不全（极端 SPA）：
1. 用 `web_search` 碰运气（有时能抓到部分缓存）
2. 直接告诉用户「该平台内容需要通过浏览器打开」，用 Google 缓存的 URL 给用户参考
3. 不要陷入反复重试——JS 渲染不是重试能解决的问题
