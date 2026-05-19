# Hermes Agent 临时文件与缓存深度分析报告

**系统**: macOS (26.5)  
**日期**: 2026-05-17  
**~/.hermes/ 总大小**: 1.4 GB  
**~/.chrome-debug-profile/ 总大小**: 9.2 GB  
**合计占用**: ~10.6 GB

---

## 一、目录用途与内容详解

### 1. `~/.hermes/` 顶层文件

| 路径 | 大小 | 用途 | 安全性 |
|------|------|------|--------|
| `config.yaml` | 4.7K | 核心配置文件 | ❌ **不可删** |
| `.env` | 581B | API 密钥等环境变量 | ❌ **不可删** |
| `auth.json` | 2.3K | 认证凭据 | ❌ **不可删** |
| `SOUL.md` | 537B | Agent 人格定义 | ❌ **不可删** |
| `state.db` + `-shm` + `-wal` | 19M + 32K + 4M | SQLite 主状态数据库（会话、消息等） | ❌ **不可删** |
| `kanban.db` | 100K | 看板任务数据库 | ❌ **不可删** |
| `models_dev_cache.json` | 2.0M | 模型目录缓存 | ⚠️ **可删** — 下次启动时重建 |
| `ollama_cloud_models_cache.json` | 671B | Ollama 模型缓存 | ⚠️ **可删** — 下次启动时重建 |
| `webui.log` | 1.1M | WebUI 运行日志 | ✅ **可删** — 运行时重建 |
| `channel_directory.json` | 1.3K | 频道目录 | ⚠️ **可删** — 可重建 |
| `discord_threads.json` | 23B | Discord 线程映射 | ⚠️ **可删** — 可重建 |
| `gateway.lock` / `gateway.pid` | 157B each | 网关进程锁/PID文件 | ⚠️ **可删**（进程停后） |
| `webui.pid` | 5B | WebUI 进程PID | ⚠️ **可删**（进程停后） |
| `auth.lock` | 0B | 认证锁文件 | ⚠️ **可删**（无活跃操作时） |
| `processes.json` | 2B | 子进程追踪 | ⚠️ **可删**（进程停后） |
| `gateway_state.json` | 417B | 网关状态 | ⚠️ **可删** — 可重建 |
| `.update_check` | 52B | 更新检查时间戳 | ✅ **可删** |
| `.hermes_history` | 2.6K | CLI 历史记录 | ✅ **可删** |
| `webui.ctl.env` | 224B | WebUI 控制环境变量 | ❌ **不可删** |

### 2. `~/.hermes/hermes-agent/` — 1.2 GB（应用源码）

| 子目录 | 大小 | 用途 | 安全性 |
|--------|------|------|--------|
| `venv/` | 277M | Python 虚拟环境 | ⚠️ **可删重建** — `pip install` 重建，耗时约2-5分钟 |
| `web/` | 250M | Web 前端资源 | ⚠️ **可删重建** — `npm install` 重建 |
| `ui-tui/` | 208M | TUI 界面 (Ink/React) | ⚠️ **可删重建** — `npm install` 重建 |
| `node_modules/` | 149M | Node.js 依赖 | ⚠️ **可删重建** — `npm install` 重建 |
| `__pycache__/` | 1.6M | Python 字节码缓存 | ✅ **可删** — 自动重建 |
| `.pytest_cache/` | 16K | 测试缓存 | ✅ **可删** |
| 其余源码 | ~100M | 核心代码 | ❌ **不可删** |

### 3. `~/.chrome-debug-profile/` — **9.2 GB** ⚠️ 最大消费者

| 子目录 | 大小 | 用途 | 安全性 |
|--------|------|------|--------|
| `Default/Service Worker/CacheStorage/` | **3.2 GB** | 浏览器 Service Worker 缓存 | ✅ **可删** |
| `Default/IndexedDB/` | **1.1 GB** | 浏览器 IndexedDB 存储 | ✅ **可删** |
| `Default/Local Storage/` | 31M | 本地存储 | ✅ **可删** |
| `Default/GPUCache/` | 5.6M | GPU 着色器缓存 | ✅ **可删** |
| `Default/Cache/` | 1.7M | HTTP 缓存 | ✅ **可删** |
| `Default/Code Cache/` | 68K | 代码缓存 | ✅ **可删** |
| `Default/Session Storage/` | 252K | 会话存储 | ✅ **可删** |
| `Default/File System/` | 860K | 文件系统存储 | ✅ **可删** |
| `BrowserMetrics-spare.pma` | 4M | 浏览器指标 | ✅ **可删** |
| `ShaderCache/` / `GrShaderCache/` | ~几M | 着色器缓存 | ✅ **可删** |
| `Safe Browsing/` | ~几M | 安全浏览数据 | ✅ **可删** |
| **整个目录** | **9.2 GB** | **Hermes 浏览器工具的 Chrome 调试配置文件** | ✅ **整个目录可安全删除** — 下次启动浏览器工具时自动重建 |

### 4. `~/.hermes/lsp/` — 99 MB

| 子目录 | 大小 | 用途 | 安全性 |
|--------|------|------|--------|
| `node_modules/` | 99M | LSP 服务器 Node.js 依赖 | ⚠️ **可删重建** — `npm install` 重建 |
| `bin/` | 0B | LSP 二进制 | — |

### 5. `~/.hermes/sessions/` — 17 MB（59 个文件）

| 类型 | 示例 | 用途 | 安全性 |
|------|------|------|--------|
| `session_*.json` | 各 15K-534K | CLI 会话历史记录 | ⚠️ **可删** — 删除旧会话，保留近期 |
| `request_dump_*.json` | ~97K | 请求调试转储 | ✅ **可删** — 纯调试用 |

### 6. `~/.hermes/webui/` — 26 MB

