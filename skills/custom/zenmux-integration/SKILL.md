---
name: zenmux-integration
description: "Build tools and integrations on top of ZenMux AI Gateway APIs — quota monitoring, management endpoints, subscription queries, and custom dashboards."
version: 1.0.0
author: Hermes Agent
platforms: [macos, linux]
metadata:
  hermes:
    tags: [zenmux, ai-gateway, api-integration, monitoring, widgets]
---

# ZenMux Integration

Build tools and integrations on top of ZenMux AI Gateway — quota monitoring widgets, usage dashboards, billing alerts, and custom tooling.

## When to Use

- Building any tool that queries ZenMux account/quota/subscription data
- Creating macOS widgets, CLI tools, or dashboards for ZenMux monitoring
- Debugging ZenMux API calls or auth issues
- Any task involving `zenmux.ai` endpoints

## Key Concepts

### Two API Key Types (⚠️ Critical Distinction)

| Key Type | Prefix | Purpose | Where to Create |
|----------|--------|---------|-----------------|
| **Regular API Key** | `sk-ss-v1-` | Call AI models (Chat/Responses/Anthropic/Gemini) | Console > API Keys |
| **Management API Key** | Different prefix | Query subscription, balance, usage, flow rate | Console > Management |

**Pitfall:** Regular API Keys CANNOT call Management endpoints. If you get auth errors on `/api/v1/management/*`, the wrong key type is being used.

### Flows (Billing Unit)

A Flow is ZenMux's composite billing unit combining token consumption + per-request overhead. Different models consume different Flows per request. Current rate: ~1 Flow ≈ $0.03283.

### Quota Model

- **5-hour window**: Rolling window, resets every 5 hours. Rate-limited.
- **Weekly limit**: Rolling 7-day window. Hard cap on total Flows.
- Both have `max_flows`, `used_flows`, `remaining_flows`, `usage_percentage`.

## Management API Quick Reference

Full endpoint details in `references/management-api.md`.

| Endpoint | Method | Auth | Returns |
|----------|--------|------|---------|
| `/api/v1/management/subscription/detail` | GET | Management Key | Plan tier, quota_5_hour, quota_7_day |
| `/api/v1/management/payg/balance` | GET | Management Key | PAYG credits breakdown |
| `/api/v1/management/flow_rate` | GET | Management Key | Current Flow/USD rate |
| `/api/v1/management/generation?id=<id>` | GET | Management Key | Single call details |

Base URL: `https://zenmux.ai`

## User's Current Setup

- Plan: Ultra ($200/mo) — 800 Flows/5h, ~6182 Flows/week
- Regular API Key: stored in `~/.hermes/.env` as `ZENMUX_API_KEY`
- Management API Key: **NOT YET CREATED** — user needs to create in ZenMux Console > Management

## Ongoing Projects

- **macOS WidgetKit Widget**: Native desktop + right-panel widget for quota monitoring. Chose WidgetKit over Scriptable for native rendering parity with system widgets. Plan in progress.

## 与 zenmux-usage Skill 的兼容性（2026-05-20）

GitHub 上存在社区 Skill `ZenMux/skills` → `zenmux-usage`，与本 Skill 功能大量重叠但更全面：

| 维度 | zenmux-integration（本 Skill） | zenmux-usage（社区） |
|------|------------------------------|---------------------|
| 端点覆盖 | 4 个（基础管理 API） | 7 个（含 3 个统计端点） |
| Statistics Timeseries | ❌ | ✅ 按模型/天的 token/cost 趋势 |
| Statistics Leaderboard | ❌ | ✅ 按模型排名（tokens/cost） |
| Statistics Market Share | ❌ | ✅ 按供应商占比 |
| 格式化指南 | 简略 | 详尽（每种返回类型都有模板） |
| 参数选择逻辑 | 无 | 有（模糊请求的默认值决策树） |
| 环境变量名 | `ZENMUX_MANAGEMENT_API_KEY` | `ZENMUX_MANAGEMENT_KEY` |
| 项目上下文 | 有（WidgetKit 项目） | 无（纯查询工具） |

**建议：** 两个 Skill 不冲突。zenmux-usage 可作为查询子模块合并进来，或独立安装用于统计查询。Management Key 只需创建一次，两个 Skill 共用。

**前置条件：** Management API Key 尚未创建。需到 https://zenmux.ai/platform/management 创建，添加到 `~/.hermes/.env` 和 `~/.zshrc`。

## Pitfalls

1. **Management API Key missing**: Most interesting tools need this. First step in any ZenMux integration project is confirming the Management Key exists in `.env` as `ZENMUX_MANAGEMENT_API_KEY`.
2. **Billing data delay**: Usage/billing fields appear 3-5 minutes after request completion. Token counts are synchronous.
3. **Not for production**: Builder Plan (subscription) prohibits production use — PAYG only for production.
