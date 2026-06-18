# Dokobot 架构分析：像素级视觉提取

## 官方定义（来源：dokobot.ai 首页，2026-06 实测）

> **"Pixel-based visual extraction.** Dokobot analyzes the rendered page at pixel level, not the DOM tree. It detects content boundaries from visual coordinates, making it immune to HTML/CSS changes."

> "Visual, not DOM — Reads what you see on screen, not the code behind it"

> "No adapters needed — Works on any webpage without site-specific configuration"

> "Immune to site changes — HTML/CSS redesigns don't affect extraction results"

## Token 减量数据（官方）

- Raw HTML of typical web page: **~24,000 tokens**
- Dokobot output: **~240 tokens**（99% 减量）

## 架构链路

```
Chrome 渲染页面（完整 JS 执行，包括 SPA/infinite scroll/lazy-load）
        │
        ▼
Dokobot Extension 滚动截图（--screens 参数控制截取几个"屏"）
        │
        ▼
像素级分析：从视觉坐标检测内容边界
（不是 DOM 遍历，不受 HTML/CSS 变更影响）
（不是 VLM/OCR——不做图像→文字转换）
        │
        ▼
提取对应区域的文本 → 结构化输出 → CLI stdout
```

## 关键辨析

### 像素分析 ≠ OCR/VLM
Dokobot 的"像素级分析"做的是**内容边界检测**（智能裁剪），不是图像→文字转换。文本本身来自 Chrome 渲染后的页面，只是**哪些文本该保留**的判断依据是视觉布局而非 DOM 树。

### 像素分析 vs DOM 解析 vs browser_vision

| 方案 | 提取方式 | SPA 支持 | 防改版 | 提取端 Token 成本 |
|------|---------|:---:|:---:|:---:|
| **DOM textContent** | 遍历 DOM 取 textContent | ❌ JS 未执行 | ❌ 依赖选择器 | 0 |
| **Raw HTML** | HTTP response body | ❌ | ❌ | ~24K tokens（进 LLM） |
| **browser_vision** | 截图 → VLM 看图识字 | ✅ Chrome 渲染 | ✅ 视觉判断 | 5-15K tokens（截图编码+VLM 推理） |
| **Dokobot** | 渲染 → 像素边界检测 → 文本提取 | ✅ Chrome 渲染 | ✅ 视觉坐标 | **0**（本地 bridge，不进 LLM） |

### 为什么 SPA 能读
Chrome 执行所有 JS → DOM 完全渲染 → Dokobot 截图 → 像素分析。对提取器来说，SSR 和 CSR 最终渲染结果在像素层面没有区别。这与 headless 抓取工具的根本差异。

### 为什么防改版
CSS class 改名了？DOM 结构变了？像素布局不变就无影响。Dokobot 看的是"屏幕上第 300-800px 这个矩形区域"，不关心它的 CSS 选择器是 `.content` 还是 `.x7pq2a`。

## 实测输出特征（dokobot read --local）

- 保留基本 HTML 标签（`<h1>`, `<a>`, `<p>`）用于 LLM 结构化理解
- 可能保留少量 CSS class（如 `<div class="entry-content">`）
- 自动剔除导航栏/页脚/广告/侧边栏
- `--format chunks` 模式输出分段 JSON

## 与 browser_vision 的选择边界

| 场景 | 用 Dokobot | 用 browser_vision |
|------|:---:|:---:|
| 提取网页文本内容 | ✅ 首选 | ❌ 浪费 token |
| 分析页面 UI/布局 | ❌ 只有文本 | ✅ 看图分析 |
| 验证页面渲染结果 | ❌ | ✅ 截图对比 |
| 读图表/数据可视化 | ⚠️ 无法提取图表 | ✅ 唯一选择 |
