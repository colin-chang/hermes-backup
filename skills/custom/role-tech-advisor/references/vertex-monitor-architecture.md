# Vertex Monitor 架构参考

> 创建于 2026-05-24，为 Vertex AI Gemini 提供实时计费代理 + Web UI 仪表盘。

## 项目路径

`/Users/Colin/Developer/Services/VertexMonitor`

## 架构

```
Hermes / Agent → proxy.py (FastAPI :8897) → liteLLM SDK → Vertex AI Gemini
                      │
                      ├─ store.py (双模式计费 + 统计)
                      ├─ static/index.html  (仪表盘: 概览/统计/历史)
                      ├─ static/settings.html (设置页: 凭证/模型/计费/测试)
                      └─ data/store.json (持久化)
```

## 部署

```bash
docker compose up -d   # 本地
# 或
conda activate vertex-monitor && python proxy.py
```

Docker: `python:3.11-slim` → 端口 8897，数据卷 `./data/`，GitHub 暗色主题 Web UI。

## 计费模型

### 自动循环模式（默认）
- 每月 reset_day 号自动归零 spent
- `auto_monthly_amount` = 每月重置后余额
- 示例：每月 1 号 $10 → Google AI Pro 赠金

### 手动模式
- `manual_balance` = 固定余额
- `manual_expires_at` = 截止日期（ISO datetime）
- 到期后所有调用被拦截

两种模式可随时切换，切换时 spent 归零。

## API 端点

| 方法 | 路径 | 说明 |
|------|------|------|
| `GET` | `/` | 仪表盘 Web UI |
| `GET` | `/settings` | 设置页面 Web UI |
| `GET` | `/health` | 健康检查 + 模型列表 |
| `GET` | `/usage` | 预算摘要 |
| `GET` | `/api/config` | 计费配置 + 完整状态 |
| `POST` | `/api/config` | 更新计费配置 |
| `POST` | `/api/reset` | 手动重置本期消费 |
| `GET` | `/api/settings` | 模型列表 + Key 状态 + **key_content（完整 JSON，回填 textarea）** |
| `POST` | `/api/settings` | 更新模型列表 + Vertex Key JSON（验证→写文件→热加载） |
| `GET` | `/api/stats` | 模型消费统计 |
| `GET` | `/api/history?limit=N` | 调用历史 |
| `POST` | `/api/test` | 连通性测试（优先 gemini-3.1-flash-lite） |
| `POST` | `/v1/chat/completions` | OpenAI 兼容聊天补全 |

### 402 预算耗尽响应

```json
{
  "error": "budget_exhausted",
  "message": "余额已耗尽",
  "spent": 10.000024,
  "remaining": 0.0,
  "balance": 10.0,
  "mode": "auto_recurring"
}
```

## 模型白名单

`config.json` → `models` 字段控制。当前 13 个模型：

| 系列 | 模型 ID | 上下文 | 状态 |
|------|--------|--------|------|
| Gemini 3.x | `gemini-3.5-flash` | 1M | 稳定 |
| | `gemini-3.1-flash-lite` | 1M | 稳定 |
| | `gemini-3.1-pro-preview` | 1M | 预览 |
| | `gemini-3.1-pro-preview-customtools` | 1M | 预览 |
| | `gemini-3-flash` | 1M | 预览 |
| Gemini 2.5 | `gemini-2.5-pro` | 2M | 稳定 |
| | `gemini-2.5-flash` | 1M | 稳定 |
| | `gemini-2.5-flash-lite` | 1M | 稳定 |
| | `gemini-2.5-flash-live-api` | 1M | 稳定 |
| Gemini 2.0 | `gemini-2.0-flash` | 1M | 稳定 |
| | `gemini-2.0-flash-lite` | 1M | 稳定 |
| Gemini 1.5 | `gemini-1.5-pro` | 2M | 遗留 |
| | `gemini-1.5-flash` | 1M | 遗留 |

**排除**：图片/视频生成模型（`*-flash-image`、`*-pro-image`、Veo、Imagen）和需单独部署的 Gemma。

## 文件职责

| 文件 | 职责 |
|------|------|
| `proxy.py` | FastAPI 服务：端点 + liteLLM 调用 + 计费拦截 + SSE 流式包装 + Web UI 托管 |
| `store.py` | 数据层：BillingConfig + 消费追踪 + 模型统计 + JSON 持久化 |
| `static/index.html` | 仪表盘：余额概览 + Chart.js 图表 + 模型分布表 + 调用历史 + 累计统计 + 导航栏 + 语言选择器 |
| `static/settings.html` | 设置页：Vertex 凭证管理 + 模型列表编辑 + 计费模式 + 连通性测试（含按钮联动、表单校验） |
| `static/i18n.js` | 翻译引擎：en/zh-CN 双语字典 + `i18n.t()` API + localStorage 持久化 + `data-i18n` DOM 自动应用 |
| `config.json` | 项目配置（项目 ID/区域/默认模型/模型白名单/凭证路径） |

