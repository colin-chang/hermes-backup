---
name: mattermost-operations
description: Mattermost 自部署运维 — 推送通知/网络/配置/容器管理
version: 3.28.0
---
# Mattermost 运维操作

Mattermost 是用户的主消息平台（Docker 部署于 `~/Developer/Services/Mattermost/`），用于 Hermes Agent。本 Skill 覆盖日常运维、故障诊断、配置管理及插件化迁移。

## 变更记录

- **v3.28.0** (2026-05-25): **P53（幽灵代码围栏导致内容消失）**。`truncate_message()` 的代码块 carry-over 在 short-circuit 路径下失效：Chunk 1 末尾的闭合 fence 在 Chunk 2 中因缺少开启围栏前缀，被 CommonMark 解析器视为新的开启围栏，吞掉后续的 markdown 标题和格式化内容。用户体感为「方案 B 的内容和标题消失了」。诊断关键：API 取证→逐行检查 markdown 结构→寻找孤立的 ` ``` `。**诊断方法论**：消息内容消失类问题必须先 API 取证再下结论，禁止直接假设是分片/折叠。新增 `references/ghost-code-fence-content-loss.md`。`gateway/platforms/mattermost.py` 将 `MAX_POST_LENGTH` 硬编码为 4000 字符（OpenClaw 遗留值），长消息被 `truncate_message()` 拆分为多条帖子后在 CRT Thread 中被折叠。Mattermost 实际支持 16383 字符。新增 `references/mattermost-message-truncation.md`。**iPad 端表格压缩 CSS 分析**。Mattermost 的 `.table-responsive` 缺少关键 CSS（`overflow-x: auto`），加上 `.post-message` 的 `overflow: clip` 在 iOS Safari 上更激进，`table-layout: fixed` 级联约束导致表格向内压缩而非溢出滚动。新增 `references/ipad-table-rendering.md`。
- **v3.26.0** (2026-05-24): **Footer 可视化调研**。Context Ring 渲染可行性分析——Hermes WebUI 的 SVG ring 实现原理、Mattermost 约束下的三种方案对比（Pillow PNG / Emoji 圆点 / Unicode）、Pillow 方案技术链路与关键挑战、Emoji 方案作为低风险替代。v5 居中表格方案被标记为已废弃（用户反馈视觉不可接受）。新增 `references/context-ring-feasibility.md`。
- **v3.25.0** (2026-05-24): **P50（评论→正文合并）已上线**。
- **v3.24.0** (2026-05-24): **消息碎片化深度分析**。`hermes-agent` Skill 的 `references/mattermost-streaming-fragmentation.md` 扩展为完整源码级分析 — 三条并行消息管线架构图、`_send_commentary()` 断裂点（stream_consumer.py:552）、`__reset__` 工具进度拆条机制（run.py:14894）、四级修复方案（配置→评论合并→抑制 reset→全量合并）、关键源码索引表。本 Skill 的 SKILL.md 添加交叉引用。
- **v3.23.0** (2026-05-24): 新增 **Runtime Footer 内联渲染**。流式模式下 footer 以独立消息发送的根因分析（gateway/run.py 双路径）、插件拦截方案（`send()` 检测 ` · ` 分隔符 → `PUT /posts/{id}` 编辑上一条消息追加为脚注）。**样式迭代**：两行→单行 `── *text* ──`（斜体）→ `` `── text ──` ``（inline code 灰色等宽，Mattermost 不支持 CSS 的唯一可行方案）。新增 `references/runtime-footer-inline.md`。
- **v3.23.0** (2026-05-24): 新增 **Runtime Footer 编辑合并机制**。插件在 `send()` 中拦截 Gateway 的独立 footer 消息，改为编辑上一条 Bot 帖子，以 inline code 脚注样式追加到末尾。新增 `references/footer-edit-merge.md` — 含检测逻辑、API 拉取 Pitfall、格式演变、降级策略。
- **v3.23.0** (2026-05-24): 新增 **Footer 拦截编辑合并模式**。Gateway 流式模式下 runtime_footer 作为独立消息发送，插件在 `send()` 中拦截并通过 `PUT /posts/{id}` 编辑上一条消息，合并为同一条消息脚注。新增 `references/footer-interception-pattern.md`。
- **v3.22.0** (2026-05-24): 新增 **P49**（Empty Response → fallback_prior_turn_content）。LLM 返回空文本后 turn 以 fallback 结束，用户仅收到 39 字符的截断片段。含完整诊断步骤（日志特征、grep 命令）、模型自诊螺旋识别、与 Stream Drop 的关联分析。新增 `references/empty-response-fallback-diagnosis.md`。
- **v3.21.0** (2026-05-24): 新增 **Channel → Thread 模型继承**（插件 v2.1.0）。`__init__.py` 注册 `pre_gateway_dispatch` hook，在消息处理最早阶段检测 Thread 消息，自动从父 Channel 继承 `_session_model_overrides`。更新 `slash-command-architecture.md` 新增继承机制文档，`README.zh-CN.md` 新增小贴士区块。
- **v3.20.0** (2026-05-24): 新增 **P48**（asyncio 并发回调竞态）。`asyncio.start_server` 为每个连接创建独立协程，用户双击审批按钮时两个请求同时进入 `_handle_callback`，在第一个完成 `resolve_gateway_approval` 之前第二个也通过校验，导致竞态。修复：按 `session_key` 使用 `asyncio.Lock` 串行化审批处理，并发请求返回即时「⏳ 处理中」update + 清空按钮。更新 `references/slash-command-architecture.md` 新增 P48 条目。
- **v3.19.0** (2026-05-23): P46 修复完成——`source.thread_id` 守卫已应用（仅 Thread 上下文执行 canonical key fallback），修复 Telegram topic mode CI 回归。**插件脚本扩展**：`hermes-mattermost-enhancer.sh` 增加 Patch 3 (P46) + Patch 4 (P46b)，面向第三方 Mattermost 用户交付 Gateway clarify 修复。`hermes-patches.sh` base.py 补丁逻辑从失效 byte 匹配更新为字符串匹配。更新 `references/clarify-session-collision.md` 上线状态，更新 `references/patch-plugin-boundary.md` 反映插件脚本现有 4 个补丁。
- **v3.17.0** (2026-05-23): P46 修复完成并上线。**修复 1（插件侧）**：`mattermost-enhancer` 插件覆盖 `send_clarify()` 渲染交互卡片，新增 `cards.py` 函数（`render_clarify_card`、`render_clarify_choice_confirmed_card`、`render_clarify_other_prompt_card`），`adapter.py` 新增 `_handle_clarify_choice_callback` / `_handle_clarify_other_callback`。**修复 2（源码侧）**：`gateway/run.py` clarify 检查增加 canonical session_key fallback，已注册为 `hermes-patches.sh` P46 patch，已提交上游 [PR #30669](https://github.com/NousResearch/hermes-agent/pull/30669)。**Pitfall 47**：MM action_id 不能含下划线（`_`），否则按钮回调报「找不到该页面」。已加入 `slash-command-architecture.md`。插件 README 中英文同步更新。
- **v3.17.0** (2026-05-23): **P46 修复完成并上线。修复 1（插件侧）**：`mattermost-enhancer` 插件覆盖 `send_clarify()` 渲染交互卡片，新增 `cards.py` 函数（`render_clarify_card`、`render_clarify_choice_confirmed_card`、`render_clarify_other_prompt_card`），`adapter.py` 新增 `_handle_clarify_choice_callback` / `_handle_clarify_other_callback`。**修复 2（源码侧，两层防御）**：Layer 1 在 `_handle_message` clarify 拦截处做 canonical session_key fallback；Layer 2 在 `_handle_message_with_agent` 创建 Session 前再次检查 pending clarify。已注册为 `hermes-patches.sh` P46a + P46b patch，已提交上游 [PR #30669](https://github.com/NousResearch/hermes-agent/pull/30669)。**P47**：MM action_id 不能含下划线/连字符，否则按钮回调报「找不到该页面」，修复为纯字母数字。已加入 `references/slash-command-architecture.md`。插件 README 中英文同步更新。
- **v3.16.0** (2026-05-23): 新增 **P46**（Clarify 阻塞 + Session 分裂）。`clarify` 工具等待用户回复时 Gateway 对同一 Thread 消息执行双路由——传给 clarify 的同时创建新 Session，导致同一 Thread 两个 Session 并行、新 Session 无上下文。详见 `references/clarify-session-collision.md`。
- **v3.16.0** (2026-05-23): 新增 **P46**（Clarify 阻塞 + Session 分裂）。
- **v3.14.0** (2026-05-22): **P38 增强**。原 P38 修复仅覆盖 Thread 根帖 root_id 为空的场景。新增 API 反查防御：当 root_id 为空且 reply_mode=thread 时，通过 `_api_get(f"posts/{post_id}")` 查询真正的 root_id，防止 MM WebSocket 异常导致 Thread 回复的 root_id 丢失时 session 分裂。详见 `references/thread-root-post-id-fix.md`。新增 `references/patch-plugin-boundary.md` — 入站 vs 出站补丁分类，解释为什么某些补丁能插件化、某些必须保持 source patch。
- **v3.11.0** (2026-05-22): 新增 **P37**（`send_exec_approval` 审批通知路由丢失）。`send_exec_approval` 调用 `self.send()` 时未传递 `metadata`，Thread 模式下提示落到频道级，CRT 用户看不见 → 审批超时卡死。修复：`self.send(chat_id, msg, metadata=metadata)`。`_send_local_file`/`_send_url_as_file` 同源问题（通过 `_get_thread_root_id` 间接调用，缺 metadata 入参），待后续网关侧统一修复。
- **v3.10.0** (2026-05-22): 新增 **P36**（`_resolve_root_id` 失败时缺少 metadata fallback 导致并发 Thread 串台）。`send()` if-elif 结构缺陷：reply_to 匹配时 if 分支吞掉 _resolve_root_id 失败，metadata.thread_id fallback 因 Python 语义永不触发。修复：if 内嵌套 elif 降级分支。新增 `references/thread-routing-metadata-fallback.md` 含完整日志追踪、根因分析和修复代码。
- **v3.9.0** (2026-05-22): `references/plugin-packaging-conventions.md` 新增「文档编辑 Git 工作流」— 文档迭代使用 amend + force push 保持单条提交。新增「小贴士区块规范」— 部署相关补充信息以 blockquote 形式放在项目结构之后、许可之前，每条一问一答一行，不放代码块不分小节。检查清单新增对应条目。 新增「插件名称匹配故障」节 — `config.yaml` 的 `plugins.enabled` 名与 `plugin.yaml` 的 `name` 不匹配导致插件静默不加载的根因、诊断和修复流程。新增「Shell registry 字符串转义陷阱」节 — `\\\\\"` vs `\\\"` 转义层级错误和中文引号 `\"...\"` 被 shell 误解析的问题。检查清单新增相关验证条目。
- **v3.7.0** (2026-05-28): `references/plugin-packaging-conventions.md` 新增「`apply` 交互式重启模式」— 配套脚本的 `apply` 子命令不得要求用户单独执行重启，必须在 patch 完成后交互式询问。新增「文档编辑工作流」节 — 中文优先，定稿后再同步英文
- **v3.6.0** (2026-05-22): `references/plugin-packaging-conventions.md` 新增「环境变量文档规范」节 — 文档环境变量配置必须与代码 `_os.getenv()` 调用严格一致。核心规则：代码是唯一真相源 / `.env` 是实际配置 / README 是衍生文档。特别标注 `MATTERMOST_CALLBACK_URL`：代码有 fallback 但 Docker 下不生效，对自部署用户是必填项。新增检查清单条目：环境变量文档与代码一一对应、必填/可选分界明确、Docker 特例标注
- **v3.5.0** (2026-05-22): `references/plugin-packaging-conventions.md` 新增「文档写作风格」节 — 面向小白用户的 README 写作规范：说人话举场景标截图位、功能/Bug 分表、架构用比喻、截图位约定。本次 session 用户明确要求文档面向非技术用户
- **v3.5.0** (2026-05-28): 新增 `references/plugin-doc-and-script-conventions.md` — 插件 README 文档结构规范（面向小白的功能描述/Bug独立表/大白话架构解释/快速上手）与配套脚本消息约定（双语中英格式、交互式重启流程、禁止抽象术语）。见该 reference
- **v3.4.0** (2026-05-28): 插件重命名 `mattermost-enhancer` → `hermes-plugin-mattermost-enhancer`（v2.0.0）。文档净化（移除 patch 编号/行数/本机路径等个性化内容），添加中英文 README + LICENSE + .gitignore + 配套 `scripts/hermes-mattermost-enhancer.sh`。详见 `references/plugin-packaging-conventions.md`
- **v3.5.0** (2026-05-28): 补充文档约定：双语输出规范（EN first, ZH in parens）、先中文后英文的编辑流程、`hermes-patches.sh` 标签用户化规范、中文引号陷阱。`references/plugin-packaging-conventions.md` 扩展。
- **v3.3.0** (2026-05-22): 更新插件迁移状态（12 patches，移除 send_typing Thread registry 残留）。新增 §9 Patch 标签人性化 — registry 标签从代码描述改为功能影响描述，提升 `check` 输出可读性。更新 `references/plugin-migration-patterns.md`
- **v3.1.0** (2026-05-22): 新增 P35（inline import 导致回调延迟）。`_handle_callback()` 内 `from tools.approval import resolve_gateway_approval` 移至模块级别，消除按钮点击 1-3 秒延迟及"无效的操作 id"竞态错误。参见 `references/plugin-migration-patterns.md` §5
- **v3.0.0** (2026-05-22): **全部 mattermost.py 补丁迁移完成**。patch 6（`_resolve_root_id`）+ patch 10c（MEDIA 静默跳过）迁入插件 `send()`/`_send_local_file()`/`_send_url_as_file()` 覆写。`mattermost.py` 源码回滚至上游 a91a57fa5（852 行，零修改）。`hermes-patches.sh` 降至 13 patches（移除 patches 6/7/10c，-673 行）。新增 P34（双重 callback server 启动冲突）及 `references/plugin-migration-patterns.md`
- **v2.10.0** (2026-05-22): DM 审批完整迁移至 `mattermost-enhancer` 插件。`send_exec_approval`/`_get_or_create_dm`/`_verify_signature`/`_stop_callback_server`/`connect`/`disconnect` 全部迁入插件 `adapter.py`。`hermes-patches.sh` 移除 patches 7a-7d（~493 行）
- **v2.9.0** (2026-05-21): 插件重命名 `mattermost-approval` → `mattermost-enhancer`。P32（Channel/Thread 会话区分）经用户测试确认通过。所有代码示例和日志 logger 名称同步更新
- **v2.8.0** (2026-05-21): **重大修正** — P32/P33 完全重写：MM Slash Command payload **原生包含 `root_id` 字段**（Channel 顶层为空，Thread 中为 root post ID），无需 API 反查。`_find_user_thread_root_id()` 已删除。P17 根因描述更新。references/slash-command-architecture.md "关键缺失：无 root_id" 节重写为 "root_id 字段：Thread 上下文"
- **v2.7.0** (2026-05-21): 新增 P33（HTTP 回调时序——asyncio.sleep 等待消息创建）；P32 补充时序根因
- **v2.6.0** (2026-05-21): 新增 P31（Deny 后按钮不消失需清空 actions）+ P32（Channel/Thread 会话区分 — 查用户最近帖子而非只找有 root_id 的帖子）；更新 API 反查代码示例
- **v2.5.0** (2026-05-21): 新增 P30（LLM 自报模型错误需 _pending_model_notes）；P25 补充 select name 字段作 placeholder；补充模型切换诊断方法
- **v2.4.0** (2026-05-21): P25 修正为 select 下拉列表替代按钮；新增 P28（select 回调用 selected_option 非 model_id）+ P29（日志截断 [:60] 误判 session_key 不匹配）
- **v2.3.0** (2026-05-21): 重大更新 P23-P27——P23/P26 修正为绕过 switch_model() 直接构建 override；P24 扩展到 Bot API 发帖（不仅是 update）；新增 P27（Slash Command 响应以用户身份显示→返回空 {}）
- **v2.2.0** (2026-05-20): 新增 Pitfall 23-26（switch_model 需 explicit_provider/update 响应消息重复/模型列表混乱/模型切换 api_key 为空失效）；补充卡片更新机制说明
- **v2.1.0** (2026-05-20): 新增 Pitfall 18-22（callback 异常吞噬/ImportError 隐藏/Bot API 权限/插件发现降级/Slash Command URL 为空降级 WS）
- **v2.0.0** (2026-05-19): 修正 v11.x Team Edition HPNS/TPNS License 要求；新增 push-proxy 自建指南；修正容器无 shell 的诊断命令
- **v1.0.0**: 初始版本

