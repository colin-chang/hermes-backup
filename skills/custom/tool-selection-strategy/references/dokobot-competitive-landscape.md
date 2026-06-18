# Dokobot 竞品全景（2026-06）

> 深度调研输出，用于未来工具选型时的快速参考。数据随时间衰减。

## Dokobot 核心护城河

| 特性 | Dokobot | 竞品现状 |
|------|---------|----------|
| WASM 像素级视觉分割 | ✅ 独有 | 所有竞品均为 DOM 遍历或无障碍树 |
| 复用日常 Chrome 登录态 | ✅ | bb-browser 需独立实例重登录；Firecrawl 等云服务不走本地浏览器 |
| 输出 LLM 优化（99% token 压缩） | ✅ | 竞品输出 ARIA 树/DOM 树/markdown，非同等优化 |
| Bridge 生命周期管理 | Chrome Native Messaging，关闭即退出 | bb-browser/OpenCLI 均有孤儿进程/端口冲突风险 |
| 本地免费无限量 | ✅ | Firecrawl/Browserbase 有配额限制 |

## 竞品分层

### 直接竞品（同生态位）
- **bb-browser** (MIT): CDP + DOM walk + ARIA 树输出。独立 Chrome 实例。适合自动化，非纯阅读。
- **OpenCLI** (Apache-2.0): DOM Snapshot + 79 个 Site Adapter。复用 Chrome。Adapter 对 API 变更脆弱。
- **Nanobrowser** (Apache-2.0, 13.1k⭐): Chrome 扩展 AI Agent。自动化导向，需自配 LLM API Key。
- **Agent Browser** (Vercel Labs, Rust): CLI 无障碍树方案。独立会话。

### 云 API 替代
- **Firecrawl**: Free→$16/mo。LLM-optimized markdown + Browser Sandbox。
- **Browserbase**: Free→$20/mo。托管 Playwright 浏览器基础设施。
- **ScrapingBee**: $49/mo 起。托管无头 Chrome。
- **Diffbot**: Free→$299/mo。计算机视觉 + 知识图谱，企业级。

### AI Agent 框架（互补，非替代）
- **Browser Use** (78k⭐): Python，89.1% WebVoyager。
- **Stagehand** (21k⭐): TypeScript，Playwright + AI 混合。
- **Skyvern** (20k⭐): 计算机视觉驱动，无需选择器。

## 结论

Dokobot 本地模式在当前时间点（2026-06）是「像素级提取 + 复用登录态 + LLM 优化输出 + 零成本」组合的唯一解。建议以 Dokobot 为阅读工具，需要自动化时补充 bb-browser 或 Browser Use。