## i18n 双语支持

### 架构
`static/i18n.js` — 单文件翻译引擎，无外部依赖。两个页面 (`index.html`, `settings.html`) 共享同一引擎。

```
static/i18n.js
  ├─ messages.en / messages['zh-CN']  — 翻译字典
  ├─ i18n.getLang()  → localStorage('vm_lang') || 'en'
  ├─ i18n.setLang(lang)  → localStorage + location.reload()
  ├─ i18n.t(key)  → 当前语言翻译文本（fallback → en → key）
  └─ DOMContentLoaded → 遍历 [data-i18n] 属性自动替换
```

### 语言切换器
右上角 `<select class="lang-select">` → `onchange="i18n.setLang(this.value)"` → 页面重载。

```html
<select class="lang-select" onchange="i18n.setLang(this.value)">
  <option value="en">EN</option>
  <option value="zh-CN">中文</option>
</select>
```

**CSS 要点**：`<select>` 在 flex nav 中与 pill 链接并排时，必须显式设 `height: 30px` + `border-radius: 20px` + `vertical-align: middle`，否则 `<select>` 默认高度与链接不一致导致布局错位。

选择后 `localStorage` 持久化，下次访问自动恢复。默认 `en`。

### data-i18n 属性
静态文本用 HTML 属性标记，`DOMContentLoaded` 时自动替换：

```html
<!-- 纯文本 -->
<span data-i18n="label_remaining">Remaining</span>

<!-- placeholder -->
<textarea data-i18n="key_placeholder" placeholder="..."></textarea>

<!-- title -->
<title data-i18n="nav_title">Vertex Monitor</title>
```

### JS 动态文本
图表标签、校验消息、通知弹窗等动态内容调用 `i18n.t()`：

```javascript
// 图表
label: i18n.t('chart_prompt')

// 校验错误
errors.push(i18n.t('val_model_empty'));

// 通知
notify('✅', i18n.t('notify_saved'));
```

### 新增翻译 key 清单
在 `i18n.js` 的 `messages.en` 和 `messages['zh-CN']` 中同步添加。命名规范：`模块_含义`（如 `val_model_empty`、`chart_cost_title`、`key_help_step1`）。

跨模块共用 key 用 `common_` 前缀（如 `common_or`、`common_confirm_reset`）。

### 语言切换对页面影响
切换语言 → `location.reload()` → 所有 `data-i18n` 元素重新翻译 + JS 重新调用 `i18n.t()` → 包括图表、表格、日期格式（`formatDate` 按语言切换 `zh-CN` / `en-US` 格式）。

## GitHub 发布清单

### `.gitignore` 结构
```
# Python
__pycache__/  *.py[cod]  dist/  build/  *.egg-info/

# 环境
venv/  .venv/  .env

# IDE
.vscode/  .idea/  *.swp

# 系统
.DS_Store  Thumbs.db

# Vertex Monitor
vertex-key.json  *.log
data/*           # 忽略所有数据内容
!data/.gitkeep   # 但保留目录结构占位
```

### 提交文件清单（14 文件）
```
.dockerignore  .gitignore  Dockerfile  README.md  config.json
data/.gitkeep  docker-compose.yml  environment.yml
proxy.py  store.py  requirements.txt  test_vertex.py
static/index.html  static/settings.html  static/i18n.js
```

### 清理项（不上传）
- `vertex-key.json` — GCP 服务账号私钥
- `data/store.json` / `data/store_history.jsonl` — 真实计费/调用数据
- `__pycache__/` — Python 构建缓存
- `cost_store.py` — v1 废弃代码（已删）

## Hermes 接入

在 `~/.hermes/config.yaml` 的 `custom_providers` 中添加（block-style YAML，非 inline `{...}`）：

