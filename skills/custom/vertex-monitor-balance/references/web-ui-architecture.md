# Vertex Monitor Web UI 架构

## 项目路径

`/Users/Colin/Developer/Services/VertexMonitor/`

## GitHub 仓库

`https://github.com/colin-chang/VertexMonitor`

## 项目结构

```
VertexMonitor/
├── proxy.py                  # FastAPI 代理 + API 端点
├── store.py                  # 双模式计费引擎 + 统计
├── static/
│   ├── index.html            # 仪表盘页 — 统计卡片 + Chart.js 图表 + 模型用量表
│   ├── settings.html         # 设置页 — 凭证/模型/计费配置 + 表单校验 + 连通性测试
│   └── i18n.js               # 翻译引擎 — en/zh-CN，data-i18n 属性 + i18n.t() API
├── config.example.json       # 示例配置（用户复制为 config.json 并填入 GCP 项目 ID）
├── requirements.txt          # Python 依赖
├── Dockerfile
├── docker-compose.yml
├── .gitignore                # 排除 config.json, vertex-key.json, data/*
├── .dockerignore
├── LICENSE                   # MIT
├── SECURITY.md               # 漏洞报告 + 凭证处理策略
├── PRIVACY.md                # 自托管、无遥测声明
├── README.md                 # 英文
├── README.zh-CN.md           # 中文
├── data/                     # 运行时数据（git 忽略）
│   └── .gitkeep
└── test_vertex.py            # 连通性测试脚本（示例项目 ID，非真实）
```

### 敏感文件排除

`.gitignore` 排除以下文件，防止凭证泄漏：

| 排除项 | 原因 |
|--------|------|
| `config.json` | 含 GCP 项目 ID |
| `vertex-key.json` / `vertex-key.json/` | 含服务账号私钥（可能是文件或目录） |
| `data/*` (除 `.gitkeep`) | 运行时数据 |
| `.env` | 环境变量 |

`config.example.json` 提供模板，用户复制后填入真实值。

## 双页面共享导航栏

两个页面各自内联完整 CSS，导航栏 HTML/CSS 结构一致：

```html
<div class="nav">
  <h1>🔒 <span data-i18n="nav_title">Vertex Monitor</span></h1>
  <div class="nav-links">
    <a href="/" class="active">📊 <span data-i18n="nav_dashboard">Dashboard</span></a>
    <a href="/settings">🔧 <span data-i18n="nav_settings">Settings</span></a>
    <select class="lang-select" onchange="i18n.setLang(this.value)">
      <option value="en">EN</option>
      <option value="zh-CN">中文</option>
    </select>
  </div>
</div>
```

## i18n 方案

- 零依赖，纯 JS 实现
- `data-i18n` 属性标记可翻译文本节点
- `i18n.t(key)` 用于 JS 动态文本
- `localStorage` 持久化语言偏好
- 默认英文，支持简体中文

### ⚠️ FOUC 防闪屏（Flash of Untranslated Content）

非英文用户切换页面时会看到：英文文本先渲染 → i18n.js 替换为中文 → 闪屏。

**三层防御机制**：

1. **`<head>` 预替换**：在 `i18n.js` 加载后紧跟同步内联脚本，非英文时立即调用 `i18n.applyAll()`：
   ```html
   <script src="/static/i18n.js"></script>
   <script>if(i18n.getLang()!=='en'){i18n.applyAll()}</script>
   ```
   此刻 `<body>` 尚未解析，`querySelectorAll('[data-i18n]')` 只能匹配 `<head>` 中的 `<title>`。

2. **`visibility:hidden` 隐藏**：`<body class="i18n-hide">` + CSS `.i18n-hide { visibility: hidden }`，确保页面在替换完成前不可见（不用 `display:none` 避免布局抖动）。

3. **底部脚本揭示**：在 `<body>` 末尾的 `<script>` 中执行 `i18n.applyAll(); document.body.classList.remove('i18n-hide');`，此时 DOM 已完全解析，所有 `data-i18n` 节点被替换后一次性显示。

**为什么不用 `DOMContentLoaded`**：`DOMContentLoaded` 触发时浏览器已开始渲染，用户会看到短暂的英文文本。

**为什么英文用户不受影响**：英文是 HTML 硬编码默认文本，`applyAll()` 不改变内容，`i18n-hide` 在底部脚本也会被移除。

## Chart.js 图表（仅仪表盘页）

- CDN 引入：`chart.js@4.4.8`
- 🍩 环形图：消费占比（暗色 15 色调色板）
- 📊 横向堆叠柱状图：Token 用量
- 图例颜色必须显式设置 `fontColor: '#c9d1d9'`（暗色主题下默认黑色不可见）

## 后端 API

| 端点 | 方法 | 说明 |
|------|------|------|
| `/api/config` | GET | 余额/计费配置 |
| `/api/config` | POST | 更新计费配置 |
| `/api/settings` | GET | 模型列表 + Key 状态 + `key_content`（回填用） |
| `/api/settings` | POST | 保存凭证/模型/计费 |
| `/api/test` | POST | 连通性测试（使用 `gemini-3.1-flash-lite`） |
| `/v1/chat/completions` | POST | OpenAI 兼容代理（SSE 流式） |

## CSS 陷阱记录

### 1. 全局 select 宽度 + 字号误伤导航栏

设置页的 `input, textarea, select { width: 100%; font-size: 14px; }` 让 `.lang-select` 被撑满且字号变大，导致换行和与 Dashboard 页不一致（切换页面时轻微闪屏）。

**修复（两层）**：

1. `.lang-select { width: auto; font-size: 12px; }` 显式覆盖
2. 全局选择器排除法：`select` → `select:not(.lang-select)`

```css
input, textarea, select:not(.lang-select) {
  width: 100%; padding: 8px 12px; /* ... */
}
```

**排查方法**：对比 Dashboard 页（正常）和 Settings 页（异常），差异在于 Settings 页有全局表单样式。

### 2. 暗色主题下 Chart.js 图例黑色不可见

`generateLabels` 的默认 `fontColor` 是黑色，暗色背景下不可读。

**修复**：显式设置 `labels: { fontColor: '#c9d1d9' }` 和 `generateLabels` 回调中 `fontColor`。

### 3. i18n FOUC 闪屏

见上方「FOUC 防闪屏」章节。

## 部署流程

```bash
# 修改前端文件后，复制到容器
docker cp static/settings.html vertex-monitor:/app/static/settings.html
docker cp static/index.html vertex-monitor:/app/static/index.html
docker cp static/i18n.js vertex-monitor:/app/static/i18n.js

# 或者重建容器
cd ~/Developer/Services/VertexMonitor && docker compose up -d --build
```

## 开源合规状态

项目已通过合规化检查，详见 `open-source-compliance` skill。关键项：

- MIT LICENSE ✅
- SECURITY.md（凭证处理策略）✅
- PRIVACY.md（自托管无遥测声明）✅
- config.example.json（脱敏配置模板）✅
- 双语 README（EN + zh-CN）✅
- .gitignore 排除 config.json / vertex-key.json / data/* ✅

## 设计规范

- 暗色主题：背景 `#0d1117`，卡片 `#161b22`，边框 `#30363d`
- 文字主色 `#c9d1d9`，次要 `#8b949e`，强调 `#58a6ff`
- 圆角 8px，pill 按钮 20px
- 无外部 CSS 框架依赖
