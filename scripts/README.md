# Hermes Scripts 目录索引

> 路径：`~/.hermes/scripts/`
> 更新时间：2026-05-28

---

## 📋 文件清单

| # | 文件 | 类型 | 运行方式 |
|---|------|------|---------|
| 1 | `hermes-patches.sh` | Bash 脚本 | 手动执行 |
| 2 | `browser-configure.sh` | Bash 脚本 | 手动执行 |
| 3 | `purge-mm-channel.py` | Python 脚本 | 手动执行 |
| 4 | `hermes-weekly-cleanup.sh` | Bash 脚本 | Cron 定时 |
| 5 | `update-gitlens.sh` | Bash 脚本 | Cron 定时 |
| 6 | `immigration-monitor-prompt.md` | Prompt 模板 | Cron 定时 |

---

## 1. hermes-patches.sh — Hermes 补丁还原脚本

**作用：** 当 `hermes-agent` 上游版本更新后，本地修改会被覆盖。此脚本一键还原所有自定义 patch。

**活跃补丁（当前 8 个）：**

| # | 文件 | 作用 |
|---|------|------|
| 1 | `providers.py` | 自定义 provider 聚合器识别 — `custom:*` 只显示精选模型 |
| 2 | `doctor.py` | `hermes doctor` 误报修复 — 自定义 provider 不再弹「模型不匹配」假警告 |
| 3 | `model_switch.py` | 模型白名单优先（generic） — config 设了 `models` 限制就真生效 |
| 4 | `model_switch.py` | 模型白名单优先（custom_providers） — 同上，`custom_providers` 分组也遵守 |
| 5 | `cron/jobs.py` | 定时任务中文存储修复 — `ensure_ascii=False` 防止汉字变 `\uXXXX` |
| 6 | `stream_consumer.py` | 评论合并 — Agent 评论文字不再被拆成多条独立消息 |
| 7 | `base.py` | 幽灵代码围栏空块 — 长代码跨 chunk 分片不再产生空围栏块 |
| 8 | `stream_consumer.py` | fallback send Thread 路由 — 修复「fallback 发送时回复跑到主频道」 |

**已消除（无需再打）：**
- `gateway/config.py`、`utils.py`、MEDIA 正则 — ✅ 上游合入
- Mattermost 专属修复（6 个）→ 迁移至 `mattermost-enhancer` 插件脚本

**最后验证：** 2026-05-28，Hermes v2026.5.16-1195-g458a94e42

**何时运行：**
- `hermes-agent` 升级后（`git pull` 或 `pip install --upgrade`）
- 发现 Hermes 行为异常时（先用 `check` 模式诊断）

**使用：**
```bash
~/.hermes/scripts/hermes-patches.sh check    # 检查当前状态（默认）
~/.hermes/scripts/hermes-patches.sh apply    # 应用所有 patch
~/.hermes/scripts/hermes-patches.sh status   # 同 check
```

---

## 2. browser-configure.sh — 浏览器自动化方案配置入口

**作用：** Hermes 通过 CDP（Chrome DevTools Protocol）操作 Chrome 浏览器。此脚本是三种浏览器接入方案的统一配置入口，负责 profile 拷贝、daemon 启动、端口发现，最终将 CDP URL 写入 `~/.hermes/.env`。

**三种方案：**

| 方案 | 特点 | 适用场景 |
|------|------|---------|
| `bb-browser` ★默认推荐 | 独立 Chrome + daemon 管理 + 无授权弹窗 | 日常使用、批量/密集操作 |
| `buildin-isolation` | 独立 Chrome + 手动启动 | 临时调试、需自定义 Chrome 参数 |
| `buildin-inspect` | 复用主 Chrome + 共享登录态 | 偶尔轻量操作 |

**何时运行：**
- 首次配置 Hermes 浏览器自动化时（必须执行一次）
- 切换不同方案时
- 主 Chrome 登录态变更后（`bb-browser` / `buildin-isolation` 需重新同步）
- Chrome 重启后（`buildin-inspect` 需重新发现端口）

**使用：**
```bash
~/.hermes/scripts/browser-configure.sh                    # 默认 bb-browser
~/.hermes/scripts/browser-configure.sh bb-browser          # 显式指定
~/.hermes/scripts/browser-configure.sh buildin-isolation   # 独立 Chrome
~/.hermes/scripts/browser-configure.sh buildin-inspect     # 复用主 Chrome
~/.hermes/scripts/browser-configure.sh --help              # 完整帮助
```

---

## 3. purge-mm-channel.py — 清空 Mattermost 频道消息

**作用：** 清空指定 Mattermost 频道的所有历史消息。分两步执行：先分页拉取所有帖子 ID，再逐条 DELETE。需手动输入频道名确认，防止误操作。

**前置条件：** `~/.hermes/.env` 中需配置 `MATTERMOST_URL` 和 `MATTERMOST_TOKEN`。

**何时运行：** 需要清空测试频道的消息记录时（手动执行，需交互确认）。

**使用：**
```bash
python3 ~/.hermes/scripts/purge-mm-channel.py <CHANNEL_ID>
```
执行后会显示频道名称并要求手动输入确认。

---

## 4. hermes-weekly-cleanup.sh — Hermes 每周清理脚本

**作用：** 安全清理 Hermes 运行过程中产生的临时文件和缓存，回收磁盘空间。**绝不触碰核心配置**（config.yaml、.env、SOUL.md、state.db、memories、skills、scripts）。

**清理范围（9 大类）：**