| 子目录 | 大小 | 用途 | 安全性 |
|--------|------|------|--------|
| `sessions/` | 26M | WebUI 会话数据 + 日志 | ⚠️ **可删** — 保留活跃会话 |
| `sessions/_run_journal/` | 17M | 运行日志 | ✅ **可删** |
| `sessions/_turn_journal/` | 120K | 轮次日志 | ✅ **可删** |
| `attachments/` | 52K | 上传的截图/附件 | ⚠️ **视情况** — 可能包含用户上传的重要文件 |

### 7. `~/.hermes/cache/` — 1.2 MB

| 子目录 | 大小 | 用途 | 安全性 |
|--------|------|------|--------|
| `screenshots/` | ~1.2M | 浏览器工具截图（4个PNG文件） | ✅ **可删** — 临时性 |
| `documents/` | 0B | 文档缓存（空） | ✅ **可删** |
| `model_catalog.json` | 5.1K | 模型目录缓存 | ⚠️ **可删** — 可重建 |

### 8. `~/.hermes/logs/` — 1.1 MB

| 文件 | 大小 | 用途 | 安全性 |
|------|------|------|--------|
| `agent.log` | 965K | Agent 主日志 | ✅ **可删** — 持续追加写入 |
| `errors.log` | 60K | 错误日志 | ✅ **可删** |
| `gateway.log` | 47K | 网关日志 | ✅ **可删** |
| `tui_gateway_crash.log` | 31K | TUI 网关崩溃日志 | ✅ **可删** |
| `gateway.error.log` | 20K | 网关错误日志 | ✅ **可删** |
| `gateway-exit-diag.log` | 9K | 网关退出诊断 | ✅ **可删** |
| `update.log` | 1.4K | 更新日志 | ✅ **可删** |
| `gateway-shutdown-diag.log` | 0B | 关机诊断 | ✅ **可删** |
| `curator/` | 0B | 日志策展目录（空） | ✅ **可删** |

**轮转策略**: **无自动轮转！** 日志文件持续追加，`agent.log` 是主要增长点。

### 9. `~/.hermes/backups/` — 14 MB

| 文件 | 大小 | 用途 | 安全性 |
|------|------|------|--------|
| `pre-update-*.zip` | 14M | 更新前备份 | ⚠️ **可删** — 仅在确认更新成功后删除 |

### 10. `~/.hermes/state-snapshots/` — 7.6 MB

| 子目录 | 大小 | 用途 | 安全性 |
|--------|------|------|--------|
| `20260516-100922-pre-update/` | 7.6M | 更新前状态快照 | ⚠️ **可删** — 确认稳定后可删除 |

### 11. 其他小目录

| 路径 | 大小 | 用途 | 安全性 |
|------|------|------|--------|
| `audio_cache/` | 0B | 音频缓存 | ✅ **可删** |
| `image_cache/` | 0B | 图片缓存 | ✅ **可删** |
| `hooks/` | 0B | 网关钩子 | ✅ **可删** |
| `pairing/` | 0B | 设备配对 | ✅ **可删** |
| `plugins/` | 0B | 用户插件 | ✅ **可删** |
| `sandboxes/` | 0B | 沙箱数据 | ✅ **可删** |
| `images/` | 24K | 剪贴板图片 | ✅ **可删** |
| `memories/` | 8K | 记忆文件 | ❌ **不可删** — 用户核心数据 |
| `scripts/` | 56K | 用户脚本 | ❌ **不可删** |
| `cron/output/` | 54K | 定时任务输出 | ⚠️ **可删旧** |
| `gateway/` | 4K | 网关数据 | ⚠️ **可删** |
| `.claude/` | 278B | Claude 集成设置 | ❌ **不可删** |
| `bin/` | 9.9M | 二进制工具 | ❌ **不可删** |
| `skills/` | 7.2M | 技能包 | ❌ **不可删** |
| `workspace/` | 20K | 工作区脚本 | ❌ **不可删** |

---

## 二、按增长风险排序的 TOP 清理目标

| 排名 | 路径 | 当前大小 | 增长速度 | 风险等级 |
|------|------|----------|----------|----------|
| 1 | `~/.chrome-debug-profile/` | **9.2 GB** | 高（每次浏览器操作） | 🔴 极高 |
| 2 | `~/.hermes/state.db` | 19 MB + WAL | 中（每次对话） | 🟡 中 |
| 3 | `~/.hermes/sessions/` | 17 MB | 中（每次对话） | 🟡 中 |
| 4 | `~/.hermes/webui/sessions/` | 26 MB | 中（每次 WebUI 使用） | 🟡 中 |
| 5 | `~/.hermes/logs/agent.log` | 965 KB → ∞ | 中（持续追加，**无轮转**） | 🟡 中 |
| 6 | `~/.hermes/cache/screenshots/` | 1.2 MB | 低-中 | 🟢 低 |
| 7 | `~/.hermes/backups/` | 14 MB | 低（更新时） | 🟢 低 |

---

## 三、特别注意的陷阱

1. **`state.db` 是 SQLite 数据库** — 绝不能在运行时删除！直接删除会导致数据丢失和进程崩溃。
2. **`~/.chrome-debug-profile/` 删除时机** — 必须在 Chrome 调试进程未运行时删除。
3. **`venv/` 和 `node_modules/` 删除后需重建** — 不是"下次启动自动修复"。
4. **锁文件不能在进程运行时删除** — 可能导致多实例问题。
5. **`memories/` 目录虽小但极其重要** — 删除后 Agent 会"失忆"。
6. **日志无自动轮转** — `agent.log` 是追加模式，长期运行后可能变得很大。
7. **Chrome Service Worker Cache 是最大元凶** — `CacheStorage/` 一个目录就占 3.2 GB。