```yaml
custom_providers:
  - name: vertex-budget
    base_url: http://localhost:8897/v1
    api_key: noop
    model: gemini-3.1-flash-lite
    models:
      gemini-3.5-flash:
        context_length: 1048576
      gemini-3.1-flash-lite:
        context_length: 1048576
      gemini-3.1-pro-preview:
        context_length: 1048576
      gemini-3.1-pro-preview-customtools:
        context_length: 1048576
      gemini-3-flash:
        context_length: 1048576
      gemini-2.5-pro:
        context_length: 2097152
      gemini-2.5-flash:
        context_length: 1048576
      gemini-2.5-flash-lite:
        context_length: 1048576
      gemini-2.5-flash-live-api:
        context_length: 1048576
      gemini-2.0-flash:
        context_length: 1048576
      gemini-2.0-flash-lite:
        context_length: 1048576
      gemini-1.5-pro:
        context_length: 2097152
      gemini-1.5-flash:
        context_length: 1048576
```

## 已知陷阱

### liteLLM ModelResponse
`litellm.completion()` 返回 `ModelResponse` 对象，不是 dict。取 `usage`/`choices` 前必须 `resp.model_dump()`。

### Docker 网络
容器内 uvicorn 默认 `host=127.0.0.1` 只在容器内 loopback 监听，宿主机端口映射无效。必须设 `host=0.0.0.0`。

### Docker 只读文件系统：凭证必须写入数据卷
Docker 镜像层（`/app/`）为只读。`POST /api/settings` 接收的 Key JSON 写入 `/app/vertex-key.json` 会触发 `OSError: [Errno 30] Read-only file system`。

**修复**：凭证统一写入 `/app/data/vertex-key.json`（`_data_dir / creds_filename`），启动时优先从数据卷读取，回退到应用目录：

```python
_data_dir = Path(__file__).parent / "data"
_data_dir.mkdir(parents=True, exist_ok=True)
_creds_in_data = _data_dir / _credentials_filename

if _creds_in_data.exists():
    os.environ["GOOGLE_APPLICATION_CREDENTIALS"] = str(_creds_in_data.resolve())
elif _creds_in_app.exists():
    os.environ["GOOGLE_APPLICATION_CREDENTIALS"] = str(_creds_in_app.resolve())
```

`docker-compose.yml` 中 `./data:/app/data` 挂载确保该目录可读写。

### 数据持久化：STORE_PATH 必须在挂载目录内
`store.py` 的 `STORE_PATH` 默认值为 `Path(__file__).parent / "store.json"`（即 `/app/store.json`），但 `docker-compose.yml` 只挂载 `./data:/app/data`。数据写入容器根目录，重启即丢失。

**修复**：默认路径改为 `_DATA_DIR / "store.json"`，其中 `_DATA_DIR = Path(__file__).parent / "data"`，并 `mkdir(exist_ok=True)`。同时 `proxy.py` 的 history 查询路径从 `store_history.jsonl` 改为 `data/store_history.jsonl`。

### YAML 代码块格式：只用 block style，禁止 inline flow
Hermes `custom_providers` 的 `models:` 字段使用标准 block-style YAML：
```yaml
# ✅ 正确
models:
  gemini-3.5-flash:
    context_length: 1048576

# ❌ 错误（inline flow）
models:
  gemini-3.5-flash: { context_length: 1048576 }
```
此项适用于所有面向用户的 YAML 示例（Web UI modal、README、skill references）。

### Gemini 3.1 thinking tokens
`max_tokens` 过低（<10）时可能返回 `content: null`——模型消耗 token 用于内部推理，无输出 token。建议 `max_tokens ≥ 20`。

### Hermes 流式兼容：SSE 包装模式

**背景**：Hermes 全局 `streaming: true` → 所有请求发 `stream: true`。Vertex Monitor 不实现真正的 SSE 流式传输（litellm 的 Vertex adapter 流式不稳定），但必须返回 SSE 格式否则 Hermes 解析失败 → "Empty response"。

**方案**：代理检测 `stream: true` 请求 → 内部调用 litellm 时强制 `stream=False` → 获得完整响应后包装为 SSE 格式返回。

```python
client_wants_stream = body.get("stream", False)
if client_wants_stream:
    # 构造 delta chunk + finish chunk + [DONE]
    def sse_generator():
        yield f"data: {json.dumps(chunk_content)}\n\n"
        yield f"data: {json.dumps(chunk_done)}\n\n"
        yield "data: [DONE]\n\n"
    return StreamingResponse(sse_generator(), media_type="text/event-stream")
```

**关键细节**：
- `chunk_content` — `object: "chat.completion.chunk"`, `delta: {content: "..."}`, `finish_reason: null`
- `chunk_done` — `delta: {}`, `finish_reason: "stop"`, 含 `usage` + `_budget`
- 非流式请求仍走原路径 `JSONResponse`，不受影响
- 此模式适用于**任何不支持流式但需兼容流式客户端的代理**