| # | 类别 | 具体内容 | 保留策略 |
|---|------|---------|---------|
| 1 | Chrome 调试缓存 | Service Worker / IndexedDB / Cache / GPUCache 等 | 仅当 Chrome 调试进程未运行时清理 |
| 2 | Python 字节码 | `__pycache__` / `.pytest_cache` | 无条件删除（自动重建） |
| 3 | 日志轮转 | `logs/*.log` 过期删除 + 超大截断（>50MB）+ `/tmp/chrome_*.log` | 3 天过期 |
| 4 | 截图/媒体/模型缓存 | screenshots、documents、audio_cache、image_cache、images、模型缓存 JSON | 3 天过期；模型缓存无条件删除 |
| 5 | 旧会话/请求转储 | `sessions/*.jsonl`、`request_dump_*.json`、WebUI 会话/附件 | 3 天过期 |
| 6 | 旧备份/快照 | `backups/*.zip`、`state-snapshots/` | 3 天过期 |
| 7 | 定时任务输出 | `cron/output/` | 3 天过期 |
| 8 | 失效锁文件 | `gateway.lock`、`webui.pid`、`auth.lock`、`processes.json` | 仅当对应进程未运行时删除 |
| 9 | SQLite VACUUM | `state.db`、`kanban.db` | 仅当 Gateway 未运行时执行 |

**触发方式：** 由 Cron 定时任务 `"清理临时文件"`（Job ID: `3a0686fb07c9`）每周日凌晨 03:00 触发，`no_agent=true` 模式直接执行脚本。

**何时手动运行：** 磁盘空间紧张时、升级前后需要清理缓存时。

**使用：**
```bash
~/.hermes/scripts/hermes-weekly-cleanup.sh
```
stdout 输出摘要报告，详细日志写入 `~/.hermes/logs/cleanup.log`。

---

## 5. update-gitlens.sh — GitLens 自动更新脚本

**作用：** 自动检测并安装 Rebuild-gitlens（第三方 GitLens 重建版）的最新版本，实现本地 VS Code 安装 + SCP 同步到远程服务器 + 清理旧版本残留。

**执行流程：**
1. 从 GitHub Tags 页面抓取最新版本号（绕过 API rate limit）
2. 版本合法性校验（semver 格式 + 非空非 null）
3. 自动探测两种 VSIX 命名格式（纯版本号 vs 带 `v` 前缀）
4. 比对本地已安装版本 + 远程服务器状态，均最新则跳过
5. 下载 VSIX 并本地安装到 VS Code
6. SCP 同步扩展目录到远程服务器 `orb`
7. 用 `jq` 更新远程 `extensions.json` 中的 GitLens 版本和路径
8. 清理本地 + 远程旧版本扩展

**触发方式：** 由 Cron 定时任务 `"Update GitLens"`（Job ID: `666d944bde0a`）每日凌晨 02:00 触发，`no_agent=true` 模式直接投递 stdout 到 Mattermost。

**依赖：** `curl`、`ssh`（免密登录 orb）、`scp`、`jq`、`/usr/local/bin/code`

**何时手动运行：** 需要立即更新 GitLens 而不等 Cron 时。

**使用：**
```bash
~/.hermes/scripts/update-gitlens.sh
```

---

## 6. immigration-monitor-prompt.md — 加拿大移民动态日报 Prompt

**作用：** 加拿大移民日报 Cron 子代理的完整执行指令。定义了从数据抓取到报告输出的四阶段流程（抓取 → 过滤 → 分析 → 输出），以及 iMessage 推送给嫂子的发送策略。

**覆盖信源（8 大类）：**
- **官方：** IRCC 新闻 API、EE 抽签页、处理时间页、OINP 更新页 & 通道总览、IRCC Notices
- **媒体：** CIC News、CIC Times、Moving2Canada、Immigration.ca、Immigration News Canada
- **Reddit（5 板块）：** r/ImmigrationCanada、r/expressentrycanada、r/CanadaVisa、r/canada、r/ontario
- **X（4 账号）：** @CitImmCanada、@MarcMillerVM、@ONgov、@GovCanJobsEDSC
- **小红书：** 10 组关键词 + 博主 DecisionMade
- **补充搜索：** Brave Search 5 组关键词

**触发方式：** 由 Cron 定时任务 `"加拿大移民日报"`（Job ID: `2e081401e374`）每日 17:00 CST 触发，自动加载 `role-canada-affairs` + `doko-*` + `nomad-imessage` skills，使用 `doubao-seed-2.0-pro` 模型。

**何时修改：** 需要调整信源、过滤规则、报告模板或 iMessage 推送策略时。

**使用：**
```bash
# 直接编辑（修改后下次 Cron 触发时自动生效，无需重启）
vim ~/.hermes/scripts/immigration-monitor-prompt.md
```

---

## 📊 运行频率总览

| 脚本 | 触发方式 | 频率 | Cron Job ID |
|------|---------|------|-------------|
| `hermes-patches.sh` | 手动 | 按需（升级后） | — |
| `browser-configure.sh` | 手动 | 按需（配置变更时） | — |
| `purge-mm-channel.py` | 手动 | 按需（需交互确认） | — |
| `hermes-weekly-cleanup.sh` | Cron | 每周日 03:00 | `3a0686fb07c9` |
| `update-gitlens.sh` | Cron | 每日 02:00 | `666d944bde0a` |
| `immigration-monitor-prompt.md` | Cron | 每日 17:00 | `2e081401e374` |
