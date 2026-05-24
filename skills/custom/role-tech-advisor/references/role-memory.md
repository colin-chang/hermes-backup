# 技术顾问角色专属记忆

> 本文件存储技术顾问角色的领域知识，由 Agent 在对话中自动更新。
> 与全局 MEMORY.md 互补：共性事实 → 全局；领域知识 → 本文件。


### Vertex Monitor — Vertex AI 预算代理（v3.3，2026-05-24）
- 路径：`/Users/Colin/Developer/Services/VertexMonitor`
- 架构：FastAPI + liteLLM SDK（非 Proxy）+ 双页 Web UI（仪表盘 + 设置）+ i18n 双语（en/zh-CN）
- 仪表盘：Chart.js 暗色主题图表（消费占比环形图 + Token 用量堆叠柱状图）+ 数据表格 + 调用历史
- 设置页：表单前置校验（非空/JSON/数值范围），按钮联动（Key+模型→测试启用），保存后热加载配置
- i18n：`static/i18n.js` 翻译引擎，`data-i18n` 属性 + `i18n.t()` API，右上角语言选择器，localStorage 持久化
- 流式兼容：SSE 包装模式（检测 `stream:true` → 内部 `stream=false` → delta+finish+[DONE] 三块 SSE）
- ⚠️ Docker 镜像层只读：Key 文件必须写入 `/app/data/`（数据卷），非 `/app/`
- ⚠️ Chart.js `generateLabels` 不继承 `labels.color`，必须显式设 `fontColor`
- 静态文件：`app.mount("/static", StaticFiles(...))` 服务 i18n.js
- GitHub 就绪：14 文件清单，`.gitignore` 排除凭证/数据/缓存，`data/.gitkeep` 保目录
- 前端模式详见 `references/frontend-dark-ui-patterns.md`

### Google Sheets 指挥中心
- Master Sheet ID: `10ujCdTHQZKcSxPpbpu3G8myMHUV2V13dhniGRTdK0wU`
- 结构：Overview / Content / Finance

### Mattermost 统一插件 (mattermost-enhancer)\n- 状态：✅ 全部完成（12 源码补丁已迁入插件，mattermost.py 零修改）\n- 插件位置：`~/.hermes/plugins/mattermost-enhancer/`\n- GitHub：`colin-chang/hermes-plugin-mattermost-enhancer`\n- 涵盖能力：\n  - DM 审批（交互卡片 + 回调服务器 + asyncio.Lock 防竞态）\n  - /model 模型切换（select 下拉 + session override + pending_model_notes）\n  - Channel → Thread 模型继承（pre_gateway_dispatch hook）\n  - /new 会话重置（确认卡片）\n  - Clarify 交互卡片渲染（按钮选项 + 「其他」文本输入）\n  - Thread root_id 解析（覆写 send/send_typing/send_local_file/send_url_as_file）\n  - MEDIA 文件缺失静默跳过\n  - **Runtime Footer 内联合并**（v2.2.0，2026-05-24）：流式模式下 footer 不再独立发帖，\n    检测 ` · ` 分隔符 → 编辑上一条 Bot 消息 → 水平线+斜体脚注

### Obsidian 混合云站
- 状态：架构设计完成，等待 Phase 1 (Next.js 初始化)
- 架构：Obsidian+GitHub(CMS) → Cloudflare Pages → GCP Cloud Run

## 开发环境与工具

- Hermes 插件：zenmux-image / zenmux-video（colin-chang GitHub）
- 模型商：ZenMux，精选模型白名单
- Chrome CDP：bb-browser daemon 模式，9222端口

## 技术决策记录

### Ollama 本地模型性能调优（2026-05-19）
- M2 Pro + 32GB 实测：上下文长度是 Apple Silicon 上 prefill 的头号瓶颈
- qwen3.5 默认 262K context → prefill 仅 4 tok/s，限制到 16K → 53 tok/s（13x 提升）
- qwen2.5-coder 20K diff 场景：88s → 15.3s（5.7x），通过 num_ctx=4096 + num_predict=128
- Ollama 创建优化版模型 = Docker 分层：权重共享，仅新增 35-100B 参数层
- VS Code Copilot Agent 模式不适合本地模型（多步串行 80-100s vs 云模型秒级）
- 完整指南：`references/ollama-performance-tuning.md`

### Hermes IM 平台选型（2026-05-18）
- Discord 渲染碎片化（3 根因）→ 短期配置修复 + 源码修复
- 长远方向：Fork hermes-webui 添加 Discord 风格层级（Server/Category/Channel/Thread）+ PostgreSQL 持久化
- 完整对比矩阵：`references/hermes-platform-comparison.md`

## 常用凭证与工具约定

