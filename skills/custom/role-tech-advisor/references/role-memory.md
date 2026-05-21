# 技术顾问角色专属记忆

> 本文件存储技术顾问角色的领域知识，由 Agent 在对话中自动更新。
> 与全局 MEMORY.md 互补：共性事实 → 全局；领域知识 → 本文件。

## 进行中的项目

### Mattermost 统一插件 (mattermost-approval)
- 状态：阶段二完成（DM 审批迁移），等待 gateway 重启验证
- 阶段一 ✅：环境检查（Hermes v0.14.0 / plugins dir / register_platform API）
- 阶段二 ✅：插件骨架创建（7 文件），config.yaml 已启用
- 阶段三 ⏳：Slash 指令扩展（/model /new 卡片交互）
- 阶段四 ⏳：收尾（API 契约文档 / patches 7 移除）
- 插件位置：`~/.hermes/plugins/mattermost-approval/`
- 开发计划：`~/.hermes/workspace/mm-plugin-development-plan.md`
- 关键认知：
  - register_platform() 实际 API：adapter_factory(工厂函数) + check_fn，非 adapter_class + priority
  - Plugin 入口：register(ctx) 函数（非 on_load）
  - _create_adapter() 先查 registry → 再 fallback 内置，无 priority 机制
  - 阶段二子类用 pass 即可（全部继承父类 patches 代码）

### Obsidian 混合云站
- 状态：架构设计完成，等待 Phase 1 (Next.js 初始化)
- 架构：Obsidian+GitHub(CMS) → Cloudflare Pages → GCP Cloud Run

### Google Sheets 指挥中心
- Master Sheet ID: `10ujCdTHQZKcSxPpbpu3G8myMHUV2V13dhniGRTdK0wU`
- 结构：Overview / Content / Finance

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
<!-- Agent: 在此记录值得保留的配置经验 -->

### iMessage 发送（2026-05-19）
- 始终加载 `imessage-nomad`（非 builtin `imessage`，后者 bridge 路径已失效）
- 加载方式：`/skill imessage-nomad` 或自然语言触发
- Bridge 脚本在 skill 内：`~/.hermes/skills/custom/imessage-nomad/references/imsg-bridge.command`
- 发送前自动检测 bridge 运行状态（`tmux has-session`），未运行则 `open` + `sleep 2`
- 禁止使用 `osascript send`（假阳性根因：永远返回 exit 0，已导致 4 次重复发送事故）
