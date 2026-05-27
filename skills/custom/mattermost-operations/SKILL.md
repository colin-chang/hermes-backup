---
name: mattermost-operations
description: Mattermost 自部署运维 — 推送通知/网络/配置/容器管理
version: 3.44.0
---
# Mattermost 运维操作
---

## 变更记录

- **v3.45.0** (2026-05-30): **补丁验证方法论沉淀**。`references/hermes-patch-lifecycle.md` 新增 old-string 存在性对比验证法：committed vs current 三分类（PATCHED/OBSOLETE/NOT APPLIED），含批量验证代码框架和关键注意事项（Python 转义假阳性、execute_code 自动化推荐）。
- **v3.44.0** (2026-05-30): **hermes-patches.sh 全量过时审查**。对比 Hermes v0.14.0 当前源码逐项验证：14 项 patch 中 13 项已由上游完全修复（identical fix），仅 P57（工具进度消息进 Thread）上游"修复"不完整——添加了 `Platform.MATTERMOST` 但保留了 `source.thread_id` 条件。**但 enhancer 插件 `send()` 中的 `metadata.thread_id` fallback 已覆盖此场景**，P57 在插件生效时不再必要。结论：hermes-patches.sh 整体过时，建议移除或归档。详见 `references/hermes-patch-lifecycle.md`（更新全面过时分析 + 逐项验证矩阵）。**mattermost-enhancer 代码规范改进**：① 提取 `_build_callback_url()` 消除 4 处重复构造（DRY）② `import os` 统一为模块级替代 2 处 `import os as _os` ③ 清理 WS heartbeat 段前重复分隔注释 ④ 中英文 README FAQ 数字同步（3→5 bugs，31→40+ methods）。
- **v3.43.0** (2026-05-28): **P62 — Gateway auto-resume 多 session 同 channel 串台**。
- **v3.43.0** (2026-05-28): **P62 — Gateway auto-resume 多 session 同 channel 串台**。Gateway 重启后 `_schedule_resume_pending_sessions()` auto-resume 所有 `restart_interrupted` session（未做同 channel 去重），导致历史残留 session 的回复落入当前 Thread。日志特征：`Scheduled auto-resume for N` > `Marked M in-flight`，且有 `msg=''` 空消息涌入。修复方向：按 `(platform, chat_id)` 仅 auto-resume 最新 session。新增 `references/gateway-auto-resume-cross-talk.md`。上游 PR [#33391](https://github.com/NousResearch/hermes-agent/pull/33391) — bundled adapter `send_multiple_images()` metadata→root_id Thread 路由修复。
- **v3.42.0** (2026-05-30): **P61 — 图片/视频/文件 Thread 路由丢失**。bundled `mattermost-platform` 适配器 `send_multiple_images()` 接收 `metadata` 参数但**完全忽略**——payload 中无 `root_id`，导致 `image_generate`/`video_generate` 生成的图片和视频永远发到频道级而非 Thread。`send_image()`/`send_video()`/`send_document()` 同样接收 metadata但传给 `_send_local_file()` 时只传 `reply_to=None`。对比：文本消息 `send()`（enhancer 覆写）正确提取 `metadata.thread_id` 作为 `root_id` fallback。新增 `references/media-thread-routing-bug.md` — 含完整调用链（4 条路径）、对比矩阵、修复方案（插件覆写 4 个方法）。
- **v3.37.0** (2026-05-28): 新增 Desktop 客户端已知问题——编辑 Server URL 后静默回退的根因分析（tab webContents origin 覆盖本地存储）与绕过方案（删除→新建）。新增 `references/desktop-client-url-revert.md`。
- **v3.38.0** (2026-05-29): **P57 回退修复 + 插件 v2.3.0 发布**。commit `73439a4` 仅凭 changelog 声明就删除了 Patch 2（progress→thread），但上游"修复"保留了 `source.thread_id` 条件，Channel 根消息时仍为 None，工具进度消息泄露到频道。恢复 Patch 2（`patch_progress_thread`），`hermes-patches.sh` 注册 P57，插件发布 v2.3.0。更新 `references/hermes-patch-lifecycle.md` — P57 反面案例替换旧的 P55 示例，强调删除 patch 前必须验证上游修复的完整语义。新增插件 Release 工作流节。
- **v3.39.0** (2026-05-29): **插件脚本完整覆盖审查 + 模拟全新安装验证**。发现 `hermes-mattermost-enhancer.sh` 仅覆盖 4/9 项 patch（遗漏 P5 评论合并/P6 WebSocket心跳/P7 fallback reply_to/P8 _api_put timeout/P9 幽灵围栏），根因是新增 patch 时仅更新 `hermes-patches.sh` 未同步到插件脚本。完整重写脚本（P1-P9 连贯编号，9/9 check），模拟全新安装验证通过。新增双脚本同步原则 + 模拟全新安装验证流程到 `references/hermes-patch-lifecycle.md`。更新 `references/patch-plugin-boundary.md` 添加当前双归属覆盖表（9 项 P1-P9 与全局 P# 对照）。SKILL.md 新增"插件配套脚本完整性验证"节。
- **v3.42.0** (2026-05-30): **P61 — 图片/视频/文件 Thread 路由丢失**。bundled `mattermost-platform` 适配器 `send_multiple_images()` 接收 `metadata` 参数但**完全忽略**——payload 中无 `root_id`，导致 `image_generate`/`video_generate` 生成的图片和视频永远发到频道级而非 Thread。`send_image()`/`send_video()`/`send_document()` 同样接收 metadata但传给 `_send_local_file()` 时只传 `reply_to=None`。对比：文本消息 `send()`（enhancer 覆写）正确提取 `metadata.thread_id` 作为 `root_id` fallback。新增 `references/media-thread-routing-bug.md` — 含完整调用链（4 条路径）、对比矩阵、修复方案（插件覆写 4 个方法）。
- **v3.41.0** (2026-05-30): **Patch 可消除性审查执行**。基于 v3.40.0 分析结论实施改造：① P6（WebSocket心跳）→ enhancer adapter 覆写 `_ws_connect_and_listen(heartbeat=15.0)`，移除 shell patch；② P8（`_api_put` timeout）→ enhancer `edit_message` 已完整覆写（自带 30s timeout），移除 shell patch；③ P1 标记为可选（插件已有降级）；④ P9 保留 shell patch（覆写 `truncate_message` 需复制 130+ 行上游代码，维护代价远大于 patch）。shell 脚本从 9→7 项源码 patch + 2 项 adapter 覆写检查 = 9/9 总检查。还原 bundled adapter 中 heartbeat=30.0 和 _api_put 无 timeout 的原始状态。中英文 README 同步更新：Bug 表 7→9（新增 #8 WS 断连 + #9 回复碎片化），新增「实现方式」列（Shell Patch vs Adapter Override），「插件 vs 脚本」节更新为 5 个 shell patch + 4 个 adapter override。更新 `references/patch-plugin-boundary.md` 反映最终决策。
- **v3.40.0** (2026-05-29): **Patch 可消除性深度审查**。逐项源码级分析 9 个 patch 是否真正需要修改 Hermes 源码。结论：P6（WebSocket心跳）和 P8（`_api_put` timeout）**不必要**——enhancer 已覆写相关方法；P1（DM审批 user_id）**可选**——插件已有降级方案；P9（幽灵围栏）**保留 patch**——覆写 130+ 行 `truncate_message` 代价大于 patch；仅 P2/P3/P4/P5/P7 必须保留源码 patch（修改 gateway 调用方代码，adapter 覆写无法影响上游决策）。关键发现：P2 不能仅靠 `metadata.thread_id` 降级——因为 `_progress_thread_id` 走 else 分支 `= source.thread_id = None`，导致 `_progress_metadata = None`，降级方案根本不会被触发。P2 替代路径（修改 `_progress_thread_id` 像 Slack 一样 fallback 到 `event_message_id`）仍需改 run.py，patch 不可避免，只是改哪个变量的区别。新增"Patch 可消除性审查"到 `references/patch-plugin-boundary.md`，双归属覆盖表新增分类列。新增维护规则：新增 patch 前必须做可消除性审查。
- **v3.36.0** (2026-05-29): **上游 PR [#33335](https://github.com/NousResearch/hermes-agent/pull/33335) 已提交**。P55（`_send_fallback_final` 缺 `reply_to`）+ P56（`_api_put` 缺 timeout），仅含 2 个文件的精确修复，未混入其他本地 patch。`hermes-patches.sh` 新增 P55/P56 注册表条目和 apply 脚本（15/15 check 通过）。更新 `references/gateway-stream-consumer-diagnostics.md` 上游 Bug 清单状态（待提交→已提交 PR）。新增 PR 提交工作流（stash→精确 apply→确认→commit→恢复）。
- **v3.35.0** (2026-05-28): **P58/P59/P60 修复完成并验证**。5 项修复全部实施：① `MAX_MESSAGE_LENGTH = 4000` 属性（gateway `getattr` 不再回退到 4096 默认值）② `_resolve_root_id` LRU 缓存（5 分钟 TTL，避免重复 API 调用风暴）③ 覆写 `edit_message`（30s timeout + 空内容防护 + 分类错误消息，消除 `Stream send/edit error: ` 空白日志）④ Footer 编辑路径改用 `edit_message`（不再直接调无 timeout 的 `_api_put`）⑤ `MATTERMOST_URL` 从 `https://mm.a-nomad.com` 改为 `http://localhost:8065` 直连（**根因修复**：Bot 经 Cloudflare 代理时 WebSocket 每 30 秒断连，直连后零断连）。commit d185642。更新 `references/gateway-stream-consumer-diagnostics.md` 补充已实施修复细节和验证结果。
- **v3.34.0** (2026-05-28): **P58/P59/P60 Gateway Stream Consumer 消息丢失与截断诊断**。Hermes 重装后 Thread 对话频繁无回复+消息截断。三层因果链：① WebSocket 每 30 秒断连（反向代理超时）→ ② bundled adapter `_api_put` 缺 timeout 导致 `edit_message` 超时（`asyncio.TimeoutError` 的 `str()` 为空字符串，日志特征 `Stream send/edit error: ` 后面空白）→ ③ `_send_fallback_final` 缺 `reply_to` + `MAX_MESSAGE_LENGTH` 属性缺失（adapter 只有 `MAX_POST_LENGTH`，gateway `getattr` 回退到默认 4096 超出 MM 的 4000 限制）。新增 `references/gateway-stream-consumer-diagnostics.md` — 含完整因果链、调试指纹、上游 Bug 清单、插件侧修复方案。
- **v3.33.0** (2026-05-27): **P57 跨 Thread 串台诊断**。真实案例：Agent 回复落入错误 Thread。根因：Gateway 传入的 `event_message_id` 指向其他 channel 的帖子，`_resolve_root_id` 成功但返回了不同 channel 的 root_id。防御方案：`send()` 中增加 channel_id 归属校验（验证 root_id 所属 channel 匹配当前 chat_id）。新增 `references/cross-thread-reply-defense.md`。更新 P2/P55 串台根因列表——补充 `require_mention` 假阳性导致消息静默跳过这一原因。
- **v3.32.0** (2026-05-27): **P51 参考文档修正 + 兼容性审计清单**。① `references/mattermost-message-truncation.md` 修正：P51 从未注册到 `hermes-patches.sh`（旧文档声称「已注册」有误），更新文件路径为 v0.14.0 bundled plugin 位置，标注当前状态为「未修复」并提供两种修复方案。② 新增 `references/plugin-compatibility-audit.md` — Hermes 升级后 enhancer 插件逐方法兼容性审计清单（含检查步骤、方法对照表、注册表验证、已知 Gap 追踪）。SKILL.md 添加交叉引用。
- **v3.31.0** (2026-05-27): **P1/P2/P4/P5 修复完成 + Patch 管理原则**。① P1（P54）`apply_yaml_config_fn` 丢失 — enhancer `__init__.py` 显式导入并传递。② P2（P55）`hermes-mattermost-enhancer.sh` Patch 2 **完全移除**（上游已修复）——用户明确指令：上游修了就删掉，不要搞兼容层。提炼为原则 §Patch 管理。③ P4（P53）幽灵代码围栏 — `ba...
- **v3.30.0** (2026-05-27): **P56（日志误删恢复）**。App Cleaner 等清理工具可能将 `~/.hermes/logs/` 误删至废纸篓。运行中的 Gateway 进程文件描述符仍指向 Trash 中的原文件，日志持续写入但路径不可访问。诊断：`lsof -p <pid> | grep log` 可定位文件位置，但 macOS TCC 限制阻止路径读取。恢复：重启 Gateway → 日志恢复写入 `~/.hermes/logs/` 正常路径。预防：将 Hermes 加入 App Cleaner 的 Settings → Skip List。清理 P54/P55 重复条目。
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

## Patch 管理原则

**上游修复 → 直接删除，不要兼容层。** 当 Hermes 上游合入了某个修复后，本地 patch 脚本中的对应条目应立即删除（函数体 + apply 调用 + status check + header 注释），而不是改为"检测新版本 → 跳过"的兼容模式。用户明确反馈：多余的兼容代码增加维护负担，且阻碍对"未修复"状态的准确判断。

**⚠️ 删除本地 patch 前必须验证上游修复的完整语义。** 不能仅凭 changelog 声明或上游 commit message 就删除本地 patch。**血泪教训（P57）**：commit `73439a4` 看到 v0.14.0 changelog 写"fixed Mattermost progress thread routing"就删除了 Patch 2，但上游修复保留了 `source.thread_id` 条件——当用户在 Channel 根级别发消息时 `source.thread_id` 为 None，导致 `_progress_reply_to` 仍为 None，工具进度消息依然不进 Thread。**验证方法**：删除 patch 前至少做一次端到端测试，或在源码中确认上游修复的条件分支覆盖了所有本地 patch 覆盖的场景。

**新增 patch 必须同步注册表。** `hermes-patches.sh` 的 `_patch_registry` 是 check/apply 的单一数据源，新增任何 patch 都必须同时添加注册表条目（`file_rel|label|check_grep_pattern`）。

- **P54/P55/P56/P57 编号已归入各自 reference 文档。** `mattermost-operations` 的 Pitfall 编号与插件 reference 文档一一对应，避免跨文档重复。P55/P56 已提交上游 [PR #33335](https://github.com/NousResearch/hermes-agent/pull/33335)。P57 已注册 `hermes-patches.sh` + `hermes-mattermost-enhancer.sh` Patch 2，待提交上游。

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

**`mattermost.py` 源码已零修改**——**v0.14.0 起 Mattermost 适配器已从 `gateway/platforms/mattermost.py` 迁移至 bundled plugin `hermes-agent/plugins/platforms/mattermost/`，由插件系统自动加载为 `hermes_plugins.platforms_mattermost`**。enhancer v2.2.1 已适配新导入路径。所有自定义逻辑均由插件接管。

详见 [references/hermes-v0.14-migration-audit.md](references/hermes-v0.14-migration-audit.md) — v0.14.0 迁移完整兼容性矩阵、6 个问题清单（含 P54/P55）、修复方案。

详见 [references/slash-command-architecture.md](references/slash-command-architecture.md)（含 30+ 已知 Pitfall）。
参见 [references/plugin-migration-patterns.md](references/plugin-migration-patterns.md) — 源码 patch → 插件迁移的模式与陷阱。
参见 [references/thread-routing-metadata-fallback.md](references/thread-routing-metadata-fallback.md) — P36：并发 Thread 串台的根因、日志追踪与修复代码。
参见 [references/gateway-restart-session-loss.md](references/gateway-restart-session-loss.md) — P39：网关重启导致会话历史丢失，用户感知为「串台」的诊断与区分。
参见 [references/clarify-session-collision.md](references/clarify-session-collision.md) — P46：clarify 阻塞等待时 Gateway 双路由导致 Session 分裂，用户体感「突然失忆」的诊断与规避。
参见 [references/media-thread-routing-bug.md](references/media-thread-routing-bug.md) — P61：bundled adapter `send_multiple_images`/`send_image`/`send_video` 忽略 `metadata.thread_id`，图片/视频永远不进 Thread 的完整调用链与修复方案。上游 PR [#33391](https://github.com/NousResearch/hermes-agent/pull/33391) 已提交。
参见 [references/gateway-auto-resume-cross-talk.md](references/gateway-auto-resume-cross-talk.md) — P62：Gateway 重启后 auto-resume 所有 `restart_interrupted` session 导致跨 Thread 串台的根因分析、日志特征与修复方向。
参见 [references/plugin-compatibility-audit.md](references/plugin-compatibility-audit.md) — Hermes 版本升级后 enhancer 插件兼容性审计清单
参见 [references/ghost-code-fence-content-loss.md](references/ghost-code-fence-content-loss.md) — P53：幽灵代码围栏导致消息内容消失的根因、诊断方法及规避方案。
参见 [references/cross-thread-reply-defense.md](references/cross-thread-reply-defense.md) — P57：跨 Thread 串台（reply_to 指向错误 channel 的 root_id）的根因分析与 channel_id 校验防御方案。
参见 [references/gateway-stream-consumer-diagnostics.md](references/gateway-stream-consumer-diagnostics.md) — P58/P59/P60：Stream Consumer 消息丢失与截断的三层因果链、`asyncio.TimeoutError` 空字符串调试指纹、`_api_put` 缺 timeout、`_send_fallback_final` 缺 `reply_to`、`MAX_MESSAGE_LENGTH` 属性缺失。
参见 [references/gateway-sigterm-midstream-truncation.md](references/gateway-sigterm-midstream-truncation.md) — Gateway SIGTERM 打断流式输出导致消息截断的诊断：SIGTERM 时间线对比、排除插件路由 Bug（验证 enhancer send() resolved_root）、session 持久化检查、与 P39 的区别。
参见 [references/empty-response-fallback-diagnosis.md](references/empty-response-fallback-diagnosis.md) — P49：Empty Response → fallback_prior_turn_content 的根因、日志特征、诊断命令与模型自诊螺旋应对。
参见 [references/runtime-footer-inline.md](references/runtime-footer-inline.md) — Runtime Footer 流式模式独立消息的根因、双路径分析、插件拦截编辑方案。
参见 [references/platform-register-override-pitfall.md](references/platform-register-override-pitfall.md) — P54：Platform 覆盖丢失 `apply_yaml_config_fn` 的根因、影响范围、修复方案和通用检查清单。
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
- **跨 Thread 串台——reply_to 指向错误 channel**（P57）：`_resolve_root_id` 成功返回 root_id，但该 root_id 属于不同 channel。Gateway 传入的 `event_message_id` 在 WS 断线重连或 session 路由错位时可能指向错误 Thread 的帖子。防御：`send()` 中校验 `root_post.channel_id == chat_id`，不匹配则拒绝使用该 root_id。详见 [references/cross-thread-reply-defense.md](references/cross-thread-reply-defense.md)
- **审批通知路由丢失**（P37）：send_exec_approval 收到 metadata（含 thread_id），但调用 self.send() 发提示时未传递 metadata。导致 Thread 模式下提示落到频道级，CRT 用户看不到，审批超时卡死。修复：self.send() 传入 metadata=metadata。_send_local_file / _send_url_as_file 同源但缺 metadata 入参。
- **Thread 根帖进度消息落到频道**（P38）：非插件 Bug，Gateway mattermost.py。Thread 根帖 WebSocket 事件中 root_id 为空字符串，or None 将其转为 None。导致 source.thread_id 为空，所有 Still working 等进度通知消息失去 Thread 上下文，落到频道。修复：CRT 模式下 root_id 为空时用 post_id 兜底。hermes-patches.sh 已注册 patch #11。详见 references/thread-root-post-id-fix.md
- **网关重启导致会话丢失**（P39）：非插件 Bug。Gateway 重启后，内存中的 conversation history 丢失。下一次用户在同一 Thread 发消息时 session 命中但 `history=0`，Agent 不记得之前的对话。用户体感为「串台」。诊断：对照 `gateway.run: Gateway running` 重启时间与下一次 `conversation turn` 的 `history=N`。若 N=0 且对话间隔跨重启，则是会话丢失。详见 references/gateway-restart-session-loss.md
- **Clarify 阻塞 + Session 分裂**（P46）：非插件 Bug，Gateway 双路由。`clarify` 等待时用户回复被同时传给 clarify 和新 Session，导致同一 Thread 两个 Session 并行。**已修复**：`gateway/run.py` 两层防御（`_handle_message` canonical key fallback + `_handle_message_with_agent` 二次拦截），已注册 `hermes-patches.sh`，已提交[上游 PR](https://github.com/NousResearch/hermes-agent/pull/30669)。`source.thread_id` 守卫已应用，修复了 Telegram topic mode CI 回归。**加剧因素**：Mattermost 适配器不渲染 clarify 交互卡片 → 用户看不到提问 → 更容易触发 P46。**插件侧修复**：`send_clarify()` 覆写渲染为 MM interactive card button。详见 [references/clarify-session-collision.md](references/clarify-session-collision.md)。**归属决策**：P46/P46b 是通用 Gateway bug（非 Mattermost 专属），保留在全局 `hermes-patches.sh`；同时纳入插件脚本（面向没有全局脚本的第三方 Mattermost 用户），详见 [references/patch-plugin-boundary.md](references/patch-plugin-boundary.md)。
- **Clarify 交互卡片 Mattermost 不渲染**（P47）：与 P46 连锁效应。按钮 action_id 含特殊字符（`_`、`-`）时回调报「找不到该页面」——修复为纯字母数字（Pitfall 47，见 [references/slash-command-architecture.md](references/slash-command-architecture.md)）
- **asyncio 并发回调竞态 — 双击审批按钮**（P48）：`asyncio.start_server` 独立协程处理每个连接，用户快速双击时两个请求同时进入回调处理器。修复：按 `session_key` 使用 `asyncio.Lock` 串行化审批处理，并发请求返回即时「⏳ 处理中」update + 清空按钮（Pitfall 48，见 [references/slash-command-architecture.md](references/slash-command-architecture.md)）
- **MAX_POST_LENGTH = 4000 导致消息截断**（P51）：bundled plugin `hermes-agent/plugins/platforms/mattermost/adapter.py` 硬编码 4000 字符上限（OpenClaw 遗留值），长消息被拆分为多条帖子后在 CRT Thread 中折叠，用户看不到后续内容。Mattermost 服务器实际支持 16383。修复：在 enhancer `adapter.py` 中覆盖 `MAX_POST_LENGTH = 16000`。详见 [references/mattermost-message-truncation.md](references/mattermost-message-truncation.md)
- **图片/视频/文件 Thread 路由丢失**（P61）：bundled adapter 的 `send_multiple_images()` 接收 `metadata` 但 payload 中无 `root_id`——图片/视频永远发到频道。`send_image()`/`send_video()`/`send_document()` 同理（接收 metadata 但只传 `reply_to=None` 给 `_send_local_file`）。对比：文本 `send()`（enhancer 覆写）已正确处理 metadata fallback。修复：覆写 4 个方法提取 `metadata.thread_id`。上游 [PR #33391](https://github.com/NousResearch/hermes-agent/pull/33391) 已提交修复 bundled `send_multiple_images()`。详见 [references/media-thread-routing-bug.md](references/media-thread-routing-bug.md)
- **Gateway 重启后 auto-resume 多 session 串台**（P62）：`_schedule_resume_pending_sessions()` 未做同 channel 去重，Gateway 重启后所有 `restart_interrupted` session 同时 auto-resume，历史残留 session 的回复落入当前 Thread。日志特征：`scheduled > marked` + `msg=''` 空消息涌入。**已修复**：按 `(platform, chat_id)` 仅 auto-resume 最新 session，上游 [PR #33406](https://github.com/NousResearch/hermes-agent/pull/33406)，`hermes-patches.sh` P58。详见 [references/gateway-auto-resume-cross-talk.md](references/gateway-auto-resume-cross-talk.md)
- **⚠️ 关联**（P53）：截断后的代码块 carry-over 可能产生幽灵围栏吞掉后续内容。详见 [references/ghost-code-fence-content-loss.md](references/ghost-code-fence-content-loss.md)
- **iPad 端表格压缩**：`.table-responsive` 缺少 overflow CSS + `.post-message` 的 `overflow: clip` 在 iOS Safari 更激进 + `table-layout: fixed` 级联约束。详见 [references/ipad-table-rendering.md](references/ipad-table-rendering.md)
- **Platform 覆盖丢失 `apply_yaml_config_fn`**（P1/P54）：自定义插件 `register_platform()` last-writer-wins 替换 bundled `PlatformEntry`，包括 `apply_yaml_config_fn` hook → `config.yaml` 中 `mattermost:` 下所有配置（`require_mention` / `free_response_channels` / `allowed_channels`）全部失效。**诊断**：`env | grep MATTERMOST_REQUIRE` 为空即命中。**已修复**：enhancer `__init__.py` 显式导入并传递 `apply_yaml_config_fn=_apply_yaml_config`。详见 [references/platform-register-override-pitfall.md](references/platform-register-override-pitfall.md)
- **hermes-mattermost-enhancer.sh Patch 2 已恢复**（P2/P57）：v0.14.0 上游"修复"了 progress thread 路由，但保留了 `source.thread_id` 条件——当用户在 Channel 根级别发消息时 `source.thread_id` 为 None（Thread 是 Hermes 回复后才创建的），`_progress_reply_to` 仍为 None，工具进度消息不进 Thread。正确修复：对 Mattermost 不要求 `source.thread_id`，只要求 `event_message_id`。`hermes-mattermost-enhancer.sh` Patch 2（`patch_progress_thread`）已恢复，`hermes-patches.sh` 注册为 P57。详见 [references/hermes-patch-lifecycle.md](references/hermes-patch-lifecycle.md)
- **WebSocket 心跳优化**（P6/P54）：~~原 shell patch 已移除~~，改为 enhancer adapter 覆写 `_ws_connect_and_listen(heartbeat=15.0)`。shell 脚本 check 改为验证 adapter 覆写存在。
- **`_api_put` 缺 timeout**（P8/P56）：~~原 shell patch 已移除~~，enhancer adapter 已完整覆写 `edit_message`（自带 30s timeout + 分类异常处理），不走上游 `_api_put`。shell 脚本 check 改为验证 adapter 覆写存在。
- **幽灵代码围栏**（P4/P53）：`base.py` truncate_message 修复已应用，注册为 `hermes-patches.sh` P53。详见 [references/ghost-code-fence-content-loss.md](references/ghost-code-fence-content-loss.md)（已更新修复方案）
- **Empty Response → fallback_prior_turn_content**（P49）：LLM 在大量 tool calls 后返回空文本，turn 以 `fallback_prior_turn_content` 结束，用户仅收到 39 字符的截断片段。详见 [references/empty-response-fallback-diagnosis.md](references/empty-response-fallback-diagnosis.md)
- **Runtime Footer 编辑合并**：插件在 `send()` 中拦截独立的 footer 消息，通过 `PUT /posts/{id}` 编辑上一条消息追加为脚注。详见 [references/footer-edit-merge.md](references/footer-edit-merge.md)
- **日志误删恢复**（P56）：App Cleaner 等工具将 `~/.hermes/logs/` 误删后，运行中的 Gateway 进程文件描述符仍指向 Trash 中的原文件 → `lsof -p <pid> | grep log` 可定位，但路径访问被拒绝 → 重启 Gateway 后日志恢复写入正常路径。预防：将 Hermes 加入 App Cleaner 的 Skip List
- **Gateway Stream Consumer 消息丢失与截断**（P58/P59/P60）：三层因果链——① WebSocket 每 30 秒断连（**根因：Bot 经 Cloudflare 代理连接，CF WebSocket 超时。修复：`MATTERMOST_URL` 改为 `http://localhost:8065` 直连，验证零断连**）② bundled adapter `_api_put` 缺 timeout → `edit_message` 超时 → Stream fallback（`asyncio.TimeoutError` 的 `str()` 为空字符串，日志特征 `Stream send/edit error: ` 后面空白。**修复：覆写 `edit_message` 添加 30s timeout + 分类错误消息**）③ `_send_fallback_final` 缺 `reply_to` + `MAX_MESSAGE_LENGTH` 属性缺失（adapter 只有 `MAX_POST_LENGTH`，gateway `getattr` 回退到默认 4096 超出 MM 的 4000 限制。**修复：添加 `MAX_MESSAGE_LENGTH` + 缓存 `_resolve_root_id` + Footer 编辑改用 `edit_message`**）。commit d185642。**上游 PR [#33335](https://github.com/NousResearch/hermes-agent/pull/33335)** 已提交 P55（`_send_fallback_final` 缺 `reply_to`）+ P56（`_api_put` 缺 timeout）。**调试指纹**：`Stream send/edit error: ` 后面空白 = `asyncio.TimeoutError`。详见 [references/gateway-stream-consumer-diagnostics.md](references/gateway-stream-consumer-diagnostics.md)
- **工具进度消息不进 Thread（上游"修复"不完整导致回退）**（P57）：v0.14.0 上游在 `_progress_reply_to` 中添加了 `Platform.MATTERMOST`，但保留了 `source.thread_id` 条件。当用户在 Channel 根级别发消息时 `source.thread_id` 为 None（Thread 是 Hermes 回复后才创建的），导致 `_progress_reply_to = None`，工具进度消息不会路由进 Thread。正确逻辑：对 Mattermost 只要求 `event_message_id`，不要求 `source.thread_id`，因为 adapter 内部的 `_resolve_root_id` + metadata fallback 会处理 Thread 路由。**根因**：commit `73439a4` 仅凭 changelog 声明就删除了本地 Patch 2，未验证上游修复的完整语义。修复：恢复 Patch 2（`patch_progress_thread`），`hermes-patches.sh` 注册为 P57。

卡片更新机制关键规则：`{"update": {"message": "...", "props": card}}` 会导致 MM 同时渲染 message 正文和 props.attachments，必须避免内容重叠。select 下拉列表选择后卡片被 update 替换（无按钮），用户需重新 `/model` 获取新卡片。详见 [references/slash-command-architecture.md](references/slash-command-architecture.md)。

## 网络问题

### WebSocket 稳定性（Cloudflare 反向代理陷阱）

**Bot 和 Mattermost 在同一主机时，必须用 `localhost` 直连，不要走 Cloudflare。** `MATTERMOST_URL` 配置项决定了 Bot 的 WebSocket 和 API 连接目标。如果设为经 Cloudflare 代理的域名（如 `https://mm.example.com`），Cloudflare 的 WebSocket 超时会导致连接每 30 秒断连（close code 258），引发一连串问题：`edit_message` 超时 → Stream fallback → Thread 路由丢失 → 消息截断。

**快速诊断**：
```bash
# 检查是否经 Cloudflare
curl -sI https://<your-domain> | grep -i "server\|cf-ray"
# server: cloudflare = 走 CF ❌

# 检查本地可达性
curl -s http://localhost:8065/api/v4/system/ping
# {"status":"OK"} = 可直连 ✅

# 检查 Bot 连接目标
grep "connecting to w" ~/.hermes/logs/gateway.log | tail -3
# ws://localhost = 直连 ✅ | wss://domain = 走 CF ❌
```

**修复**：在 `.env` 中将 `MATTERMOST_URL=https://mm.example.com` 改为 `MATTERMOST_URL=http://localhost:8065`，然后重启 Gateway。

Mattermost 容器访问外网可能受 GFW 影响。解决方案：
1. 容器配 `HTTP_PROXY` / `HTTPS_PROXY` 环境变量
2. 搬至蒙特利尔后自然解决

## 桌面客户端已知问题

### Server URL 编辑后静默回退

Mattermost Desktop（macOS）编辑已有 server 的 URL 时，保存后重新打开会恢复为旧 URL。根因是弹窗预填充 URL 时读取 tab 的 webContents origin 而非本地存储。绕过方案：删除旧 server → 新建，不要编辑。详见 [references/desktop-client-url-revert.md](references/desktop-client-url-revert.md)。

## 插件配套脚本完整性验证

`hermes-mattermost-enhancer.sh` 和 `hermes-patches.sh` 必须**同步覆盖所有 Mattermost 关键 patch**。第三方用户只有插件脚本，没有全局脚本，所以插件脚本遗漏 = 第三方用户功能缺失。

**当前覆盖（7 项源码 patch + 2 项 adapter 覆写检查 = 9/9）**：

| # | 文件 | 功能 | 归属 | 分类 |
|---|------|------|------|------|
| P1 | run.py | DM 审批传入 user_id | 双归属 | 🟡 可选（插件有降级） |
| P2 | run.py | 工具进度消息进 Thread（上游修复不完整） | 双归属 | 🔴 必须源码 |
| P3 | run.py | Clarify Session 分裂修复 | 双归属 | 🔴 必须源码 |
| P4 | run.py | Clarify 并发守护 | 双归属 | 🔴 必须源码 |
| P5 | stream_consumer.py | 评论→正文合并 | 双归属 | 🔴 必须源码 |
| P7 | stream_consumer.py | stream fallback 丢失 reply_to | 双归属 | 🔴 必须源码 |
| P9 | base.py | 幽灵代码围栏修复 | 双归属 | 🟡 保留 patch |
| A1 | adapter.py | WebSocket 心跳 30→15s | 插件覆写 | 🟢 adapter override |
| A2 | adapter.py | edit_message 30s timeout | 插件覆写 | 🟢 adapter override |

> P6/P8 已从 shell patch 移除，改由 enhancer adapter 方法覆写实现（`_ws_connect_and_listen` + `edit_message`）。

**验证流程（模拟全新安装）**：
```bash
cd ~/.hermes/hermes-agent
git stash --include-untracked      # 还原原始上游代码
echo "n" | bash ~/.hermes/plugins/mattermost-enhancer/scripts/hermes-mattermost-enhancer.sh apply
bash ~/.hermes/plugins/mattermost-enhancer/scripts/hermes-mattermost-enhancer.sh check
# 期望：9/9 passed（7 源码 patch + 2 adapter 覆写检查）
git checkout -- . && git stash pop  # 恢复本地完整 patch 状态
```

**每次新增/删除 patch 后必须运行此验证**，确保全新安装场景下脚本功能完整。

### Patch 可消除性审查

新增 Mattermost patch 前，必须先回答三个问题：

1. **能否通过覆写 adapter 方法实现？** — 如果修改的是 `BasePlatformAdapter` 的方法（如 `send()`, `edit_message()`, `_ws_connect_and_listen()`），可以在 enhancer 中覆写，不需要 patch。**但要注意方法体量**：`truncate_message` 有 130+ 行复杂逻辑，覆写意味着复制整段上游代码并维护同步，代价远大于 patch。
2. **能否通过 `pre_gateway_dispatch` hook 实现？** — 如果逻辑可以用 `{"action": "skip"}` 表达（拦截消息），可走 hook。但 hook 无法修改 gateway 内部变量或表达「已消费」语义。
3. **是否修改 gateway 调用方代码？** — 如果修改的是 `run.py` 中传给 adapter 的参数（如 `reply_to`, `metadata`, `user_id`）或 `StreamConsumer` 内部逻辑，则**必须保留源码 patch**。

**覆写 vs Patch 决策规则**：方法体 < 30 行 → 优先覆写；方法体 > 100 行 → 优先 patch（维护成本差异显著）。

详见 `references/patch-plugin-boundary.md` — Patch 可消除性审查节。

## 插件 Release 工作流

`hermes-plugin-mattermost-enhancer` 使用 GitHub Actions `release.yml`（`workflow_dispatch`）发布新版本：

```bash
# 1. 推送代码
cd ~/.hermes/plugins/mattermost-enhancer && git push origin main

# 2. 触发 Release workflow（版本号 + Release Notes）
gh workflow run release.yml \
  --repo colin-chang/hermes-plugin-mattermost-enhancer \
  -f version=v2.3.0 \
  -f notes="$(cat <<'EOF'
## v2.3.0 — 修复摘要

1. 修复 A ...
2. 修复 B ...
EOF
)"

# 3. 检查运行结果
gh run list --repo colin-chang/hermes-plugin-mattermost-enhancer --limit 1
```

Workflow 自动完成：版本号写入 `plugin.yaml` → commit + tag → 创建 GitHub Release（含自动生成的 commit log）。

**版本号规则**：根据语义化版本选择 MAJOR/MINOR/PATCH。修复 bug → PATCH，新功能 → MINOR，破坏性变更 → MAJOR。

**Release Notes 最佳实践**：详尽描述每个修复的根因、影响面和修复方式，方便将来排查和追踪。不要只写"修复了 XX 问题"。

## Hermes Cron 定时任务排障

[references/hermes-cron-pitfalls.md](references/hermes-cron-pitfalls.md) — Cron 子代理工具不可用、安检误判、Skill ZWJ 拦截、iMessage 发送模板等已知陷阱 P40-P44。

## 开发技巧

对 `hermes-patches.sh` 等 shell 脚本做大规模修改时的工具选择陷阱：
[references/patch-tool-pitfalls.md](references/patch-tool-pitfalls.md) — `patch` 工具在 heredoc / f-string 上的已知问题及 `execute_code` 替代方案。
[references/hermes-patches-conventions.md](references/hermes-patches-conventions.md) — `hermes-patches.sh` 编写规范：注册表约定、check_grep 选型、`_do_patch` 必须在函数体内、同文件多补丁注册表一一对应。