### Key 文件命名
GCP 服务账号 JSON 密钥统一命名为 `vertex-key.json`（非 `ai-project-384207-*.json`）。获取方式见项目 README →「获取 GCP 服务账号 Key」章节。

### Web UI 连通性测试

位于**设置页面**（`/settings`）。「🔍 测试连通性」按钮 → `POST /api/test` → 优先用 `gemini-3.1-flash-lite`（避免 thinking token 截断）。

**按钮联动逻辑**：
- Key 未填 **且** 服务器无已保存 Key → 按钮 `disabled`
- (Key 已填 **或** 服务器已有 Key) 且 模型非空 → 按钮 `enabled`（点击时自动先保存设置再测试）
- 有未保存修改 → 「💾 保存设置」按钮 `enabled` + ⚠ 提示

`updateButtonStates()` 中测试按钮条件：`!((keyFilled || hasKey) && modelsExist)`。`hasKey` 来自 `GET /api/settings` 响应的 `has_key` 字段，确保保存后即使 textarea 清空按钮仍可用。

测试不消耗预算（不经过 `record_call`）。默认响应包含模型和响应内容。

## Chart.js 暗色主题集成

仪表盘使用 Chart.js v4.4 CDN 无外部依赖。两个图表并排（flex `chart-grid`）：

### 环形图（消费占比）
- `type: 'doughnut'`，图例在右侧
- 自定义 `generateLabels` 在标签中显示金额：`3.1-flash-lite  $0.001234`
- Tooltip 显示百分比：`$0.001234 (45.2%)`
- 边框色 `#161b22`（卡片背景色），2px 宽，与暗色主题无缝融合
- **图例颜色**：`options.plugins.legend.labels.color: '#c9d1d9'` + `generateLabels` 返回的每个 item 必须加 `fontColor: '#c9d1d9'`。两者缺一不可——`labels.color` 只覆盖内置 labels，自定义 `generateLabels` 不继承该值，默认回退到黑色，在暗色主题下不可见

### 横向堆叠柱状图（Token 用量）
- `type: 'bar'` + `indexAxis: 'y'`
- 两个数据集：Prompt（蓝 `#58a6ff`）+ Completion（绿 `#3fb950`），均 `stacked: true`
- X 轴标签缩写：≥1B → `1.2B`，≥1M → `3.5M`，≥1K → `500K`
- Y 轴无网格线（`grid: { display: false }`）

### 全局默认配置
```javascript
Chart.defaults.color = '#8b949e';  // muted text
Chart.defaults.borderColor = 'rgba(48,54,61,0.5)';  // border color
Chart.defaults.font.family = "-apple-system, ...";
Chart.defaults.font.size = 11;
```

### 调色板
15 色 GitHub 风格：`#58a6ff`(蓝), `#3fb950`(绿), `#d2991d`(黄), `#f85149`(红), `#bc8cff`(紫), `#f778ba`(粉), ...

### 无数据时
图表隐藏（`chartArea.style.display = 'none'`），仅显示 "暂无数据" 表格行。

## 配置热加载模式

`POST /api/settings` 接收新配置后不仅要写 `config.json` 还要立即重载模块级全局变量，否则正在运行的请求仍使用旧模型列表/凭证：

```python
# 写文件
CONFIG_PATH.write_text(json.dumps(cfg, ...), encoding="utf-8")

# 热加载全局变量
global _config, ALLOWED_MODELS, VERTEX_PROJECT, VERTEX_LOCATION
_config = cfg
ALLOWED_MODELS = set(cfg.get("models", []))
VERTEX_PROJECT = cfg.get("vertex_project", ...)
VERTEX_LOCATION = cfg.get("vertex_location", ...)
```

适用场景：任何 FastAPI 服务在运行时通过 API 更新配置文件后需要立即生效的模块级变量。

## 表单校验模式（单文件 HTML）

设置页 `validate()` 函数统一前置校验，返回 `{valid: bool, errors: []}`。校验规则：

| 字段 | 校验 |
|------|------|
| 模型列表 | 非空，每行 trim |
| Key JSON | 若填写：`JSON.parse()` 合法性 + `private_key`/`client_email` 字段 |
| 自动循环 | `reset_day` 1-28，`monthly_amount` >= 0 |
| 手动设定 | `balance` >= 0，`expires_at` 非空 |

错误以列表弹窗展示：`⚠️ 请修正以下问题：\n· 模型列表不能为空\n· Key JSON 格式无效：...`。

`saveAll()` 和 `testAndSave()` 均在入口调用 `validate()`，不通过拒绝执行。后端错误也提取具体消息（`d.detail.message`）而非泛化提示。