## 触发条件

- 用户询问 Mattermost 相关问题（推送通知/配置/网络/容器/升级）
- 用户询问 `hermes-plugin-mattermost-enhancer` 插件相关问题
- Mattermost 移动端或桌面端异常
- 服务器端日志分析
- 容器管理（mm-app / mm-postgres）

## 文档编辑工作流

编辑插件仓库文档时，遵守以下顺序：

1. **只编辑中文文档（`README.zh-CN.md`）**，直到内容定稿
2. **用户确认中文定稿后**，再将内容同步到英文文档（`README.md`）
3. 不要在中文未定稿时同步编辑英文——避免来回翻改两份文档

> 这是用户明确要求的工作流："先不用更新英文文档，我们先编辑中文文档，等我编辑定稿之后，再统一同步到英文文档。"

## Mattermost 部署概况

用户通过 Docker Compose 自托管 Mattermost Team Edition，路径：
```
/Users/Colin/Developer/Services/Mattermost/
```

关键文件：
- `docker-compose.yml` — 主服务定义（postgres + mattermost）
- `.env` — 环境变量（域名、镜像版本、DB 密码等）
- `volumes/app/mattermost/config/config.json` — Mattermost 运行时配置
- `volumes/app/mattermost/logs/mattermost.log` — 服务日志

