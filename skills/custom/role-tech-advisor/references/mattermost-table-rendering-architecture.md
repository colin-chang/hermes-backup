# Mattermost Markdown 表格渲染架构

> 深度调研日期：2026-05-24
> 调研起因：iPad 端表格压缩在左侧窄条，展开后正常渲染

## 渲染链路全貌

```
用户输入 Markdown
  ↓ formatText() — 调用 marked.js 解析
  ↓
renderer.tsx: table() — 生成 HTML：
  <div class="table-responsive">
    <table class="markdown__table">...</table>
  </div>
  ↓
messageHtmlToComponent() — html-to-react 转 React 虚拟 DOM
  ↓
<ShowMore> 包裹 → <div class="post-message post-message--collapsed">
  ↓
DOM 层级：.post > .post__content(display:table) > .post__body > .post-message
```

## 关键源码文件

| 文件 | 路径 | 作用 |
|------|------|------|
| Markdown 渲染器 | `webapp/channels/src/utils/markdown/renderer.tsx` | `table()` 方法生成 `<div class="table-responsive">` 包装 |
| HTML→React 转换 | `webapp/channels/src/utils/message_html_to_component.tsx` | 将 HTML 字符串转为 React 组件树 |
| 折叠/展开控制 | `webapp/channels/src/components/post_view/show_more/show_more.tsx` | `MAX_POST_HEIGHT=600`，控制 `post-message--collapsed/expanded` |
| 表格 CSS | `webapp/channels/src/sass/layout/_markdown.scss` | `.markdown__table` 样式（边框、斑马纹等） |
| 帖子容器 CSS | `webapp/channels/src/sass/components/_post.scss` | `.post-message` 的 `overflow: hidden/clip` |
| 响应式 CSS | `webapp/channels/src/sass/responsive/_tablet.scss` | 平板断点——**无任何表格相关规则** |

## 根因：三层 CSS 级联缺陷

### ① `.table-responsive` 缺少核心 CSS

`renderer.tsx` L209-210 生成的包装 div 类名暗示 Bootstrap 的响应式表格行为，但 Mattermost 已移除 Bootstrap 核心 CSS。

`_post.scss` L2054-2056 仅声明：
```scss
.table-responsive {
    direction: ltr;  // 仅此而已！
}
```

**缺失的应有声明**：`display: block; width: 100%; overflow-x: auto; -webkit-overflow-scrolling: touch;`

### ② `.post-message` 的 `overflow: clip` 在 iOS Safari 更激进

`_post.scss` L1847-1848（MM-38006 修复）：
```scss
.post-message {
    overflow: hidden;
    overflow: clip;  // ← iOS Safari 对此裁剪更激进
}
```

| 浏览器 | `overflow: clip` 行为 |
|--------|----------------------|
| Chrome/Edge | 允许子元素创建独立滚动区域 |
| Firefox | 同上 |
| macOS Safari | 基本兼容 |
| **iOS Safari (iPad)** | **严格裁剪所有子元素**，子无法通过 `overflow-x: auto` 突破 |

Mattermost 代码注释也承认 `overflow: clip` 在 Safari 上不稳定。

### ③ `display: table; table-layout: fixed` 级联约束

```scss
.post__content {
    display: table;
    width: 100%;
    table-layout: fixed;  // 列宽由第一行决定
}
```

iPad 上侧边栏 + 头像列(53px) 吃掉更多空间比例，留给 `.post__body` 的实际宽度更窄。HTML `<table>` 默认 `max-width: 100%`，在约束容器中向内压缩而非溢出滚动。

## 为什么展开后正常

| 场景 | 容器 | overflow 约束 | 结果 |
|------|------|-------------|------|
| 内联帖子（collapsed） | `.post-message--collapsed` | `hidden/clip` + `max-height:600px` | ❌ 压缩 |
| Show More 展开 | `.post-message--expanded` | `hidden/clip`（无 max-height） | ⚠️ 部分改善 |
| 点击表格独立页面 | 脱离 post 容器链 | 无父级 overflow | ✅ 正常 |

核心：独立页面使表格完全脱离 `.post-message` 的 overflow 约束链。

## 官方相关问题

| Issue | 状态 | 说明 |
|-------|------|------|
| #26532「tables cause jumpy display on mobile」 | 已关闭 2025-03-13 | 修复 RN App 抖动重渲染，**不涉及 Web/iPad 宽度压缩** |
| #11948「expand button for truncated tables」 | Open | 增加展开按钮改善可发现性，**未从根因修复** |
| mattermost-mobile #2306 | 已关闭 2018 | 相同症状：column text wraps 1 char wide，横屏正常 |

截至 2026-05-24，没有专门修复 iPad Web 端表格宽度压缩的 Issue 或 PR。

## 解决方案

### 方案 A：补全 `.table-responsive` CSS（推荐，最小侵入）

```scss
// 在 _markdown.scss 或 _post.scss 中添加
.post-message__text .table-responsive {
    display: block;
    width: 100%;
    overflow-x: auto;
    overflow-y: hidden;
    -webkit-overflow-scrolling: touch;
    margin: 5px 0 10px;

    .markdown__table {
        min-width: 100%;
        width: max-content;
        table-layout: auto;
        white-space: nowrap;
    }
}
```

### 方案 B：`white-space: nowrap` 轻量方案

```scss
.markdown__table {
    width: 100%;
    table-layout: auto;
    th, td { white-space: nowrap; min-width: fit-content; }
}
.table-responsive { overflow-x: auto; -webkit-overflow-scrolling: touch; }
```

### 方案 C：`:has()` 溢出例外

```scss
.post-message:has(.table-responsive) {
    overflow: visible;
}
```

⚠️ `:has()` 需要 iOS 15.4+，且可能重新触发 MM-38006 滚动 bug。

### 方案 D：自托管自定义 CSS 注入（立即可用）

```nginx
# Nginx 反代层注入
sub_filter '</head>' '
<style>
.table-responsive { overflow-x: auto !important; -webkit-overflow-scrolling: touch !important; }
.markdown__table { min-width: 100% !important; white-space: nowrap !important; }
</style></head>';
```

或 Mattermost System Console → Customization → Custom CSS。

## 调研方法记录

- 直接从 GitHub raw content 拉取源码文件（renderer.tsx, _markdown.scss, _post.scss, _tablet.scss, show_more.tsx）
- 通过 dokobot 抓取 GitHub Issue 页面内容
- 交叉验证官方 Issue 状态与社区讨论
- Brave Search 用于发现相关 Issue（受 API 频率限制，降级到 dokobot 获取详情）
