🔀 OpenClaw→Hermes 迁移完成。1 Profile + 5角色Skill。角色: 技术顾问(deepseek-v4-pro)/加拿大事务(claude-sonnet-4.6)/自媒体运营(doubao-seed-2.0-pro)/育儿专家(claude-sonnet-4.6)/投资顾问(claude-sonnet-4.6)。记忆三层: 全局MEMORY.md + 角色role-memory.md + user-context.md。QMD RAG已配置(97文档)。移民日报cron绑定role-canada-affairs+claude-sonnet-4.6。
§
Mattermost 插件 mattermost-enhancer v2.0.0 已完成并推送GitHub(colin-chang/mattermost-enhancer)。插件覆盖全部 mattermost.py patch(6/_resolve_root_id, 7/DM审批, 10c/MEDIA静默跳过, 11/send_typing)，31个方法~1180行。源码已回滚至a91a57fa5(852行零修改)。hermes-patches.sh 12 patches(原16)，标签已改为用户友好中文描述(如"自定义provider被误判为非聚合器")。剩余2个run.py patch(8/8b)无法插件化(调用方层面)，需提PR或.pth注入。
§
IM平台评估结论：Discord不合适(Markdown碎片化)，Mattermost最接近理想(GFM完整+全平台客户端+自托管)，Telegram缺表格/标题/列表。细节见hermes-agent skill→references/im-platform-comparison.md。Mattermost已部署验证中(2026-05-20+)。
§
iMessage发送规则：用户要求通过iMessage发送内容给老婆时，必须先在当前频道中显示完整内容，再发送iMessage。严禁只发iMessage而频道中无输出（用户无法看到自己没发出的内容）。发送后应在频道中简短确认"已发送✅"。
§
URL Safety误拦截已修复(2026-05-20)：config.yaml根节点加 security.allow_private_urls: true。zenmux.ai/developer.apple.com/swiftsenpai.com已放行，169.254.169.254仍硬编码拦截。无需改源码白名单。MM审批13个Pitfall要点见hermes-agent skill→references/mattermost-approval-workflow.md。
§
iMessage skill 优先级(2026-05-19)：builtin `imessage` 禁止加载。所有 iMessage 发送用 `imessage-nomad`（custom/imessage-nomad v3.2.0）。加载：/skill imessage-nomad。bridge 脚本在 skill 内：~/.hermes/skills/custom/imessage-nomad/references/imsg-bridge.command。发送：Python socket → 127.0.0.1:8899 JSON-RPC。前置：brew install socat + Terminal.app FDA。
§
自定义Skill创建规则(2026-05-19)：所有用户自定义 Skill 统一放在 ~/.hermes/skills/custom/。创建时 skill_manage 必须加 category='custom'。存量的 Skill 已全部迁移到 custom/。gitignore 已配置为整目录追踪 custom/、忽略其他分类目录。
§
MM Slash Command payload 原生包含 root_id 字段（2026-05-21 实测确认）：Thread 中 root_id=root_post_id，Channel 顶层 root_id=空字符串。之前文档错误声称"不含 root_id"导致实现了一整套 API 反查 + asyncio.sleep 延迟方案，全部不必要。直接 params.get("root_id","") or None 即可。
§
文档写作规范(2026-05-28)：面向小白用户说人话、举场景、标截图位。功能用「痛点→改善」格式，Bug拆表（描述+影响+修复）。架构用比喻不用技术图。编辑流程：先改中文版(README.zh-CN.md)等定稿再同步英文。脚本输出双语格式：英语为主第一行，中文放括号或缩进下一行。禁止技术术语(patch/已应用/未应用/聚合器/vendor-prefix/桥接/转义符等)。详见mattermost-operations skill→references/plugin-packaging-conventions.md。