# 前端暗色主题 UI 模式

> 从 Vertex Monitor Web UI 开发中提炼的可复用前端模式。适用于任何暗色主题单页应用。

## Chart.js 暗色主题陷阱

### generateLabels 不继承 labels.color

Chart.js v4 的 `options.plugins.legend.labels.color` 设置图例文字颜色，但 **使用自定义 `generateLabels` 时不会自动继承**。必须显式在每个返回的 label item 中设置 `fontColor`：

```javascript
// ❌ 错误 — 图例文字为黑色（默认）
legend: {
  labels: {
    color: '#c9d1d9',  // 被 generateLabels 忽略
    generateLabels: function(chart) {
      return chart.data.labels.map((l, i) => ({
        text: l + '  $' + chart.data.datasets[0].data[i].toFixed(4),
        fillStyle: chart.data.datasets[0].backgroundColor[i],
        // 缺少 fontColor → 回退到默认黑色
      }));
    }
  }
}

// ✅ 正确
generateLabels: function(chart) {
  return chart.data.labels.map((l, i) => ({
    text: l + '  $' + chart.data.datasets[0].data[i].toFixed(4),
    fillStyle: chart.data.datasets[0].backgroundColor[i],
    fontColor: '#c9d1d9',  // 显式设颜色
    ...
  }));
}
```

### 全局默认 vs 图表实例

```javascript
// 全局默认（所有图表生效）
Chart.defaults.color = '#8b949e';
Chart.defaults.borderColor = 'rgba(48,54,61,0.5)';

// 实例级覆盖（单图表的 legend labels）
options: {
  plugins: {
    legend: { labels: { color: '#c9d1d9' } }  // 仅覆盖此图
  }
}
```

## 导航栏 CSS：macOS `<select>` 兼容

### 问题

macOS 的 `<select>` 有平台原生渲染，CSS `height`/`line-height` 行为不可预测。强制统一高度会导致对齐错乱。

### 最简可靠方案

```css
.nav { display: flex; align-items: center; gap: 16px; }
.nav-links { display: flex; gap: 8px; margin-left: auto; align-items: center; }
.nav-links a {
  padding: 5px 14px; border-radius: 20px;  /* pill 风格 */
}
.lang-select {
  padding: 4px 8px;                        /* 不设 height */
  border-radius: 6px;                      /* 小圆角与 pill 区分 */
}
```

**原则：**
- 不设 `height` 给 `<select>` — 依赖 `padding` 自然撑高
- 不设 `flex-wrap: wrap` 给导航容器 — 除非移动端适配
- 不设 `white-space: nowrap` 给标题 — 可能挤压右侧元素
- 用 `align-items: center` 让 flexbox 自动垂直对齐

### 过度约束的反模式

```css
/* ❌ 这些容易引起问题 */
.nav { flex-wrap: wrap; }       /* 窄屏可能换行错位 */
.nav h1 { white-space: nowrap; } /* 标题过长会溢出 */
.nav-links { flex-shrink: 0; }  /* 可能挤压到容器外 */
.nav-links a { height: 30px; }  /* inline 元素 height 无效 */
.lang-select { height: 30px; }  /* macOS select 不服从 */
```

## i18n 实现模式

### 纯前端方案（无框架依赖）

```javascript
// i18n.js — 翻译引擎
const messages = { en: { key: 'value' }, 'zh-CN': { key: '值' } };
window.i18n = {
  getLang: () => localStorage.getItem('lang') || 'en',
  setLang: (l) => { localStorage.setItem('lang', l); location.reload(); },
  t: (k) => messages[i18n.getLang()]?.[k] || messages.en?.[k] || k,
};
// DOM 就绪时扫描 [data-i18n] 属性
document.addEventListener('DOMContentLoaded', () => {
  document.querySelectorAll('[data-i18n]').forEach(el => {
    el.textContent = i18n.t(el.getAttribute('data-i18n'));
  });
});
```

```html
<!-- HTML 中使用 -->
<h2 data-i18n="overview_title">Current Period</h2>
```

### 动态文本

JS 中生成的内容用 `i18n.t()`：
```javascript
tbody.innerHTML = '<td>' + i18n.t('table_loading') + '</td>';
notify('✅', i18n.t('notify_saved'));
```

### 语言选择器

```html
<select onchange="i18n.setLang(this.value)">
  <option value="en">EN</option>
  <option value="zh-CN">中文</option>
</select>
<script>
  // 初始化选中项
  document.querySelector('.lang-select').value = i18n.getLang();
</script>
```

### 日期格式化按语言切换

```javascript
function formatDate(iso) {
  const d = new Date(iso);
  if (isNaN(d.getTime())) return iso;
  if (i18n.getLang() === 'zh-CN')
    return d.getFullYear() + '年' + (d.getMonth()+1) + '月' + d.getDate() + '日';
  return d.toLocaleDateString('en-US', { year:'numeric', month:'short', day:'numeric' });
}
```

## 表单校验模式

### 集中校验函数

```javascript
function validate() {
  const errors = [];
  // 非空
  if (!field.value.trim()) errors.push(i18n.t('val_empty'));
  // JSON 格式
  try { JSON.parse(jsonField.value); }
  catch(e) { errors.push(i18n.t('val_invalid_json') + ': ' + e.message); }
  // 数值范围
  const v = parseInt(numField.value);
  if (isNaN(v) || v < 1 || v > 28) errors.push(i18n.t('val_range'));
  return { valid: errors.length === 0, errors };
}
```

### 按钮联动

```javascript
// 测试按钮：凭证已填 OR 服务器已有 + 模型非空 → 启用
testBtn.disabled = !((keyFilled || hasKey) && modelsExist);
// 保存按钮：有未保存修改 → 启用
saveBtn.disabled = !dirty;
```

## FastAPI 静态文件挂载

```python
from fastapi.staticfiles import StaticFiles

static_dir = Path(__file__).parent / "static"
app.mount("/static", StaticFiles(directory=str(static_dir)), name="static")
# 文件访问: http://host:port/static/i18n.js
```

注意：`app.mount` 会拦截所有 `/static/*` 请求，**显式路由优先于挂载**。
