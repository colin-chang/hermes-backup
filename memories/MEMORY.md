OpenClaw→Hermes迁移完成。5角色Skill。移民日报cron: role-canada-affairs+doubao-seed-2.0-pro。
§
Mattermost 插件 mattermost-enhancer v2.0.0(colin-chang/mattermost-enhancer)。插件覆盖出站方法(6/_resolve_root_id,7/DM审批,10c/MEDIA静默跳过,11/send_typing),31方法~1180行。P38(Thread root_id空值+API反查)不可迁入插件(入站入口~200行),保持source patch。hermes-patches.sh 11 patches,P38增强版含API反查。P38最小修复已提PR upstream #30385。入站vs出站分类见mattermost-operations skill→references/patch-plugin-boundary.md。
§
IM平台评估结论：Discord不合适(Markdown碎片化)，Mattermost最接近理想(GFM完整+全平台客户端+自托管)，Telegram缺表格/标题/列表。细节见hermes-agent skill→references/im-platform-comparison.md。Mattermost已部署验证中(2026-05-20+)。
§
iMessage规则：(1) 发老婆前先在频道显示内容，再发，事后确认"已发送✅"。(2) 只用custom/imessage-nomad，禁止builtin。(3) bridge: Python socket→127.0.0.1:8899 JSON-RPC。前置: socat+Terminal FDA。(4) 不提AI，以本人(老公)口吻。
§
URL Safety误拦截已修复(2026-05-20)：config.yaml根节点加 security.allow_private_urls: true。zenmux.ai/developer.apple.com/swiftsenpai.com已放行，169.254.169.254仍硬编码拦截。无需改源码白名单。MM审批13个Pitfall要点见hermes-agent skill→references/mattermost-approval-workflow.md。
§
自定义Skill创建规则(2026-05-19)：所有用户自定义 Skill 统一放在 ~/.hermes/skills/custom/。创建时 skill_manage 必须加 category='custom'。存量的 Skill 已全部迁移到 custom/。gitignore 已配置为整目录追踪 custom/、忽略其他分类目录。
§
MM Slash Command payload 原生包含 root_id 字段（2026-05-21 实测确认）：Thread 中 root_id=root_post_id，Channel 顶层 root_id=空字符串。之前文档错误声称"不含 root_id"导致实现了一整套 API 反查 + asyncio.sleep 延迟方案，全部不必要。直接 params.get("root_id","") or None 即可。
§
文档写作规范(2026-05-28)：面向小白用户说人话、举场景、标截图位。功能用「痛点→改善」格式，Bug拆表（描述+影响+修复）。架构用比喻不用技术图。编辑流程：先改中文版(README.zh-CN.md)等定稿再同步英文。脚本输出双语格式：英语为主第一行，中文放括号或缩进下一行。禁止技术术语(patch/已应用/未应用/聚合器/vendor-prefix/桥接/转义符等)。详见mattermost-operations skill→references/plugin-packaging-conventions.md。
§
修复未完成时严禁自动触发cron job，必须等用户明确要求才能触发。"不要总他妈的自动去触发，我没有要求你触发的情况下，你就不要触发"