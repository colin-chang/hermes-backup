# Mattermost iPad 端 Markdown 表格渲染异常

## 症状

iPad Safari 上，Mattermost Web 端的 Markdown 表格被压缩在左侧窄条（column text wraps 1 character wide），
不会水平滚动。点击表格进入独立展开页面后则正常渲染。桌面端（Mac/Windows）正常。

## 渲染链路

```
Markdown 源码
  ↓ marked.js 解析
  ↓ renderer.tsx table() 方法 → 生成 HTML:
    <div class="table-responsive">
      <table class="markdown__table">
        <thead>...</thead>
        <tbody>...</tbody>
      </table>
    </div>
  ↓ messageHtmlToComponent() → html-to-react 转换
  ↓ <ShowMore> 包裹
  ↓ 最终 DOM: .post > .post__content(display:table) > .post__body > .post-message > .table-responsive
```

## 三层根因

### 1. `.table-responsive` 缺少关键 CSS

`_post.scss` 对 `.table-responsive` 只声明了 `direction: ltr`，**没有**：
- `overflow-x: auto`
- `width: 100%`
- `-webkit-overflow-scrolling: touch`

Bootstrap 的 `.table-responsive` 原本提供这些，但 Mattermost 已移除 Bootstrap 核心 CSS。
`.table-responsive` 是有名无实的空壳。

### 2. `.post-message` 的 `overflow: clip` 在 iOS Safari 更激进

```scss
.post-message {
    overflow: hidden;
    overflow: clip;  // MM-38006 fix
}
```

`overflow: clip` 是 Chromium/Gecko 功能，Safari 支持但行为更严格：
子元素无法通过自己的 `overflow-x: auto` 突破父级的 clip 约束。

### 3. `table-layout: fixed` 级联约束

```scss
.post__content {
    display: table;
    width: 100%;
    table-layout: fixed;
}
```

外层布局表固定列宽。`.post__body` 宽度 = 容器 − 头像列(53px)，
HTML `<table>` 默认 `max-width: 100%`，在受限容器中向内压缩而非溢出。

### 为什么独立页面正常？

独立 Modal/View **脱离了 `.post-message` 的 overflow 约束链**，表格自由渲染。

## 修复方案

### 方案 A：补全 `.table-responsive` CSS（推荐）

```scss
.post-message__text .table-responsive {
    display: block;
    width: 100%;
    overflow-x: auto;
    overflow-y: hidden;
    -webkit-overflow-scrolling: touch;

    .markdown__table {
        min-width: 100%;
        width: max-content;
        table-layout: auto;
        white-space: nowrap;
    }
}
```

### 方案 B：`:has()` 例外

```scss
.post-message:has(.table-responsive) {
    overflow: visible;  // 需要 iOS 15.4+
}
```

### 方案 C：自托管 CSS 注入（最实际短期方案）

Nginx 反代注入：
```nginx
sub_filter '</head>' '
  <style>
    .table-responsive { overflow-x: auto !important; -webkit-overflow-scrolling: touch !important; }
    .markdown__table { min-width: 100% !important; white-space: nowrap !important; }
  </style>
</head>';
```

## 官方关联 Issue

- [#26532](https://github.com/mattermost/mattermost/issues/26532) — "Markdown tables cause jumpy display on mobile"
  - 修复了 React Native 移动 App 的抖动重渲染，未涉及 Web/iPad 宽度压缩
- [#11948](https://github.com/mattermost/mattermost/issues/11948) — "Add expand button to truncated markdown tables"
  - 只增加了展开按钮，未从根因修复
- [#2306](https://github.com/mattermost/mattermost-mobile/issues/2306) — "Tables do not render correctly on app"
  - 相同症状："column text wraps 1 character wide"，"landscape mode renders correctly"
