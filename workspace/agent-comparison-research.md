# AI Agent 平台深度对比报告：Claude Code vs Codex CLI vs Hermes Agent

> 报告日期：2026年6月18日  
> 视角：通用 AI Agent 平台（非仅编程工具）  
> 语言：中文

---

## 目录

1. [核心身份与哲学定位](#1-核心身份与哲学定位)
2. [非编程通用能力](#2-非编程通用能力)
3. [技能/插件/扩展生态](#3-技能插件扩展生态)
4. [多端覆盖](#4-多端覆盖)
5. [调度与自动化](#5-调度与自动化)
6. [多智能体与编排](#6-多智能体与编排)
7. [模型灵活性与供应商锁定](#7-模型灵活性与供应商锁定)
8. [安全、隐私与沙箱](#8-安全隐私与沙箱)
9. [综合评分与总结](#9-综合评分与总结)

---

## 1. 核心身份与哲学定位

### Claude Code（Anthropic）

**定位**：从"AI 编程工具"出发，迅速向"通用 AI 工作代理"进化。

Claude Code 最初被定位为"agentic coding tool"，但其当前文档和功能范围已经远超编程范畴。官方描述为"reads your codebase, edits files, runs commands, and integrates with your development tools"，但实际能力包括 Slack 集成、定时任务调度、多端远程控制、浏览器交互、Chrome 扩展等。它拥有完整的多入口生态：终端 CLI、VS Code/JetBrains IDE 扩展、独立桌面应用、Web 界面、iOS App，以及 Agent SDK。

**核心理念**：以 Claude 模型为核心，构建一个"可以用在任何地方"的 AI 协作者。通过 CLAUDE.md 文件实现持久化指令记忆，通过 MCP（Model Context Protocol）实现外部工具连接标准化。

**代码与产品关系**：Claude Code 是闭源商业产品（npm 包 `@anthropic-ai/claude-code`），与 Anthropic 的模型 API 深度绑定。文档托管在 code.claude.com/docs。

---

### Codex CLI（OpenAI）

**定位**："Coding agent from OpenAI that runs locally on your computer"——本地运行的编码代理。

Codex CLI 是 OpenAI 在 2025 年推出的开源（Apache 2.0）编码代理工具。它的定位比 Claude Code 更聚焦于**本地开发工作流**：安装在终端中，与 Git 工作流深度集成，支持 VS Code/Cursor/Windsurf IDE 扩展，也有 Web 版本和桌面 App。

**核心理念**：让 OpenAI 的模型直接在开发者的本地环境中运行，拥有沙箱隔离的执行环境。通过 AGENTS.md 实现上下文配置，通过 MCP 和插件系统实现扩展。与 ChatGPT 订阅计划深度绑定（Plus、Pro、Business、Edu、Enterprise）。

**代码与产品关系**：完全开源（GitHub: openai/codex），Apache 2.0 许可。桌面 App (`codex app`) 和 Web 版本 (chatgpt.com/codex) 是其产品化入口。工具链使用 Bazel 构建，Rust 核心（codex-rs）。

---

### Hermes Agent（Nous Research）

**定位**："The self-improving AI agent"——自改进的通用 AI Agent，从一开始就定位为通用平台。

Hermes Agent 由 Nous Research 构建，是三者中**唯一从设计之初就以通用 Agent 为目标的平台**。它不是从"编程工具"衍生出来的，而是定位为"自我改进的 AI 代理"，拥有内置学习循环：从经验中创建技能、在使用中自我改进、跨会话持久化记忆、构建用户深层画像。

**核心理念**：完全开源（MIT）、模型无关（可使用任何 LLM 提供商）、平台无关（6 种终端后端）、通信渠道全覆盖（Telegram/Discord/Slack/WhatsApp/Signal/Email/CLI）。强调"不属于你的笔记本"，可在 $5 VPS 或 GPU 集群上运行，支持 serverless 休眠。

**代码与产品关系**：完全开源（GitHub: NousResearch/hermes-agent），MIT 许可。Python 构建，约 12,000 次提交。有独立桌面应用（Hermes Desktop）。

---

### 哲学对比总结

| 维度 | Claude Code | Codex CLI | Hermes Agent |
|------|------------|-----------|--------------|
| **出身** | 编程工具 → 通用平台 | 编程工具 | 从一开始就是通用 Agent |
| **开源** | 闭源商业产品 | 开源 (Apache 2.0) | 开源 (MIT) |
| **核心理念** | Claude 模型 + MCP 标准 | 本地执行 + 沙箱安全 | 自改进 + 模型无关 + 无处不在 |
| **主导方** | Anthropic（商业公司） | OpenAI（商业公司） | Nous Research（研究机构） |
| **目标用户** | 开发者 → 所有专业人士 | 开发者 | 所有人（开发者 + 普通用户） |

---

## 2. 非编程通用能力

### 2.1 写作与研究

| 能力 | Claude Code | Codex CLI | Hermes Agent |
|------|------------|-----------|--------------|
| **通用写作** | ✅ 通过 CLAUDE.md 和自然语言指令 | ⚠️ 可行但不侧重 | ✅ 通过技能系统和人格配置 |
| **深度研究** | ✅ 可结合 MCP 搜索工具 | ⚠️ 工具层面支持 | ✅ 40+ 内置工具含搜索 |
| **文档生成** | ✅ 强项 | ✅ 强项 | ✅ 强项 |
| **翻译** | ✅ CLI 一键触发 | ⚠️ 可行 | ✅ 技能生态支持 |
| **内容创作** | ✅ 自然语言驱动 | ⚠️ 非核心场景 | ✅ skills 系统 + 人格定制 |
| **跨会话记忆** | ✅ CLAUDE.md + auto memory | ✅ Chronicle（记忆系统） | ✅ FTS5 会话搜索 + 记忆 + Honcho 用户建模 |

**深度分析**：

- **Claude Code** 的写作能力依托 Claude 模型本身出色的语言能力。Claude 在长文写作、分析、翻译等方面天然强劲。加上 `claude -p "translate new strings into French"` 这种管道模式，可以轻松集成到工作流中。CLAUDE.md 提供项目级记忆，auto memory 提供个人偏好记忆。

- **Codex CLI** 虽然可以处理写作任务（因为它本质上是与 ChatGPT 模型交互），但其设计重心不在写作场景。它的 AGENTS.md 类似 CLAUDE.md，Chronicle（记忆系统）提供跨会话记忆，但工具和 UI 都是围绕代码仓库设计的。

- **Hermes Agent** 的写作/研究能力通过以下方式实现：(a) 40+ 内置工具包括 web 搜索 (Firecrawl)、浏览器自动化 (Browser Use)、图像生成 (FAL)；(b) 技能系统允许用户创建专门的写作/研究技能；(c) 人格系统（PERSONALITY.md/SOUL.md）允许深度定制写作风格；(d) FTS5 全文搜索 + LLM 摘要实现跨会话记忆回溯；(e) Honcho 辩证用户建模构建深度用户画像。

### 2.2 办公自动化

| 能力 | Claude Code | Codex CLI | Hermes Agent |
|------|------------|-----------|--------------|
| **邮件处理** | ⚠️ 需 MCP 服务器 | ⚠️ 须自行实现 | ✅ Email 网关原生支持 |
| **日历管理** | ⚠️ 需 MCP 服务器 | ❌ 不支持 | ✅ cron 定时 + 通知 |
| **文件管理** | ✅ 终端操作 | ✅ 终端操作 | ✅ 终端操作 + 6 种后端 |
| **翻译工作流** | ✅ CLI 管道 | ⚠️ 可行 | ✅ 技能封装 |
| **批量处理** | ✅ `git diff \| claude -p` | ✅ 类似模式 | ✅ batch_runner.py + cron |

**深度分析**：

- **Claude Code** 的"办公自动化"能力主要通过 MCP 生态系统间接实现——连接日历 MCP 服务器、邮件 MCP 服务器等。其 Routines（定时任务）和 `/loop` 命令提供了自动化基础。Slack 集成允许直接从团队聊天触发任务。但它本身不直接提供邮件/日历内置支持。

- **Codex CLI** 在纯办公自动化方面最弱，因为它的设计完全围绕开发工作流（git、代码仓库、IDE）。虽然有 Automations（自动化）模块和 Non-interactive Mode，但核心场景是 CI/CD、代码审查、GitHub Action 等开发自动化。

- **Hermes Agent** 在办公自动化方面最强：(a) 内置 cron 调度器，支持自然语言描述定时任务，可投递到任何平台（Telegram、Email 等）；(b) Email 网关原生支持收发邮件；(c) 6 种终端后端（local、Docker、SSH、Singularity、Modal、Daytona）使其可以在云端持续运行；(d) serverless 模式（Modal/Daytona）允许空闲时休眠降低成本。

### 2.3 创意工作

| 能力 | Claude Code | Codex CLI | Hermes Agent |
|------|------------|-----------|--------------|
| **图像生成** | ⚠️ 需 MCP | ⚠️ 需工具扩展 | ✅ 内置 FAL 集成 |
| **语音合成** | ❌ | ❌ | ✅ 内置 TTS |
| **语音输入** | ❌ | ❌ | ✅ 语音备忘录转录 |
| **创意写作** | ✅ 模型能力强 | ✅ 模型能力强 | ✅ 人格定制 + 技能 |
| **浏览器自动化** | ✅ Chrome 扩展 | ✅ Computer Use / Chrome 扩展 | ✅ Browser Use 集成 |

**深度分析**：

- **Claude Code** 的 Chrome 扩展允许直接与浏览器交互（调试 Web 应用、执行浏览器操作），这是创意和研究中非常实用的能力。但 Claude 模型本身不生成图像/语音，需要 MCP 扩展。

- **Codex CLI** 有 Computer Use 模式（类似 OpenAI Operator 的本地版本）和 Chrome 扩展，可以实现浏览器自动化。作为本地工具，可以调用任何本地程序。

- **Hermes Agent** 在创意工作方面有独特的优势：(a) Nous Portal 一站式提供图像生成 (FAL)、TTS (OpenAI)、Web 搜索 (Firecrawl)、云浏览器 (Browser Use)；(b) 语音备忘录转录功能；(c) 技能系统可以封装创意工作流；(d) 多平台网关（Telegram 等）允许随时随地触达。

---

## 3. 技能/插件/扩展生态

### 3.1 Claude Code

**Skills（技能）**：
- `/skills` 目录下可创建自定义技能
- 支持 CLI slash commands（自定义斜杠命令）
- 文档页面：`/en/skills`
- 技能本质是预定义的 prompt + 工具组合

**Plugins（插件）**：
- 插件系统：Discover and install prebuilt plugins，Create plugins
- 文档页面：`/en/plugins`
- "Prebuilt plugins"暗示存在插件市场/发现机制

**Hooks（钩子）**：
- 自动化钩子系统：`/en/hooks`
- 允许在特定事件触发时执行操作

**MCP 生态**：
- 完整支持 MCP (Model Context Protocol)
- MCP Quickstart、Reference 文档
- 可连接任何 MCP 兼容服务器
- Claude Code 是 MCP 生态的核心推动者

**Agent SDK**：
- 完整的 Agent SDK（TypeScript + Python）
- 允许构建自定义代理
- 支持子代理 (Subagents)、代理团队 (Agent teams)、动态工作流
- 支持 OpenTelemetry 可观测性
- 支持 Checkpointing（回滚文件更改）
- 支持 Streaming、Structured Output
- 独立的 SDK 文档体系：`/en/agent-sdk/overview`

### 3.2 Codex CLI

**Skills（技能）**：
- Skills 系统：文档中有专门的 `Skills` 页面
- "Using skills to accelerate OSS maintenance" 官方博客
- 可通过自然语言触发特定技能

**Plugins（插件）**：
- Plugins 系统：`Overview` 和 `Build plugins` 文档
- 插件是 Codex 功能扩展的核心机制
- 有 Sites 概念（可能是插件部署/分享平台）

**Hooks（钩子）**：
- Hooks 系统：`/en/hooks`
- 类似 Claude Code，允许在事件时触发操作

**MCP 生态**：
- 完整支持 MCP
- 文档中专门有 `MCP` 页面
- 兼容 OpenAI 的 MCP 连接器和 Connectors

**Subagents（子代理）**：
- 内建 Subagents 系统
- 文档中有专门的 Subagents 页面

**Codex SDK**：
- Codex SDK：程序化调用 Codex 的接口
- App Server：将 Codex 作为服务器运行
- MCP Server：将 Codex 作为 MCP 服务器暴露
- GitHub Action：CI/CD 集成

### 3.3 Hermes Agent

**Skills（技能系统）**：
- 自改进技能系统：Agent 在复杂任务后**自主创建技能**
- 技能在**使用中自我改进**
- 兼容 agentskills.io 开放标准
- Skills Hub：社区技能分享平台
- 技能通过 `/skill-name` 或 `/skills` 触发
- 已内置大量技能（见 `skills/` 目录）

**Plugins（插件）**：
- 插件系统：`plugins/` 目录
- 可安装第三方可选 MCP 服务器（`optional-mcps/`）
- 可选技能安装（`optional-skills/`）

**MCP 生态**：
- 完整 MCP 集成：可连接任何 MCP 服务器
- 自带 MCP 服务功能（`mcp_serve.py`）
- 社区 MCP 项目：computer-use-linux（Linux 桌面控制）
- 与 agentskills.io 标准兼容

**Cron 调度**：
- 内置 cron 调度器（`cron/` 目录）
- 自然语言描述定时任务
- 支持投递到任意平台

**多平台网关**：
- 统一网关进程
- 原生支持 Telegram、Discord、Slack、WhatsApp、Signal、Email
- 跨平台对话连续性
- 语音备忘录转录
- 微信桥接（社区项目 HermesClaw）

**上下文文件系统**：
- AGENTS.md、SOUL.md、MEMORY.md、USER.md
- CLAUDE.md 兼容
- 工作区指令文件

### 技能/插件生态对比总结

| 维度 | Claude Code | Codex CLI | Hermes Agent |
|------|------------|-----------|--------------|
| **技能系统** | ✅ 手动创建 | ✅ 手动创建 | ✅✅ 自改进 + 自主创建 |
| **插件系统** | ✅ 发现 + 安装 | ✅ 构建 + 安装 | ✅ 可选安装 |
| **MCP 支持** | ✅✅ 核心推动者 | ✅ 完整支持 | ✅ 完整支持 |
| **Agent SDK** | ✅✅ TS + Python | ✅ SDK + MCP Server | ⚠️ 通过 RPC/subagent |
| **钩子系统** | ✅ | ✅ | ⚠️ cron 替代 |
| **社区生态** | ⚠️ 较新 | ⚠️ 较新 | ✅ Skills Hub |
| **自改进能力** | ❌ | ❌ | ✅✅ 核心特色 |
| **跨平台网关** | ✅ Channels | ❌ | ✅✅ 原生多平台 |
| **开放标准** | MCP | MCP | MCP + agentskills.io |

---

## 4. 多端覆盖

### 4.1 Claude Code — 业界最全面

| 终端 | 支持状态 |
|------|---------|
| **CLI（终端）** | ✅ 核心入口 (`claude`) |
| **VS Code** | ✅ 扩展 |
| **JetBrains IDEs** | ✅ 扩展 |
| **桌面 App** | ✅ 独立桌面应用 |
| **Web** | ✅ code.claude.com / claude.ai |
| **iOS** | ✅ Claude iOS App |
| **Android** | ❌ |
| **Slack** | ✅ `@Claude` 集成 |
| **Chrome** | ✅ Chrome 扩展 |
| **CI/CD** | ✅ GitHub Actions + GitLab CI/CD |
| **API/SDK** | ✅ Agent SDK (TS + Python) |

**独特能力**：
- **Remote Control**：从手机或浏览器继续本地会话
- **Teleport**：将 Web/iOS 上的任务"传送"到终端 (`claude --teleport`)
- **Dispatch**：从手机发送任务，在桌面 App 中打开
- **Channels**：从 Telegram、Discord、iMessage 或自定义 Webhook 推送事件到会话
- 所有终端共享同一引擎，CLAUDE.md、设置、MCP 服务器跨终端通用

### 4.2 Codex CLI — 开发者多端

| 终端 | 支持状态 |
|------|---------|
| **CLI（终端）** | ✅ 核心入口 (`codex`) |
| **VS Code** | ✅ 扩展 |
| **Cursor** | ✅ 扩展 |
| **Windsurf** | ✅ 扩展 |
| **桌面 App** | ✅ `codex app` |
| **Web** | ✅ chatgpt.com/codex |
| **iOS/Android** | ⚠️ 通过 ChatGPT App 间接访问 |
| **Slack** | ✅ Slack 集成 |
| **GitHub** | ✅ GitHub 集成 + Action |
| **CI/CD** | ✅ GitHub Action |
| **API/SDK** | ✅ Codex SDK + MCP Server + App Server |

**独特能力**：
- 三种形式共存：CLI、桌面 App、Web——分别针对不同场景
- IDE 扩展覆盖 VS Code、Cursor、Windsurf
- Linear 集成（项目管理工具）
- Non-interactive Mode：适合 CI/CD 管道

### 4.3 Hermes Agent — 真正"无处不在"

| 终端 | 支持状态 |
|------|---------|
| **CLI（终端）** | ✅ 核心入口 (`hermes`)，全功能 TUI |
| **桌面 App** | ✅ Hermes Desktop |
| **Web** | ✅ 内建 Web UI |
| **Telegram** | ✅ 原生 Bot |
| **Discord** | ✅ 原生 Bot |
| **Slack** | ✅ 原生 Bot |
| **WhatsApp** | ✅ 原生 Bot |
| **Signal** | ✅ 原生 Bot |
| **Email** | ✅ 邮件网关 |
| **微信** | ✅ 社区桥接 (HermesClaw) |
| **Home Assistant** | ✅ 智能家居集成 |
| **终端后端** | ✅ 6 种：local/Docker/SSH/Singularity/Modal/Daytona |

**独特能力**：
- **统一网关**：一个进程管理所有消息平台
- **跨平台对话连续性**：在 Telegram 开始的对话可在 CLI 继续
- **6 种终端后端**：不仅能在本地运行，还能在 Docker、远程 SSH、高性能计算（Singularity）、Serverless（Modal/Daytona）环境运行
- **Serverless 持久化**：Modal/Daytona 后端支持空闲休眠、按需唤醒、近乎零空闲成本
- **$5 VPS 可运行**：极低资源需求，可在最便宜的云服务器上运行
- **语音交互**：语音备忘录转录

### 多端覆盖对比总结

| 维度 | Claude Code | Codex CLI | Hermes Agent |
|------|------------|-----------|--------------|
| **CLI** | ✅ | ✅ | ✅ (全功能 TUI) |
| **IDE 扩展** | ✅✅ VS Code + JetBrains | ✅✅ VS Code + Cursor + Windsurf | ❌ |
| **桌面 App** | ✅ | ✅ | ✅ |
| **Web** | ✅ | ✅ | ✅ |
| **消息平台** | ✅ Slack + Channels | ✅ Slack | ✅✅ 7+ 平台原生 |
| **移动端** | ✅ iOS | ⚠️ 间接 | ✅ 通过消息平台 |
| **浏览器** | ✅ Chrome 扩展 | ✅ Chrome 扩展 | ⚠️ Browser Use |
| **执行环境** | 本地 | 本地 + 沙箱 | ✅✅ 6 种后端 |
| **Serverless** | ❌ | ❌ | ✅ Modal + Daytona |
| **跨终端连续性** | ✅✅ Remote Control + Teleport | ❌ | ✅ 跨平台对话 |

---

## 5. 调度与自动化

### 5.1 Claude Code

**三层调度体系**：

| 层级 | 名称 | 运行位置 | 特点 |
|------|------|---------|------|
| L1 | **Routines** | Anthropic 云端 | 电脑关机也运行；可通过 API/GitHub 事件触发；从 Web/桌面 App/CLI 创建 |
| L2 | **Desktop scheduled tasks** | 本地机器 | 直接访问本地文件和工具 |
| L3 | **`/loop`** | CLI 会话内 | 在会话内轮询重复 |

**Hooks 系统**：事件驱动的自动化钩子，可在特定操作前后触发。

**Channels**：从外部事件源（Telegram、Discord、iMessage、Webhook）推送消息到运行中的会话。

**GitHub Actions / GitLab CI/CD**：可在 CI/CD 管道中自动运行 Claude Code。

### 5.2 Codex CLI

**Automations（自动化）**：
- 文档中有专门的 Automations 页面
- 支持定时或事件触发的自动化

**Non-interactive Mode**：适合 CI/CD 管道中的无人值守执行。

**GitHub Action**：CI/CD 集成的官方 Action。

**Codex SDK / App Server**：程序化调用实现自动化流水线。

**Workflows**：工作流概念（文档中有 Workflows 页面），可能支持多步骤自动化编排。

### 5.3 Hermes Agent

**内置 Cron 调度器**：
- 自然语言描述定时任务（如"每天早上 8 点发送今日天气"）
- 支持投递到任意平台（Telegram、Email 等）
- `cron/` 目录管理所有定时任务
- Agent 完全在后台运行，不需要用户交互

**持续运行能力**：
- 6 种终端后端意味着可以在云服务器上 24/7 运行
- Serverless 模式（Modal/Daytona）可按需唤醒执行任务后休眠

**网关自动响应**：
- 消息平台 Bot 可被事件触发（如收到邮件 → agent 自动处理）

**批量处理**：`batch_runner.py` 支持批量轨迹生成和处理。

### 调度与自动化对比总结

| 维度 | Claude Code | Codex CLI | Hermes Agent |
|------|------------|-----------|--------------|
| **云端定时** | ✅ Routines | ❌ | ✅ Serverless 模式 |
| **本地定时** | ✅ Desktop scheduled | ✅ Automations | ✅ Cron |
| **自然语言调度** | ✅ | ⚠️ | ✅✅ |
| **事件触发** | ✅ Channels + Hooks | ✅ Hooks | ✅ 网关事件 |
| **CI/CD** | ✅✅ | ✅✅ | ⚠️ 可手动集成 |
| **持续运行** | ⚠️ 需 Routines | ❌ | ✅✅ 原生支持 |
| **空闲成本** | Routines 收费 | N/A | ✅ 近乎零 |

---

## 6. 多智能体与编排

### 6.1 Claude Code

**Agent SDK**：
- TypeScript 和 Python SDK
- 构建自定义 Agent
- 子代理（Subagents）系统
- Agent 团队（Agent teams）：多个 Agent 协作
- 动态工作流（Dynamic workflows）
- 工作树隔离（Worktrees）：为 Agent 隔离文件系统

**Agent 视图（Agent view）**：可视化管理多个 Agent。

**OpenTelemetry**：可观测性追踪。

**Checkpointing**：Agent 操作回滚。

### 6.2 Codex CLI

**Subagents（子代理）**：
- 内建子代理系统
- 文档中有专门页面

**Sandboxing（沙箱）**：
- 代码执行隔离
- 安全执行环境

**Codex SDK**：程序化 Agent 调用。

**MCP Server 模式**：将 Codex 作为 MCP 服务器暴露，供其他 Agent 调用。

### 6.3 Hermes Agent

**子代理生成（Subagent Spawning）**：
- 在对话中生成隔离的子代理处理并行工作流
- 子代理拥有独立的上下文窗口

**RPC 工具调用**：
- 可编写 Python 脚本通过 RPC 调用 Agent 工具
- 将多步骤流水线压缩为零上下文成本的单次调用

**批量轨迹生成**：
- `batch_runner.py` + `trajectory_compressor.py`
- 用于训练下一代工具调用模型的研究级能力

**ACP 适配器（Agent Communication Protocol）**：
- `acp_adapter/` 和 `acp_registry/` 目录
- Agent 间通信协议
- 支持多 Agent 协作

### 多智能体对比总结

| 维度 | Claude Code | Codex CLI | Hermes Agent |
|------|------------|-----------|--------------|
| **子代理** | ✅✅ Agent SDK | ✅ Subagents | ✅ 对话中生成 |
| **代理团队** | ✅ Agent teams | ❌ | ⚠️ 通过 ACP |
| **SDK/API** | ✅✅ TS + Python | ✅ SDK | ⚠️ RPC + Python |
| **工作隔离** | ✅ Worktrees | ✅ Sandbox | ✅ 子代理隔离 |
| **可观测性** | ✅ OpenTelemetry | ⚠️ | ❌ |
| **回滚** | ✅ Checkpointing | ⚠️ | ⚠️ `/undo` |
| **训练/研究** | ❌ | ❌ | ✅✅ 轨迹生成 |

---

## 7. 模型灵活性与供应商锁定

### 7.1 Claude Code

**锁定程度：🔒🔒🔒 高度锁定**

- **仅支持 Anthropic Claude 模型**：Claude 3.5 Sonnet、Claude 3 Opus 等
- 虽然在技术层面通过 MCP 可以连接外部 AI 服务作为"工具"，但核心推理引擎不可替换
- 通过 Anthropic API 使用，需要 Anthropic 账户和 API Key
- 定价绑定 Anthropic 的 token 计费模型
- **优势**：深度集成意味着优化更好、体验更流畅

### 7.2 Codex CLI

**锁定程度：🔒🔒 中高度锁定**

- **主要绑定 OpenAI 模型**：GPT-4o、GPT-4.1、GPT-5 等
- 深度集成 ChatGPT 订阅体系（Plus/Pro/Business/Edu/Enterprise）
- 也可使用 API Key 方式，但仍限于 OpenAI API
- 开源代码但模型推理依赖 OpenAI
- 通过 MCP 可扩展工具但核心推理不可换
- Amazon Bedrock 部署选项（文档中有提到），允许在 AWS 上运行
- **优势**：与 ChatGPT 生态无缝集成

### 7.3 Hermes Agent

**锁定程度：🔓 零锁定**

- **可使用任何 LLM 提供商**：
  - Nous Portal（一站式 300+ 模型）
  - OpenRouter（200+ 模型）
  - NovitaAI
  - NVIDIA NIM (Nemotron)
  - Xiaomi MiMo
  - z.ai/GLM
  - Kimi/Moonshot
  - MiniMax
  - Hugging Face
  - OpenAI
  - 自定义端点
- **切换命令**：`hermes model` — 一条命令切换，无需代码更改
- **Nous Portal**：一个订阅覆盖模型 + Web 搜索 + 图像生成 + TTS + 云浏览器
- **Provider 系统**：`providers/` 目录管理所有提供商的适配器
- 用户可自带任意模型的 API Key

### 模型灵活性对比总结

| 维度 | Claude Code | Codex CLI | Hermes Agent |
|------|------------|-----------|--------------|
| **模型选择** | 仅 Claude 系列 | 仅 OpenAI 系列 | ✅✅ 任意模型 |
| **提供商数量** | 1 | 1（+ Bedrock） | 12+ |
| **切换成本** | 无法切换 | 无法切换 | 一条命令 |
| **本地模型** | ❌ | ❌ | ✅ Hugging Face 等 |
| **定价灵活性** | 绑定 Anthropic | 绑定 OpenAI | ✅ 自由选择最便宜的 |
| **Portal 一站式** | ❌ | ❌ | ✅ Nous Portal |

---

## 8. 安全、隐私与沙箱

### 8.1 Claude Code

**权限系统**：
- Permission modes：控制 Agent 的操作权限
- 命令审批：可配置哪些命令需用户确认

**数据隐私**：
- 闭源商业产品，代码不透明
- 数据通过 Anthropic API 传输
- CLAUDE.md 等配置文件存储在本地 `.claude/` 目录

**沙箱**：
- Worktrees：为 Agent 任务提供文件系统隔离
- 无容器级沙箱

**企业功能**：
- 管理员配置
- 组织级治理
- 合规支持

### 8.2 Codex CLI

**安全设计**：
- **Sandboxing**：核心特色之一，提供代码执行沙箱
- **Cyber Safety**：专门的安全页面
- **Codex Security**：安全插件和安全云端
- 权限系统
- 审批控制

**透明性**：
- 完全开源（Apache 2.0），代码可审计
- 本地执行为主，数据不出本地（使用 API 时除外）

**企业功能**：
- Enterprise 管理设置
- 治理策略
- 管理配置
- Agent 审批和安全

**沙箱架构**：
- 编译时使用 Bazel
- Rust 核心（codex-rs）提供安全保障
- 隔离的执行环境

### 8.3 Hermes Agent

**安全设计**：
- **命令审批**：可配置命令执行需用户确认
- **DM 配对**：消息平台一对一绑定防止未授权访问
- **容器隔离**：Docker 后端提供容器级隔离
- **SSH 后端**：可在远程隔离环境执行
- **完全本地运行**：可选择不依赖任何云服务
- **开源透明**：MIT 许可，完全可审计

**隐私**：
- 用户数据完全在用户控制之下
- 可完全离线运行（本地模型 + 本地工具）
- 无遥测（开源项目）
- 所有对话/记忆存储在本地 `~/.hermes/`

**执行环境**：
- 6 种终端后端提供不同级别的隔离：
  - local：直接本地执行
  - Docker：容器隔离
  - SSH：远程隔离
  - Singularity：HPC 级容器
  - Modal：Serverless 隔离
  - Daytona：Serverless 隔离

### 安全与隐私对比总结

| 维度 | Claude Code | Codex CLI | Hermes Agent |
|------|------------|-----------|--------------|
| **代码透明** | ❌ 闭源 | ✅ Apache 2.0 | ✅ MIT |
| **沙箱执行** | ⚠️ Worktrees | ✅✅ 核心特色 | ✅ Docker/Singularity |
| **本地优先** | ⚠️ 依赖 API | ✅ | ✅✅ 可完全离线 |
| **命令审批** | ✅ | ✅ | ✅ |
| **企业治理** | ✅ | ✅✅ | ❌（研究项目） |
| **数据隐私** | ⚠️ 数据经过 Anthropic | ⚠️ 数据经过 OpenAI | ✅✅ 完全用户控制 |
| **容器隔离** | ❌ | ⚠️ | ✅ Docker/SSH |
| **Serverless 隔离** | ❌ | ❌ | ✅ Modal/Daytona |

---

## 9. 综合评分与总结

### 能力雷达图（满分 5 分）

| 维度 | Claude Code | Codex CLI | Hermes Agent |
|------|:-----------:|:---------:|:------------:|
| **编程与开发** | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ | ⭐⭐⭐ |
| **通用写作/研究** | ⭐⭐⭐⭐ | ⭐⭐⭐ | ⭐⭐⭐⭐ |
| **办公自动化** | ⭐⭐⭐ | ⭐⭐ | ⭐⭐⭐⭐⭐ |
| **创意工作** | ⭐⭐⭐ | ⭐⭐⭐ | ⭐⭐⭐⭐ |
| **技能/插件生态** | ⭐⭐⭐⭐ | ⭐⭐⭐ | ⭐⭐⭐⭐⭐ |
| **多端覆盖** | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ |
| **调度/自动化** | ⭐⭐⭐⭐ | ⭐⭐⭐ | ⭐⭐⭐⭐⭐ |
| **多智能体** | ⭐⭐⭐⭐⭐ | ⭐⭐⭐ | ⭐⭐⭐ |
| **模型灵活性** | ⭐ | ⭐⭐ | ⭐⭐⭐⭐⭐ |
| **安全/隐私** | ⭐⭐⭐ | ⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ |
| **开源/社区** | ⭐ | ⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ |

### 综合推荐

| 用户画像 | 最佳选择 | 原因 |
|---------|---------|------|
| **专业软件开发者** | Claude Code 或 Codex CLI | IDE 深度集成、Git 工作流优化、代码审查自动化 |
| **已深度使用 Anthropic/OpenAI 生态** | 对应的 Claude Code/Codex | 模型锁定反成优势——集成更深度 |
| **需要通用 AI Agent 的普通用户** | **Hermes Agent** | 唯一的真正通用平台；多平台消息接入；零锁定 |
| **重视隐私和自主权** | **Hermes Agent** | 完全开源、可离线运行、数据自控 |
| **想自己构建 Agent 系统** | Claude Code（Agent SDK） | 最好的 SDK/API 支持 |
| **CI/CD 自动化** | Claude Code 或 Codex CLI | 原生 GitHub Actions/GitLab CI 支持 |
| **最大化性价比** | **Hermes Agent** | 可选最便宜模型 + serverless 空闲零成本 |
| **需要在手机/聊天中与 AI 交互** | **Hermes Agent** | 7+ 消息平台原生 Bot 支持 |
| **研究/训练用途** | **Hermes Agent** | 唯一有轨迹生成/压缩能力的平台 |

### 最终结论

这三个平台代表了 AI Agent 领域的三个不同方向：

1. **Claude Code** 是"**商业产品的极致**"——Anthropic 倾注了大量资源打造了最完整的全栈体验。从终端到 IDE 到桌面到 Web 到手机，从技能到插件到钩子到 Agent SDK，从 Slack 到 Chrome 到 GitHub，Claude Code 的覆盖面最广、集成最深。但它将用户锁定在 Anthropic 生态中。

2. **Codex CLI** 是"**开源开发者的瑞士军刀**"——完全开源、本地执行、沙箱安全，深度融入 VS Code/Cursor/Windsurf 生态和 ChatGPT 订阅体系。它在代码开发场景下非常强大，但作为通用 Agent 平台的意愿和能力都有限。

3. **Hermes Agent** 是"**真正为通用场景而生的自改进 Agent**"——它是唯一从一开始就以"通用 AI 代理"为目标设计的平台，而非从编程工具衍生。模型无关的架构、自改进技能系统、前所未有的多平台覆盖、6 种执行后端、serverless 部署选项，使其成为最灵活、最自主、性价比最高的选择。但它在 IDE 深度集成和 Agent SDK 方面不如前两者。

**一句话总结**：

> 如果你是开发者且已绑定 Anthropic/OpenAI 生态，选对应的 Claude Code/Codex CLI。  
> 如果你需要一个**真正的通用 AI Agent 平台**——能写作、能研究、能办公、能在任何设备上触达、不锁定任何模型、自改进、且完全掌控数据——**Hermes Agent 是唯一答案**。

---

*本报告基于 2026 年 6 月 18 日的官方文档、GitHub 仓库和公开信息编写。*
