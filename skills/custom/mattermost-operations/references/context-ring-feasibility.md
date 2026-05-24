# Context Ring 可视化 Footer — 技术可行性评估

> 评估日期：2026-05-24 | 状态：方案已提出，待用户决策

## 背景

用户希望将 Footer 中的上下文使用百分比（如 `34%`）改为类似 Hermes WebUI 的环形进度指示器，认为圆环比纯数字更好看、直观。本文档汇总技术调研结果。

## Hermes WebUI 的 Ring 实现（参考目标）

**渲染原理**：SVG `<circle>` + CSS `stroke-dasharray`/`stroke-dashoffset` + JavaScript 动态计算

```html
<svg viewBox="0 0 24 24">
  <circle class="ctx-ring-track" cx="12" cy="12" r="9.75"></circle>
  <circle class="ctx-ring-value" id="ctxRingValue" cx="12" cy="12" r="9.75"></circle>
</svg>
<span class="ctx-ring-center" id="ctxPercent">34</span>
```

```javascript
// ui.js:2382-2384
const circumference = 61.261056745;  // 2π × 9.75
ring.style.strokeDasharray = String(circumference);
ring.style.strokeDashoffset = String(circumference * (1 - pct/100));
```

**配色阈值**：
- ≤50%：绿色/默认
- 50-75%：琥珀色（`ctx-mid`）
- >75%：红色（`ctx-high`）

## Mattermost 约束

Mattermost 消息**不支持 SVG、HTML、CSS、内联样式**。只支持 Markdown + 文件附件。因此 WebUI 的纯 SVG+CSS 方案无法直接移植。

## 可行方案矩阵

| 方案 | 视觉质量 | 实现复杂度 | 外部依赖 | 可靠性 |
|------|---------|-----------|---------|-------|
| **A. Pillow 生成 PNG 图片** | ⭐⭐⭐⭐⭐ | 🔴 高 | Pillow + 字体 | 中 |
| **B. Emoji 彩色圆点 + 数字** | ⭐⭐ | 🟢 极低 | 无 | 高 |
| **C. Unicode 圆环字符** | ⭐ | 🟢 极低 | 无 | 低（跨平台字体差异大） |

**结论：方案 A（PNG）是唯一能实现真实圆环的方案，方案 B（Emoji）是低风险替代。**

## 方案 A 详解：Pillow PNG 生成

### 技术链路

```
Footer 检测 → 解析 pct → Pillow 绘制圆环 PNG
  → 上传 Mattermost 文件 API（POST /api/v4/files multipart/form-data）
  → 获取 file_ids
  → 编辑消息 PUT /api/v4/posts/{post_id}（携带 file_ids）
```

### 关键技术挑战

**① 文件上传 API**

当前插件只使用 `_api_post`（JSON body）。文件上传需要 multipart/form-data：
```python
async def _upload_file(self, channel_id: str, file_data: bytes, filename: str) -> str:
    """POST /api/v4/files — multipart/form-data
    fields: channel_id, client_ids, files[]
    """
```

需要在 `adapter.py` 新增 `_upload_file()` 方法，约 30 行。

**② Pillow 文字渲染**

小尺寸圆环（48-64px）内渲染百分比数字需要合适的字体。macOS 可用系统字体，跨平台需 fallback：
```python
from PIL import Image, ImageDraw, ImageFont
font_paths = [
    "/System/Library/Fonts/Helvetica.ttc",       # macOS
    "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",  # Linux
]
```

**③ 图片缓存**

同一 pct 不重复生成。内存 dict `{pct: bytes}`，101 个键值对 ≈ 200KB，可忽略。

**④ 消息编辑流程变更**

当前 footer 编辑流程：
```
PUT /api/v4/posts/{post_id}  { message: 原文 + footer }
```

PNG 方案需要两步：
```
1. POST /api/v4/files  → 获得 file_ids
2. PUT /api/v4/posts/{post_id}  { message: 原文, file_ids: [...] }
```

### Pillow Ring 生成核心代码（参考）

```python
from PIL import Image, ImageDraw, ImageFont
import io, math

def generate_ring(pct, size=48):
    stroke = max(3, size // 10)
    img = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    m = stroke // 2 + 1
    bbox = [m, m, size - m, size - m]

    # 背景轨道
    draw.arc(bbox, 0, 360, fill=(160, 160, 160, 100), width=stroke)

    # 进度弧（颜色按阈值）
    if pct > 75:
        color = (220, 60, 60, 240)
    elif pct > 50:
        color = (240, 150, 30, 240)
    else:
        color = (80, 180, 100, 240)

    end_angle = -90 + (pct / 100) * 360
    draw.arc(bbox, -90, end_angle, fill=color, width=stroke)

    # 居中文字
    font = ImageFont.truetype("/System/Library/Fonts/Helvetica.ttc", size=size // 4)
    text = f"{pct}%"
    bbox_t = draw.textbbox((0, 0), text, font=font)
    tw, th = bbox_t[2] - bbox_t[0], bbox_t[3] - bbox_t[1]
    draw.text(((size - tw) // 2, (size - th) // 2 - 2), text,
              fill=(200, 200, 200, 255), font=font)

    buf = io.BytesIO()
    img.save(buf, format='PNG')
    return buf.getvalue()
```

### 预估代码变更量

| 文件 | 新增/修改 | 估算量 |
|------|----------|-------|
| `adapter.py` — `_generate_ring_png()` | 新增 | ~40 行 |
| `adapter.py` — `_upload_file()` | 新增 | ~30 行 |
| `adapter.py` — `send()` footer 逻辑 | 修改 | ~15 行改动 |
| `requirements.txt` / 文档 | Pillow 依赖声明 | 1 行 |

**总计：~85 行新增 + 15 行修改。** 但 multipart 上传调试、字体回退验证、图片尺寸调优都需要迭代测试。

## 方案 B 详解：Emoji 彩色圆点（低风险替代）

```python
pct = int(footer_text.split()[-1].replace('%', ''))
if pct <= 50:
    dot = "🟢"
elif pct <= 75:
    dot = "🟡"
else:
    dot = "🔴"
footer_md = f"{dot} `── {footer_text} ──`"
```

**优点**：零依赖、零 API 变更、代码改动 1 行、即时生效。  
**缺点**：实心圆点（非圆环），视觉精细度不如 WebUI。

提供颜色紧迫度信息（绿→黄→红），比纯数字更直观，但达不到圆环的进度比例表达能力。

## 决策建议

| 优先级 | 建议 |
|--------|------|
| **先上线** | Emoji 方案 — 零成本验证是否需要可视化，5 分钟部署 |
| **后续迭代** | 如果 Emoji 不够满意，投入 Pillow PNG 方案 |
