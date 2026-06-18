# AI 平台对比：Coze / Dify / n8n

> 调研时间：2026-06-08
> 触发场景：用户纠错 Coze 私有化部署表述 + 深入询问 Coze Studio 与 Coze SaaS 差异

---

## Coze 的双重身份（关键认知）

Coze 有两个完全不同的东西，混淆它们是常见错误：

| | **Coze SaaS**（扣子） | **Coze Studio**（开源版） |
|---|---|---|
| **入口** | coze.cn / coze.com | github.com/coze-dev/coze-studio（20.9k ⭐） |
| **定位** | 字节跳动的 AI 团队协作 SaaS 平台 | 开源的 AI Agent 核心引擎 |
| **协议** | 闭源 | Apache 2.0 |
| **部署** | 纯云端 SaaS | Docker/docker-compose + K8s Helm Chart |
| **技术栈** | 闭源 | Go 后端 + React/TypeScript 前端，DDD 微服务 |
| **最新版本** | — | v0.5.1（2026.2.5） |

**⚠️ 表述铁律**：说 Coze 支持私有化部署时，必须明确是 Coze Studio 开源项目而非 Coze SaaS。coze.cn 官方产品文档中没有私有化部署章节——私有化部署入口在 GitHub。

---

## 三者定位一句话

| 平台 | 一句话 |
|------|--------|
| **Coze SaaS** | AI 团队协作工作台——人+Agent 像真团队一样协作（Agent Teams、Vibe Coding、视频创作全流程） |
| **Coze Studio** | Coze 核心引擎的开源版——Agent 搭建/工作流/知识库/模型管理的基础能力，**不含团队协作** |
| **Dify** | 开源企业级 LLM 应用平台——RAG 和知识库是看家本领 |
| **n8n** | 开源万能工作流自动化引擎——400+ 连接器，什么系统都能串 |

---

## Coze Studio 开源版功能清单

### ✅ 包含
- 模型管理（OpenAI / 火山引擎等）
- 搭建单个 Agent（创建/发布/管理，支持配置工作流+知识库）
- 可视化工作流编排
- 基础资源管理：插件（仅 18 个基础插件）、知识库（仅本地文档）、数据库、Prompt
- Chat API + Chat SDK
- Docker 一键部署（最低 2C/4G）

### ❌ 不包含（商业版专属）
- **Agent Teams 多人多 Agent 协作**（无多用户体系/权限管理）
- **技能商店**（商业版成千上万插件，开源版仅 18 个）
- **Vibe Coding** 项目级编程
- **视频创作全流程**
- **接入本地 Agent**（Claude Code / Codex CLI 等）
- **长期记忆、触发器、AI 创建智能体、音色定制**
- **企业级能力**：用户/组织管理（LDAP/OAuth）、细粒度资源权限、多租户、高可用、Agent 生命周期管理（用量统计/热门问答分析）

### ⚠️ 已知问题（社区反馈，2025.7-2026.2）
- 插件授权机制不可用
- 知识库文本/表格处理不稳定（长时间卡"处理中"）
- Bug 较多，尚未发布 GA 稳定版

---

## Coze Studio vs Dify 选型速查

| 场景 | 推荐 | 原因 |
|------|------|------|
| 快速搭 AI 客服/聊天 Bot | Coze SaaS / Coze Studio | 零代码 |
| 企业内部知识库问答 | **Dify** | RAG 最强，企业级权限 |
| 多系统数据同步自动化 | **n8n** | 400+ 连接器 |
| 团队 + Agent 协作推进项目 | **Coze SaaS** | 唯一支持多人多 Agent |
| 构建 AI 原生 SaaS 产品 | **Dify** | API 完善，可嵌入 |
| 数据完全自主 + Agent 开发 | **Coze Studio** 或 **Dify** | 都可 Docker 私有化 |
| 复杂大模型应用开发调试 | **Dify** | Prompt 调试看板 + LLMOps |

---

## 关于 "Agent Teams" 的结论

Coze Studio 开源版的 README 只写了「Build agent」（单个 Agent），全文**没有任何关于多人协作、Agent Teams、项目空间（Coze Space）的描述**。开源版连多用户体系都没有（注册就是裸账户），Agent Teams 这种重度依赖多用户身份和权限的功能**不可能在开源版中实现**。需要 Agent Teams → 只有 Coze SaaS。

---

## 信息来源

- Coze Studio GitHub: https://github.com/coze-dev/coze-studio
- Coze 官方文档: https://www.coze.cn/open/docs
- SegmentFault 企业场景分析: https://segmentfault.com/a/1190000047137271
- 博客园实测反馈: https://www.cnblogs.com/vipstone/p/19009069
