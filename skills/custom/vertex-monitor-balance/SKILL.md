---
name: vertex-monitor-balance
description: Vertex Monitor 项目技能 — 余额/预算查询 + Web UI 开发与排障。当用户问 Gemini 余额、Vertex 预算，或涉及 VertexMonitor 前端/导航/i18n/样式问题时使用。
triggers:
  - Vertex Monitor 余额
  - Gemini 还剩多少钱
  - Vertex 预算
  - API 余额查询
  - Vertex 赠金还剩多少
  - Vertex Monitor UI
  - Vertex Monitor 前端
  - Vertex Monitor 导航
  - Vertex Monitor 样式
  - settings.html
  - Vertex Monitor i18n
---

# Vertex Monitor 余额查询

## 查询端点

```
GET http://localhost:8897/api/config
```

## 执行方式

始终使用终端工具执行 `curl` 查询（容器在本地运行）：

```bash
curl -s http://localhost:8897/api/config 2>/dev/null || echo '{"error":"container_not_running"}'
```

## 响应解析

响应 JSON 包含以下关键字段：

| 字段路径 | 含义 | 示例 |
|----------|------|------|
| `billing.mode` | 计费模式：`auto_recurring` 或 `manual` | `auto_recurring` |
| `billing.auto_monthly_amount` | 自动模式下月度预算 | `12.34` |
| `billing.auto_reset_day` | 自动模式下每月重置日 | `1` |
| `billing.manual_balance` | 手动模式下当前余额 | `10.0` |
| `billing.manual_expires_at` | 手动模式下截止时间 | `2026-06-30T23:59:59` |
| `current.balance` | 当前可用总额 | `12.34` |
| `current.spent` | 已消费金额 | `0.50` |
| `current.remaining` | 剩余可用 | `11.84` |
| `current.expires_at` | 余额到期时间 | `2026-06-28T23:59:59+00:00` |
| `current.expired` | 是否已过期 | `false` |
| `current.exhausted` | 是否已耗尽 | `false` |
| `current.status` | 状态文字（含 emoji） | `🟢 正常` |
| `period.total_calls` | 本期调用次数 | `42` |
| `lifetime.spent` | 历史总消费 | `1.23` |
| `lifetime.calls` | 历史总调用 | `156` |
| `models` | 按模型分组的消费统计 | `{"gemini-3.1-flash-lite": {...}}` |

## 回复格式

查询成功后，使用以下格式回复用户（紧凑表格，中文）：

```
Vertex 预算状态：{status emoji/text}
余额：${remaining} / ${balance}{mode_label}
已消费：${spent}
调用次数：{total_calls} 次（累计 {lifetime_calls} 次）
到期时间：{expires_at_formatted}
```

其中：
- `mode_label`：自动模式显示「（本月 $X）」；手动模式显示截止日
- `expires_at_formatted`：ISO 时间转为「YYYY年MM月DD日」
- 如果 `exhausted` 为 true，开头加上「⚠️ 余额已耗尽！」
- 如果 `expired` 为 true，开头加上「⏰ 余额已过期！」

## 连通性测试

如果只需要验证 Vertex AI 连接是否正常（不关心余额），调用 `/api/test` 端点：

```bash
curl -s -X POST http://localhost:8897/api/test
```

响应示例：
```json
{"ok": true, "model": "gemini-3.1-flash-lite", "response": "OK"}
```

## 异常处理

| 错误 | 原因 | 处理 |
|------|------|------|
| `error: container_not_running` | Docker 容器未启动 | 告知用户运行 `cd ~/Developer/Services/VertexMonitor && docker compose up -d` |
| 连接拒绝 | 端口 8897 不可达 | 同上 |
| HTTP 非 200 | 代理异常 | 显示原始错误信息 |
| 余额/配置在重启后丢失 | 数据未写入 volume 挂载目录 | 详见 `references/docker-data-persistence.md` — 检查 `data/store.json` 是否存在 |

## Web UI 开发注意事项

项目包含双页面：`static/index.html`（仪表盘）和 `static/settings.html`（设置页），共享导航栏和 `static/i18n.js` 翻译引擎。

### 导航栏架构

```
.nav (flex, align-items: center)
├── h1 — 标题
└── .nav-links (flex, gap: 8px, margin-left: auto)
    ├── a (pill 链接)
    ├── a.active (高亮)
    └── select.lang-select (语言下拉)
```

### 关键 CSS 陷阱

**全局表单选择器 vs 导航栏共享组件**：设置页的 `input, textarea, select { width: 100% }` 会把导航栏的 `.lang-select`（也是 `<select>`）撑满，导致布局换行崩溃。

修复方法（两层防御，推荐都用）：

1. `.lang-select { width: auto; }` 显式覆盖全局 `width: 100%`
2. 全局选择器排除导航栏组件：`select` → `select:not(.lang-select)`

```css
/* ❌ 全局样式误伤导航栏 select */
input, textarea, select { width: 100%; font-size: 14px; }

/* ✅ 方法一：类选择器覆盖（需覆盖所有冲突属性，容易遗漏） */
.lang-select { width: auto; font-size: 12px; }

/* ✅ 方法二（更彻底）：排除法，从源头断开 */
input, textarea, select:not(.lang-select) { width: 100%; font-size: 14px; }
```

**通用原则**：多页面 Web 应用中，全局元素选择器（`input`、`select`、`a`）极易误伤共享组件（导航栏、页脚）。优先用 `:not()` 从源头排除，而非逐一覆盖。

### i18n FOUC 闪屏

非英文语言切换页面时，英文文本先渲染再替换为中文，产生闪屏。修复需三层防御：`<head>` 预替换 + `visibility:hidden` + 底部脚本揭示。详见 `references/web-ui-architecture.md` → FOUC 防闪屏。

## 参考文件

- `references/docker-data-persistence.md` — Docker volume 挂载路径对齐：数据丢失的根因与修复
- `references/model-list-and-test.md` — 完整模型列表（13 个）+ 连通性测试端点
- `references/web-ui-architecture.md` — Web UI 架构：双页面结构、i18n、Chart.js 图表、部署流程

---

## 完整示例

**用户：** Gemini 还剩多少钱？

**执行：**
```bash
curl -s http://localhost:8897/api/config
```

**回复：**
```
Vertex 预算状态：🟢 正常
余额：$11.84 / $12.34（本月）
已消费：$0.50
调用次数：42 次（累计 156 次）
到期时间：2026年06月28日
```
