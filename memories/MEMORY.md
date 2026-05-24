OpenClaw→Hermes迁移完成。5角色Skill。移民日报cron: role-canada-affairs+doubao-seed-2.0-pro。
§
Mattermost 插件 mattermost-enhancer v2.1.0(colin-chang/mattermost-enhancer)。出站覆盖: _resolve_root_id,DM审批,MEDIA静默跳过,send_typing,footer编辑合并(流式模式下PUT编辑上条消息,实现脚注同消息显示:`── model 34% ──`)。P38(Thread root_id+)不可迁入插件,保持source patch。hermes-patches.sh 11 patches。
§
iMessage规则：(1) 发老婆前先在频道显示内容，再发，事后确认"已发送✅"。(2) 只用custom/nomad-imessage，禁止builtin。(3) bridge: Python socket→127.0.0.1:8899 JSON-RPC。前置: socat+Terminal FDA。(4) 不提AI，以本人(老公)口吻。
§
URL Safety误拦截已修复(2026-05-20)：config.yaml根节点加 security.allow_private_urls: true。
§
自定义Skill创建规则(2026-05-19)：所有用户自定义 Skill 统一放在 ~/.hermes/skills/custom/。创建时 skill_manage 必须加 category='custom'。存量的 Skill 已全部迁移到 custom/。gitignore 已配置为整目录追踪 custom/、忽略其他分类目录。
§
MM Slash Command payload 原生包含 root_id 字段（2026-05-21 实测确认）：Thread 中 root_id=root_post_id，Channel 顶层 root_id=空字符串。之前文档错误声称"不含 root_id"导致实现了一整套 API 反查 + asyncio.sleep 延迟方案，全部不必要。直接 params.get("root_id","") or None 即可。
§
文档写作规范(2026-05-28)：面向小白用户说人话、举场景、标截图位。功能用「痛点→改善」格式，Bug拆表（描述+影响+修复）。架构用比喻不用技术图。编辑流程：先改中文版(README.zh-CN.md)等定稿再同步英文。脚本输出双语格式：英语为主第一行，中文放括号或缩进下一行。禁止技术术语(patch/已应用/未应用/聚合器/vendor-prefix/桥接/转义符等)。详见mattermost-operations skill→references/plugin-packaging-conventions.md。
§
修复未完成时严禁自动触发cron job，必须等用户明确要求才能触发。"不要总他妈的自动去触发，我没有要求你触发的情况下，你就不要触发"
§
nomad-imessage v4.0.0 开源发布：github.com/colin-chang/nomad-imessage-skill (MIT)。通用 macOS Agent Skill（socat+imsg JSON-RPC bridge），兼容 Hermes/Claude Code/OpenCode/Codex。Hermes特化内容归档至references/hermes/。LaunchAgent label: com.a-nomad.imsg-bridge。双语README+SECURITY+PRIVACY全套合规文档。
§
Vertex Monitor 项目: /Users/Colin/Developer/Services/VertexMonitor — Vertex AI Gemini 预算代理。liteLLM SDK计费+FastAPI薄代理+Web UI仪表盘。双模式计费(手动余额/自动循环月重置)。Docker compose部署:8899,数据卷./data/。接入Hermes: custom_providers→vertex-budget。用户Google AI Pro会员月赠$10 Vertex AI额度。conda环境:vertex-monitor。
§
配置/文档中 YAML 代码块一律使用 block style：`key:\n  subkey: value`，禁止 inline flow `{ subkey: value }`。用户 config.yaml 用 block style，教程/README/Skill 示例必须匹配。此项适用于 custom_providers.models 及所有面向用户的 YAML 片段。