服务容器：`mm-app`（mattermost）、`mm-postgres`（postgres）

### 快速部署/重启命令

```bash
cd /Users/Colin/Developer/Services/Mattermost
docker compose down && docker compose up -d
```
修改 `config.json` 不需要 down，但修改 `docker-compose.yml` 环境变量需要重建容器。

## 推送通知（Push Notifications）

Mattermost 移动端推送通知的配置和故障诊断见 [references/push-notifications.md](references/push-notifications.md)。

核心要点：
- **v11.x 起 Team Edition 的 HPNS 和 TPNS 均需 Enterprise License**。日志会出现 `"Push notifications are disabled - license missing"`
- 唯一免费方案：自建 [mattermost-push-proxy](references/mattermost-push-proxy-setup.md)（需 Firebase + Apple APNs 凭证）
- 替代方案：降级到 v10.x ESR 保留免费 TPNS，或容忍 WebSocket 兜底（App 关闭久了收不到）
- 容器无 Shell（最小镜像），诊断用 `docker inspect` + 日志文件，不能 `docker exec mm-app wget/curl`

## 常用诊断命令

```bash
# 查看容器状态
docker ps --filter name=mm-

# 查看推送相关日志（容器无 shell，直接读宿主机挂载的日志文件）
grep -i 'push\|notification.*error' volumes/app/mattermost/logs/mattermost.log | tail -30

# 查看推送配置
grep -i 'SendPush\|PushNotif' volumes/app/mattermost/config/config.json

# 检查容器环境变量（含代理配置）
docker inspect mm-app --format '{{range .Config.Env}}{{println .}}{{end}}' | grep -i 'proxy\|push'

# 注意：mm-app 容器无 sh/ash/bash，不能用 docker exec 跑 wget/curl
# 测试外网连通性需从宿主机跑 curl，或用 docker inspect 检查 proxy 配置
```

