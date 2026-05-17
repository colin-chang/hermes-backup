---
name: hermes-weekly-cleanup
description: Hermes Agent 每周清理临时文件的脚本与定时任务，安全删除缓存、旧日志、过期会话等
version: 1.0.0
created: 2026-05-17
---

# Hermes 每周清理临时文件

## 定时任务信息

- **Job ID**: `3a0686fb07c9`
- **脚本路径**: `~/.hermes/scripts/hermes-weekly-cleanup.sh`
- **调度**: `0 3 * * 0`（每周日凌晨 3:00 CST）
- **模式**: `no_agent=true`（纯脚本执行，无 LLM 开销）
- **推送目标**: `deliver: "discord"` → Discord Home 频道

> **设计模式参考：** 此任务是 `no_agent=true` 模式的参考实现。
> 通用决策框架、`report()` 函数模板、迁移清单 → `hermes-agent` skill → `references/cron-no-agent-pattern.md`

- **清理日志**: `~/.hermes/logs/cleanup.log`

## 清理范围（9 大类）

> **用户偏好：所有类别统一保留 3 天。** 调整时编辑脚本顶部 `DAYS_*` 变量。

| # | 类别 | 保留策略 | 说明 |
|---|------|----------|------|
| 1 | Chrome 调试缓存 | 全部清理 | `~/.chrome-debug-profile/Default/{CacheStorage,IndexedDB,Cache,...}`，最大空间消费者 |
| 2 | Python 字节码 | 全部清理 | `__pycache__/`, `.pytest_cache/`，自动重建 |
| 3 | 日志轮转 | 保留 3 天 | `~/.hermes/logs/*.log`, `webui.log`，超大日志自动截断 |
| 4 | 截图/媒体缓存 | 保留 3 天 | `cache/screenshots/`, `audio_cache/`, `image_cache/`, `images/`, 模型缓存 JSON |
| 5 | 旧会话/转储 | 保留 3 天 | `sessions/request_dump_*.json`, `sessions/session_*.json` |
| 6 | 更新备份/快照 | 保留 3 天 | `backups/*.zip`, `state-snapshots/` |
| 7 | 定时任务输出 | 保留 3 天 | `cron/output/` |
| 8 | 失效锁/PID 文件 | 进程不运行时清理 | `gateway.lock`, `webui.pid`, `auth.lock` |
| 9 | SQLite VACUUM | Hermes 未运行时执行 | `state.db` 空间优化，不删除数据 |

## 绝对不触碰

`config.yaml`, `.env`, `auth.json`, `SOUL.md`, `state.db*`, `kanban.db`, `memories/`, `skills/`, `bin/`, `scripts/`, `.claude/`, `workspace/`, 源码目录

## 安全机制

1. **启动前核心文件检查** — 核心文件缺失则中止
2. **Chrome 缓存** — 仅在调试进程未运行时删除
3. **锁/PID 文件** — 仅在对应进程未运行时清理
4. **SQLite VACUUM** — 仅在 Hermes 未运行时执行
5. **超大日志截断** — >50MB 时保留最近 1000 行而非删除
6. **自有日志轮转** — cleanup.log 超 1MB 时截断

## 手动执行

```bash
# 直接运行脚本
~/.hermes/scripts/hermes-weekly-cleanup.sh

# 通过 cronjob 触发
# hermes cron run 3a0686fb07c9
```

## 调整保留天数

编辑 `~/.hermes/scripts/hermes-weekly-cleanup.sh` 顶部的配置变量。
当前用户偏好：**统一 3 天**（`DAYS_*` 全部为 3）。

## 分析报告

完整分析报告保存在：`references/cleanup-analysis.md`
