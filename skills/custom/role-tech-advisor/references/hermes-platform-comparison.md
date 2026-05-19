# Hermes 消息平台对比：渲染 + 层级 + 持久化

> 调研日期：2026-05-18 | 用途：Hermes 主力 IM 平台选型决策参考

## 背景

Discord 拥有业界最好的多级分类体系（Server→Category→Channel→Thread），但 Hermes 的 Discord 适配器存在严重的消息碎片化问题。Hermes WebUI 渲染完美但无层级结构。需要评估所有可行方案。

## Hermes 平台渲染能力分层（官方 Tier 体系）

| Tier | 平台 | 编辑支持 | 工具进度 | 适用场景 |
|------|------|---------|---------|---------|
| Tier 1 | Telegram, Discord | 完整编辑 | 实时 | 主力交互 |
| Tier 2 | Slack, Mattermost, Matrix, Feishu | 编辑支持 | 默认关闭 | 团队协作 |
| Tier 3 | Signal, WhatsApp, BlueBubbles, WeCom, DingTalk, WeChat | 无编辑 | N/A | 通知推送 |
| Tier 4 | Email, SMS, Webhook, HomeAssistant | 批量投递 | N/A | 定时报告 |

## Discord 碎片化三大根因

详见 `hermes-agent` skill 的 `references/discord-streaming-fragmentation.md`：

1. **溢出分片**（>1900 字符硬拆分）— `stream_consumer.py` 安全阈值 = `MAX_MESSAGE_LENGTH - 100`
2. **工具进度独立消息** — `tool_progress: all` 时每次工具调用发独立气泡
3. **Commentary 段分隔** — `_COMMENTARY` 队列和 `_NEW_SEGMENT` 信号强制新消息

## 候选平台深度对比

| 维度 | Discord | Telegram | Mattermost | Zulip | Slack |
|------|---------|----------|------------|-------|-------|
| 层级深度 | 4 级 ✅ | 3 级 ⚠️ | 3 级 ⚠️ | 2 级(扁平) | 3 级 |
| Category 层 | ✅ 原生 | ❌(Folder 用户端) | ❌(命名约定) | ✅(Stream) | ⚠️(Section) |
| Markdown 渲染 | ⭐⭐⭐ | ⭐⭐⭐⭐ | ⭐⭐⭐⭐ | ⭐⭐⭐⭐ | ⭐⭐⭐⭐ |
| Hermes 渲染 | Tier 1 | Tier 1 | Tier 2 | ❌ 无原生 | Tier 2 |
| 持久化存储 | ✅ 云端 | ✅ 云端 | ✅ 自托管 | ✅ 自托管 | ⚠️ 付费 |
| 全文搜索 | ✅ | ✅ | ✅(ES/PG) | ✅(PG) | ✅(付费) |
| 自托管 | ❌ | ❌ | ✅ | ✅ | ❌ |
| 2000 字符限制 | ✅ 硬限制 | ❌(4096) | ❌(16384) | ❌(10000) | ❌(40000) |

## 三大自主技术方案

### 方案 A：Discord 渲染根治
- 修复 `stream_consumer.py` 溢出逻辑 → 首条截断 + 文件附件
- 工具进度 → Preview-Delete 模式（仿 OpenClaw）
- Commentary → 内联编辑到主消息
- **优势**：Discord 层级全保留，渐进式修复
- **劣势**：需维护源码补丁；2000 字符硬限制不可消除

### 方案 B：Telegram 主力
- 利用 Telegram Topics 实现 Folder→Supergroup→Topic→Thread 三级
- Tier 1 渲染，无碎片问题
- Discord 降级为社区入口
- **优势**：零代码改动，渲染优秀
- **劣势**：Folder 是用户端概念；不支持 Markdown 表格

### 方案 C：Hermes WebUI 定制扩展
- Fork hermes-webui，添加 Server/Category/Channel/Thread 层级
- PostgreSQL + FTS 全文检索
- 数据模型：servers → categories → channels → threads → messages
- **优势**：完美渲染 + 完美层级，完全自主可控
- **劣势**：开发工作量最大（Phase 1: 3-5天 MVP, 完整版: 4-6周）

## 推荐路线

```
Week 1-2: 方案 A 配置修复（tool_progress: off + SOUL.md 约束）
Week 3-4: 方案 A 源码修复（溢出合并 + Preview-Delete）
Month 2-3: 方案 C Phase 1（WebUI Channel/Session 绑定 + SQLite）
Month 4+:  方案 C 完整版（PostgreSQL + 全文检索 + 权限）
```
