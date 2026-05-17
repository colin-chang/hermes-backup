# 技术顾问角色专属记忆

> 本文件存储技术顾问角色的领域知识，由 Agent 在对话中自动更新。
> 与全局 MEMORY.md 互补：共性事实 → 全局；领域知识 → 本文件。

## 进行中的项目

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
<!-- Agent: 在此记录重要的技术决策 -->

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

## 配置细节
<!-- Agent: 在此记录值得保留的配置经验 -->