## Slash Command 与插件架构

Mattermost 客户端拦截所有 `/` 开头消息，**必须**注册 Slash Command 才能接收。
Slash Command payload 包含 `root_id` 字段（Channel 顶层为空，Thread 中为 root post ID），无需 API 反查。

**插件 `hermes-plugin-mattermost-enhancer`（`~/.hermes/plugins/mattermost-enhancer/`）已完整覆盖所有 Mattermost 自定义能力：**
- `_resolve_root_id` + Thread root_id 解析（`send()`/`_send_local_file()`/`_send_url_as_file()` 覆写）
- MEDIA 文件不存在时静默跳过（`_send_local_file()` 覆写）
- DM 审批（`send_exec_approval` → DM 卡片 → 按钮回调 → `_handle_callback`）
- `/model` 模型切换（select 下拉列表 + session override + `_pending_model_notes`）
- **Channel → Thread 模型继承**（`pre_gateway_dispatch` hook — Channel 切模型后新 Thread 自动继承，v2.1.0 新增）
- `/new` 会话重置（确认卡片 + `_reset_session`）
- `send_typing` Thread 路由修复（`adapter.py` 覆写 `send_typing()`，metadata thread_id 传入 parent_id）
- `connect`/`disconnect` 生命周期（回调服务器启停）
- **Clarify 交互卡片渲染**：`send_clarify()` 覆写，用 MM button 渲染选项 + 「✍️ 其他」自由文本按钮（v2.1.0 新增）
- **Runtime Footer 内联合并**：`send()` 检测 footer 行（` · ` 分隔符），拦截后编辑上一条消息追加为脚注（v2.2.0 新增）