### HLJP Token 获取（开发环境）
- 环境：`https://dev.xymind.cn`，User: `kkkkk` / `123456`
- 获取命令：
  ```bash
  curl -s -X POST "https://dev.xymind.cn/auth/connect/token" \
    -H 'deviceno: 4ba354cd-a7c1-46da-90f6-421b28d9d911' \
    -d 'client_id=HappyCat_Android&client_secret=RKf@Fo^!aUzfeeLs&grant_type=password&username=kkkkk&password=123456' \
    | jq -r '.access_token'
  ```

### 视频信息获取
- 常规工具返回 N/A 时，直接调用系统 ffmpeg：`ffmpeg -i <file> 2>&1`

### 浏览器工具排障
- CDP 连接失败时按顺序尝试：
  1. 先用 bb-browser MCP 工具
  2. 失败 → 用 Playwright 脚本替代（headless:false 时用户可手动登录）
  3. 如 Playwright Chromium 未安装：`cd ~/.hermes/hermes-agent && npx playwright install chromium`
- 不要手动启动 Chrome `--remote-debugging-port=9222` 模式
- `chrome://inspect` 不是开启 CDP 服务，只是客户端发现界面

## 消息平台替代评估

### Mattermost Docker 部署（2026-05-19）
- 项目路径：`/Users/Colin/Developer/Services/Mattermost`
- 重启方式：`bash start.sh`（使用 `docker-compose.without-nginx.yml` 覆写）
- 版本：Team Edition 11.7.0，镜像 `mattermost-team-edition:11.7.0`
- 推送通知：使用 TPNS (`https://push-test.mattermost.com`)，日志 Warning 和移动端弹窗为假阳性，实际推送正常
- 容器代理：已添加 `HTTP_PROXY=http://proxy.orb.internal:8305` 等环境变量
- 详细参考：`references/mattermost-docker-push-notifications.md`

### Discord → Mattermost 迁移评估
- 时间：2026-05-18
- 原因：Discord Markdown 渲染差 + Hermes 消息碎片化（2000字符溢出分片）
- 候选方案对比详见：`hermes-agent` skill → `references/im-platform-comparison.md`
- **Mattermost 为当前最接近理想的选择**：GFM 完整 Markdown（表格+标题+LaTeX）、16384字符上限（根治溢出）、全平台原生客户端（含 iPad）、Docker 自托管
- 待决策：是否启动 Mattermost 本地部署验证

### Telegram MarkdownV2 局限性
- 不支持：表格、标题 H1-H6、有序/无序列表、LaTeX、HTML 标签
- 不适合作为 AI Agent 长内容输出平台


## 配置细节

### Web UI 用户反馈偏好（2026-05-24）
- **通知消息用居中模态弹窗**，不要用角落 toast
- **确认操作用自定义暗色弹窗**，不用浏览器 `confirm()`
- **日期用中文格式**（2026年6月30日），不用 `toLocaleString`
- 所有弹窗支持：点击遮罩关闭 + ESC 关闭

### liteLLM SDK 响应处理陷阱（2026-05-24）
- `litellm.completion()` 返回 `ModelResponse` 对象，**不是 dict**
- 取 `usage`/`choices` 前必须 `resp.model_dump()` 转 dict
- `litellm.completion_cost()` 可直接接受 `ModelResponse`，无需转换

### Docker 容器网络绑定（2026-05-24）
- FastAPI/uvicorn 默认 `host="127.0.0.1"` 在容器内只监听 loopback，宿主机端口映射无效
- 容器化部署必须设 `host="0.0.0.0"`（通过环境变量 `HOST` 传入）
- docker-compose 中设 `environment: - HOST=0.0.0.0`

### Web UI 自动刷新覆盖用户输入（2026-05-24）
- 场景：`setInterval` 定期刷新时，服务器状态会覆盖用户未保存的表单编辑（如 Tab 切换）
- 方案：引入 `dirty` 标志
  - 用户点击 Tab / 修改表单 → `dirty = true` → 显示警告提示
  - 自动刷新到达 → 若 `dirty` 则跳过表单更新，仅刷新只读概览数字
  - 保存成功后 → `dirty = false` → 恢复正常刷新
- 适用于所有有自动刷新 + 表单编辑的 Web UI

### Gemini 3.1 thinking tokens 截断（2026-05-24）
- Gemini 3.1 系列模型在 `max_tokens` 极低（如 5-10）时可能返回 `content: null`
- 原因：模型消耗 token 用于内部推理（thinking blocks），输出 token 不够
- 解决：`max_tokens` 至少设 20+，推荐 50+

### iMessage 发送（2026-05-19）
- 始终加载 `nomad-imessage`（非 builtin `imessage`，后者 bridge 路径已失效）
- 加载方式：`/skill nomad-imessage` 或自然语言触发
- Bridge 脚本在 skill 内：`~/.hermes/skills/custom/nomad-imessage/references/imsg-bridge.command`
- 发送前自动检测 bridge 运行状态（`tmux has-session`），未运行则 `open` + `sleep 2`
- 禁止使用 `osascript send`（假阳性根因：永远返回 exit 0，已导致 4 次重复发送事故）
