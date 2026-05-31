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

### Mattermost 统一插件 (mattermost-enhancer)\n- 状态：✅ 全部完成（P1/P6 已从 shell patch 迁入插件 adapter override；shell patches 现为 5 个（P1-P5，旧 P2-P5/P7 重编号））\n- 插件位置：`~/.hermes/plugins/mattermost-enhancer/`\n- GitHub：`colin-chang/hermes-plugin-mattermost-enhancer`\n- 涵盖能力：\n  - DM 审批（交互卡片 + 回调服务器 + asyncio.Lock 防竞态）\n  - /model 模型切换（select 下拉 + session override + pending_model_notes）\n  - Channel → Thread 模型继承（pre_gateway_dispatch hook）\n  - /new 会话重置（确认卡片）\n  - Clarify 交互卡片渲染（按钮选项 + 「其他」文本输入）\n  - Thread root_id 解析（覆写 send/send_typing/send_local_file/send_url_as_file）\n  - MEDIA 文件缺失静默跳过\n  - **Runtime Footer 内联合并**（v2.2.0，2026-05-24）：流式模式下 footer 不再独立发帖，\n    检测 ` · ` 分隔符 → 编辑上一条 Bot 消息 → 水平线+斜体脚注

### Obsidian 混合云站
- 状态：架构设计完成，等待 Phase 1 (Next.js 初始化)
- 架构：Obsidian+GitHub(CMS) → Cloudflare Pages → GCP Cloud Run

## 开发环境与工具

- Hermes 插件：zenmux-image / zenmux-video（colin-chang GitHub）
- 模型商：ZenMux，精选模型白名单
- Chrome CDP：bb-browser daemon 模式，9222端口

## 技术决策记录

### Hermes v0.14.0 升级 — Mattermost 插件兼容性审计与修复（2026-05-27）
- 升级触发 6 个问题（P1-P6）：2 阻断 + 3 中 + 1 低
- **P1**: 插件 `register_platform` 覆盖 bundled plugin 时丢失 `apply_yaml_config_fn` → config.yaml 配置静默失效
  - 修复：显式导入 bundled 的 `_apply_yaml_config` 并传入 `register_platform`
  - 通用模式：覆盖 `register_platform` 时必须检查并携带所有 hooks（详见 `references/hermes-platform-plugin-override.md`）
- **P2**: 脚本检查模式过期（上游已修复 Thread 进度路由）
  - 修复：check 用兼容新旧格式的正则；apply 函数预检新格式并跳过
- **P3**: MAX_POST_LENGTH=4000 过小 → 跳过（等待 P1/P2 验证后再处理）
- **P4**: `truncate_message` 幽灵代码围栏 → 在 carry_lang 重新打开 fence 前检测剩余内容首行是否为 bare ` ``` `
  - 已注册 `hermes-patches.sh` P53
- **P5**: WebSocket 频繁重连（close 258=WSMsgType.CLOSED） → 心跳 30s→15s
  - 已注册 `hermes-patches.sh` P54
- **P6**: 时区误配 → 跳过（用户已在深圳确认 Asia/Shanghai 正确）
- 修复后需执行 `hermes gateway restart` 才能生效
- Patch 脚本同步更新：注册表 + header 注释 + 检查模式一致性

### 源码修改工作流补充（2026-05-27）
- 修改源码后必须同步更新对应 patch 脚本（`hermes-patches.sh` 或 `hermes-mattermost-enhancer.sh`）
- 注册表、`_do_patch` 检查模式、header 注释三者必须一致
- 修复完成后用 `check` 命令验证全部通过
- ⚠️ **验证上游合入时必须以 `origin/main` 为基准**（`git show origin/main:<file>`），不是 `HEAD` 或本地副本。本地 check 通过仅表示本机已打过 patch，不代表上游已修复。详见 `hermes-config-management` → ` references/hermes-patches-upstream-check.md`

### Mattermost MAX_POST_LENGTH 截断问题（2026-05-25）
- `gateway/platforms/mattermost.py` 硬编码 `MAX_POST_LENGTH = 4000`（OpenClaw 遗留）
- 长消息被 `truncate_message()` 拆分后 CRT Thread 折叠 → 用户只看到第一段
- Mattermost 实际支持 16383 字符
- **已修复**：`MAX_POST_LENGTH = int(os.getenv("MATTERMOST_MAX_POST_LENGTH", "16000"))`
- `.env` 需手动添加：`MATTERMOST_MAX_POST_LENGTH=16000`
- 已注册为 `hermes-patches.sh` P51，`hermes update` 后 `hermes-patches.sh apply` 可恢复
- 完整分析：`mattermost-operations` Skill → `references/mattermost-message-truncation.md`

### Mattermost iPad 端表格压缩 CSS 根因（2026-05-25）
- `.table-responsive` 缺 `overflow-x: auto`（仅 `direction: ltr`）→ 空壳
- `.post-message` 的 `overflow: clip` 在 iOS Safari 更激进
- `table-layout: fixed` + HTML `<table>` 的 `max-width: 100%` → 向内压缩
- 展开独立页面正常是因为脱离 post 容器链
- 完整分析：`mattermost-operations` Skill → `references/ipad-table-rendering.md`

### 源码修改工作流（2026-05-25 用户明确要求）
- **先汇报再动手**：涉及源码直接修改时，先出示完整的根因报告和修复方案供审阅
- 用户明确说"先不要改，先给我原因和报告供我审阅，我同意之后再去修改代码"
- 必须等用户确认方案后再执行修改，不可直接 `patch` 源码文件
- 涉及 Hermes 官方代码的修改必须注册到 `hermes-patches.sh`（防止 `hermes update` 覆盖）

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

### 消息平台决策（已落地：Mattermost）
- **2026-05-18 评估**：Discord/Telegram/Mattermost 三选一 → Mattermost 胜出（GFM 完整 Markdown + 16384 字符上限 + 全平台原生客户端）
- **部署**：`/Users/Colin/Developer/Services/Mattermost`，`bash start.sh` 启动，Team Edition 11.7.0
- **推送通知**：TPNS（`push-test.mattermost.com`），日志 Warning 和移动端弹窗为假阳性，实际推送正常
- **容器代理**：已添加 `HTTP_PROXY=http://proxy.orb.internal:8305`
- **Telegram**：不支持表格/标题/LaTeX，不适合 AI Agent 长内容输出

### Web UI 用户反馈偏好（2026-05-24）
- **通知消息用居中模态弹窗**，不要用角落 toast
- **确认操作用自定义暗色弹窗**，不用浏览器 `confirm()`
- **日期用中文格式**（2026年6月30日），不用 `toLocaleString`
- 所有弹窗支持：点击遮罩关闭 + ESC 关闭

### 常见陷阱速查
- **Web UI 自动刷新覆盖用户输入** → 引入 `dirty` 标志，跳过脏表单的自动刷新
- **FastAPI 容器部署** → 必须设 `host="0.0.0.0"`（环境变量 `HOST` 传入），`127.0.0.1` 容器内不可达
- **liteLLM `completion()`** 返回 `ModelResponse` 对象，取 `usage`/`choices` 前须 `model_dump()` 转 dict
- **Gemini 3.1 thinking tokens** → `max_tokens < 20` 可能返回 `content: null`（thinking 耗尽 token 预算），设 ≥ 50

### iMessage 发送
- Bridge：`~/.hermes/skills/nomad-imessage/references/imsg-bridge.command`
- 发送前检测 `tmux has-session`，未运行则 `open` + `sleep 2`
- ⚠️ 禁止 `osascript send`（假阳性：永远返回 exit 0，已致 4 次重复发送）