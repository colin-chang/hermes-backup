# OpenCLI × Hermes 集成参考

> 调研日期：2026-06-20 | OpenCLI v1.8.4 | Engine: Node.js ≥ 20

## 架构概览

```
AI Agent (Hermes / Claude Code / Codex)
       │ terminal("opencli <site> <command>")
       ▼
opencli CLI ──HTTP──▶ Daemon (port 19825) ──WebSocket──▶ Chrome Extension (Browser Bridge)
                                                              │
                                                              ▼
                                                        你的真实 Chrome
                                                     （复用所有登录态）
```

**关键差异 vs bb-browser：**
- OpenCLI **不需要独立 Chrome 实例**，直接复用它你现有的 Chrome
- 通过 Browser Bridge 扩展 + 本地 daemon 通信
- 安装验证：`npm install -g @jackwener/opencli` + Chrome Web Store 扩展 + `opencli doctor`

---

## OpenCLI 的多层能力

### Layer 1：浏览器自动化（Hermes 互补）

```bash
opencli browser work open <url>       # 导航（复用登录态）
opencli browser work snapshot         # DOM 快照（13 阶段管线）
opencli browser work click @3         # 点击
opencli browser work type "text"      # 输入
opencli browser work extract <sel>    # 提取
opencli browser work eval "js"        # JS 执行
opencli browser work screenshot       # 截图
opencli browser work network          # 网络抓包
```

**→ Hermes 内置 `browser_*` 工具已覆盖核心交互功能。用 opencli browser 的场景：需要复用现有 Chrome 登录态时。**

### Layer 2：Site Adapters（OpenCLI 独有价值）

```bash
opencli <site> <command> [args]
```

100+ 站点 × 数百条命令，直接用你浏览器里的 Cookie 调网站 API，**零 LLM Token 成本**。

### Layer 3：CLI Hub + 桌面应用

```bash
opencli gh issue list               # GitHub CLI 透传
opencli docker ps                   # Docker CLI 透传
opencli obsidian note "xxx"         # Obsidian CLI 透传
opencli cursor read                 # Cursor 桌面应用适配器
opencli chatgpt-app ask "prompt"    # ChatGPT 桌面版
```

### Layer 4：下载支持

```bash
opencli bilibili download BV1xxx
opencli xiaohongshu download "url"
opencli twitter download elonmusk --limit 20
opencli 1688 download <id>
```

---

## 与 Hermes 工具的关系矩阵

| 任务 | Hermes 方式 | OpenCLI 方式 | 选择 |
|------|------------|-------------|------|
| 搜 Twitter 推文 | — | `terminal("opencli twitter search ... -f json")` | **OpenCLI** |
| 刷知乎热榜 | `browser_navigate + snapshot` | `terminal("opencli zhihu hot -f json")` | **OpenCLI**（更快） |
| 查雪球股票 | — | `terminal("opencli xueqiu stock AAPL -f json")` | **OpenCLI** |
| YouTube 搜索 | `browser_navigate + 多次操作` | `terminal("opencli youtube search ... -f json")` | **OpenCLI** |
| 通用网页交互 | `browser_navigate/snapshot/click` | `opencli browser work open/click/fill` | **Hermes `browser_*`** 优先 |
| 需要登录态的网页 | `/browser connect` → `browser_*` | `opencli browser work open <url>` | **OpenCLI**（无需 `/browser connect`） |
| 桌面应用控制 | — | `terminal("opencli cursor read")` | **OpenCLI 独有** |
| 中文平台搜索 | `dokobot read --local` | `terminal("opencli zhihu/xiaohongshu search ...")` | **OpenCLI**（直接调 API） |

---

## Site Adapter 选择决策

```
目标平台有 opencli adapter？
├── YES → terminal("opencli <site> <command> -f json")  ← 首选
│         零 Token 成本，秒级返回，确定性输出
└── NO  → Hermes browser_* 工具 或 opencli browser
          通用浏览器自动化回退
```

---

## 注意事项

1. **`-f json` 而非 `--json`**：OpenCLI 使用 `-f` 指定格式（`json`/`csv`/`md`/`yaml`），与 bb-browser 的 `--json` 不同
2. **`opencli browser` 需要 session 参数**：`opencli browser <session> <command>`，session 是任意命名
3. **Daemon 自动管理**：首次使用时 auto-start，端口 19825
4. **多 Chrome profile**：`opencli profile list` / `opencli profile use <id>` 切换
5. **站点适配器依赖 API 合约**：网站 API 变更时 adapter 可能失效，社区维护