**`mattermost.py` 源码已零修改**（852 行，上游 a91a57fa5）。所有自定义逻辑均由插件接管。

详见 [references/slash-command-architecture.md](references/slash-command-architecture.md)（含 30+ 已知 Pitfall）。
参见 [references/plugin-migration-patterns.md](references/plugin-migration-patterns.md) — 源码 patch → 插件迁移的模式与陷阱。
参见 [references/thread-routing-metadata-fallback.md](references/thread-routing-metadata-fallback.md) — P36：并发 Thread 串台的根因、日志追踪与修复代码。
参见 [references/gateway-restart-session-loss.md](references/gateway-restart-session-loss.md) — P39：网关重启导致会话历史丢失，用户感知为「串台」的诊断与区分。
参见 [references/clarify-session-collision.md](references/clarify-session-collision.md) — P46：clarify 阻塞等待时 Gateway 双路由导致 Session 分裂，用户体感「突然失忆」的诊断与规避。
参见 [references/ipad-table-rendering.md](references/ipad-table-rendering.md) — iPad 端表格压缩 CSS 根因分析。
参见 [references/ghost-code-fence-content-loss.md](references/ghost-code-fence-content-loss.md) — P53：幽灵代码围栏导致消息内容消失的根因、诊断方法及规避方案。
参见 [references/empty-response-fallback-diagnosis.md](references/empty-response-fallback-diagnosis.md) — P49：Empty Response → fallback_prior_turn_content 的根因、日志特征、诊断命令与模型自诊螺旋应对。
参见 [references/runtime-footer-inline.md](references/runtime-footer-inline.md) — Runtime Footer 流式模式独立消息的根因、双路径分析、插件拦截编辑方案。
**消息碎片化完整分析**：三条并行消息管线、`_send_commentary()` 断裂点、`__reset__` 机制、四级修复方案 — 由 `hermes-agent` Skill 的 `references/mattermost-streaming-fragmentation.md` 维护（跨 Skill 交叉引用）。
插件 API 契约文档：`~/.hermes/plugins/hermes-plugin-mattermost-enhancer/references/api-contracts.md`
插件打包规范（中英文 README / LICENSE / .gitignore / 配套脚本）：`references/plugin-packaging-conventions.md`（含 ⚠️ 插件名称匹配故障诊断和 Shell registry 转义陷阱）

核心要点：
- **删除 Slash Command 注册 ≠ `/model` 走 WebSocket** — 会被客户端静默拦截
- Slash Command 响应以用户身份发送 → 卡片改用 Bot API `_api_post("posts", ...)` 发帖
- Interactive Message 限制：5 actions/attachment, 5 attachments/message（但 select 下拉列表只需 1 action，推荐使用）
- session_key 构建需要 `channel_id + root_id`，Slash Command payload 的 `root_id` 字段提供 Thread 上下文（Channel 顶层时为空）
- **Callback Server 异常吞噬**（P18）：`_handler` 的 `except` 不记录日志 → 静默空回复，必须加 `logger.exception()`
- **插件 ImportError 隐藏**（P19）：`from .module import nonexistent_func` 在调用时才抛异常，被 P18 吞噬
- **Bot API 无法读取 Slash Command URL**（P20）：非 admin token 返回空值，需查数据库
- **插件发现失败被 debug 吞噬**（P21）：Gateway 启动时插件加载异常不显眼，运行时静默降级为内置适配器
- **Slash Command URL 为空时降级为 WebSocket**（P22）：导致双重显示+错误 thread+用户头像
- **switch_model 路由 custom_provider 模型到错误 provider**（P23）：必须绕过 switch_model()，直接从 custom_providers 配置构建 session override（4 字段：provider/base_url/api_key/api_mode），否则 api_key 为空 override 不生效
- **Bot API 帖子 message + props 双重显示**（P24）：`_post_card_in_thread()` 的 message 必须留空，内容仅放 props.attachments；callback update 响应同理
- **模型选择器用 select 下拉列表**（P25）：取代多行按钮，1 个 attachment + 1 个 action，`name` 字段作为 placeholder 显示当前模型（如 "当前: zenmux/deepseek-v4-pro"），选项按 provider 分组显示 `[ProviderName] model-name` 格式，`value` 保持完整 `model_id` 不变
- **LLM 自报模型错误**（P30）：模型切换在 API 层面生效，但 LLM 回答"当前模型"时仍报默认模型——必须设置 `runner._pending_model_notes[session_key]`，Gateway 会在下条消息前注入切换通知
- **select 回调用 selected_option 非 model_id**（P28）：回调中 `context.selected_option` 包含选中值，需兼容 button 格式
- **日志截断 [:60] 误判 session_key 不匹配**（P29）：完整 session_key 81 字符被截断为 60，导致误认为 root_id 不完整
- **Deny 后卡片按钮不消失**（P31）：MM 的 `update` 响应只替换 message/props，保留原始按钮。必须在 `props.attachments` 中返回空 `actions` 数组来清除按钮，否则 Deny 后用户可重复点击导致 "No pending approval found" 报错。即使 `count == 0`（审批已处理）也必须返回 `update` 清空按钮，不能只返回 `ephemeral_text`
- **Channel/Thread 会话区分**（P32）：**MM Slash Command payload 原生包含 `root_id` 字段！** 在 Thread 中发送时 `root_id=<root_post_id>`，在 Channel 顶层发送时 `root_id=""`。直接从 `params.get("root_id", "") or None` 读取即可，无需 API 反查。旧版文档声称"payload 不含 root_id"是错误的——可能当时未测试 Thread 中的场景。`_find_user_thread_root_id()` 方法已删除
- **并发 Thread 串台**（P36）：`send()` if-elif 结构导致 `_resolve_root_id` API 调用失败时缺少 metadata.thread_id 降级，消息落到频道级。两个 Thread 并发处理时共享 aiohttp 连接池，API 压力大时触发。修复：if 内嵌套 elif 分支降级到 metadata。详见 [references/thread-routing-metadata-fallback.md](references/thread-routing-metadata-fallback.md)
- **审批通知路由丢失**（P37）：send_exec_approval 收到 metadata（含 thread_id），但调用 self.send() 发提示时未传递 metadata。导致 Thread 模式下提示落到频道级，CRT 用户看不到，审批超时卡死。修复：self.send() 传入 metadata=metadata。_send_local_file / _send_url_as_file 同源但缺 metadata 入参。
- **Thread 根帖进度消息落到频道**（P38）：非插件 Bug，Gateway mattermost.py。Thread 根帖 WebSocket 事件中 root_id 为空字符串，or None 将其转为 None。导致 source.thread_id 为空，所有 Still working 等进度通知消息失去 Thread 上下文，落到频道。修复：CRT 模式下 root_id 为空时用 post_id 兜底。hermes-patches.sh 已注册 patch #11。详见 references/thread-root-post-id-fix.md
- **网关重启导致会话丢失**（P39）：非插件 Bug。Gateway 重启后，内存中的 conversation history 丢失。下一次用户在同一 Thread 发消息时 session 命中但 `history=0`，Agent 不记得之前的对话。用户体感为「串台」。诊断：对照 `gateway.run: Gateway running` 重启时间与下一次 `conversation turn` 的 `history=N`。若 N=0 且对话间隔跨重启，则是会话丢失。详见 references/gateway-restart-session-loss.md
- **Clarify 阻塞 + Session 分裂**（P46）：非插件 Bug，Gateway 双路由。`clarify` 等待时用户回复被同时传给 clarify 和新 Session，导致同一 Thread 两个 Session 并行。**已修复**：`gateway/run.py` 两层防御（`_handle_message` canonical key fallback + `_handle_message_with_agent` 二次拦截），已注册 `hermes-patches.sh`，已提交[上游 PR](https://github.com/NousResearch/hermes-agent/pull/30669)。`source.thread_id` 守卫已应用，修复了 Telegram topic mode CI 回归。**加剧因素**：Mattermost 适配器不渲染 clarify 交互卡片 → 用户看不到提问 → 更容易触发 P46。**插件侧修复**：`send_clarify()` 覆写渲染为 MM interactive card button。详见 [references/clarify-session-collision.md](references/clarify-session-collision.md)。**归属决策**：P46/P46b 是通用 Gateway bug（非 Mattermost 专属），保留在全局 `hermes-patches.sh`；同时纳入插件脚本（面向没有全局脚本的第三方 Mattermost 用户），详见 [references/patch-plugin-boundary.md](references/patch-plugin-boundary.md)。
- **Clarify 交互卡片 Mattermost 不渲染**（P47）：与 P46 连锁效应。按钮 action_id 含特殊字符（`_`、`-`）时回调报「找不到该页面」——修复为纯字母数字（Pitfall 47，见 [references/slash-command-architecture.md](references/slash-command-architecture.md)）
- **asyncio 并发回调竞态 — 双击审批按钮**（P48）：`asyncio.start_server` 独立协程处理每个连接，用户快速双击时两个请求同时进入回调处理器。修复：按 `session_key` 使用 `asyncio.Lock` 串行化审批处理，并发请求返回即时「⏳ 处理中」update + 清空按钮（Pitfall 48，见 [references/slash-command-architecture.md](references/slash-command-architecture.md)）
- **MAX_POST_LENGTH = 4000 导致消息截断**（P51）：`gateway/platforms/mattermost.py` 硬编码 4000 字符上限（OpenClaw 遗留值），长消息被拆分为多条帖子后在 CRT Thread 中折叠，用户看不到后续内容。Mattermost 服务器实际支持 16383。修复：`MAX_POST_LENGTH = 16000`。详见 [references/mattermost-message-truncation.md](references/mattermost-message-truncation.md)
- **⚠️ 关联**（P53）：截断后的代码块 carry-over 可能产生幽灵围栏吞掉后续内容。详见 [references/ghost-code-fence-content-loss.md](references/ghost-code-fence-content-loss.md)
- **iPad 端表格压缩**：`.table-responsive` 缺少 overflow CSS + `.post-message` 的 `overflow: clip` 在 iOS Safari 更激进 + `table-layout: fixed` 级联约束。详见 [references/ipad-table-rendering.md](references/ipad-table-rendering.md)
- **幽灵代码围栏吞内容**（P53）：`truncate_message()` 的 short-circuit 路径未 prepend code fence prefix，导致 Chunk 2 中孤立的 ` ``` ` 被 CommonMark 解析为开启围栏，吞掉后续标题和格式化文本。诊断：API 取证→逐行检查→寻找孤 fence。详见 [references/ghost-code-fence-content-loss.md](references/ghost-code-fence-content-loss.md)
- **Empty Response → fallback_prior_turn_content**（P49）：LLM 在大量 tool calls 后返回空文本，turn 以 `fallback_prior_turn_content` 结束，用户仅收到 39 字符的截断片段。诊断关键：日志中 `reason=fallback_prior_turn_content` + `response_len < 100`。**模型自诊螺旋**：追问原因时模型可能陷入 terminal/grep 循环（70+ API calls），须 `/stop` 中断。详见 [references/empty-response-fallback-diagnosis.md](references/empty-response-fallback-diagnosis.md)

**Footer 拦截编辑合并模式**：Gateway 流式模式下 runtime_footer 作为独立消息发送，插件在 `send()` 中拦截并通过 `PUT /posts/{id}` API 编辑上一条消息，将 footer 合并为同一条消息的脚注。实现要点：footer 检测（` · ` 分隔符）、帖子追踪、API 实时拉取内容（避免覆盖流式正文）、降级策略。详见 [references/footer-interception-pattern.md](references/footer-interception-pattern.md)

- **Runtime Footer 编辑合并**（v2.2.0 新增）：插件拦截 Gateway 的独立 footer 消息，改为编辑上一条 Bot 帖子，将 footer 以 `\`── model 34% ──\`` inline code 脚注样式追加到末尾。含检测逻辑、编辑流程、流式模式 API 拉取 Pitfall、格式演变历史、降级策略。详见 [references/footer-edit-merge.md](references/footer-edit-merge.md)

卡片更新机制关键规则：`{"update": {"message": "...", "props": card}}` 会导致 MM 同时渲染 message 正文和 props.attachments，必须避免内容重叠。select 下拉列表选择后卡片被 update 替换（无按钮），用户需重新 `/model` 获取新卡片。详见 [references/slash-command-architecture.md](references/slash-command-architecture.md)。

## 网络问题

Mattermost 容器访问外网可能受 GFW 影响。解决方案：
1. 容器配 `HTTP_PROXY` / `HTTPS_PROXY` 环境变量
2. 搬至蒙特利尔后自然解决

## Hermes Cron 定时任务排障

[references/hermes-cron-pitfalls.md](references/hermes-cron-pitfalls.md) — Cron 子代理工具不可用、安检误判、Skill ZWJ 拦截、iMessage 发送模板等已知陷阱 P40-P44。

## 开发技巧

对 `hermes-patches.sh` 等 shell 脚本做大规模修改时的工具选择陷阱：
[references/patch-tool-pitfalls.md](references/patch-tool-pitfalls.md) — `patch` 工具在 heredoc / f-string 上的已知问题及 `execute_code` 替代方案。
[references/hermes-patches-conventions.md](references/hermes-patches-conventions.md) — `hermes-patches.sh` 编写规范：注册表约定、check_grep 选型、`_do_patch` 必须在函数体内、同文件多补丁注册表一一对应。
