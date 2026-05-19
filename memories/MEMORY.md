🔀 OpenClaw→Hermes 迁移 — 已完成。1 Profile + 5角色Skill。角色：技术顾问(deepseek-v4-pro)/加拿大事务(claude-sonnet-4.6)/自媒体运营(doubao-seed-2.0-pro)/育儿专家(claude-sonnet-4.6)/投资顾问(claude-sonnet-4.6)。切换：/skill+自然语言+自动识别。记忆三层：全局MEMORY.md(1.4K/2.2K)+角色role-memory.md+user-context.md。QMD RAG已配置(97文档)。移民日报cron已绑定role-canada-affairs+claude-sonnet-4.6。迁移文档：hermes-agent/references/openclaw-agent-migration.md + qmd-obsidian-rag.md
§
IM平台评估(2026-05-18)：Discord渲染碎片化严重(2000字符溢出+工具进度+commentary)，Mattermost被识别为最接近理想的替代平台(GFM完整Markdown/16384字符/全平台原生客户端/自托管)。Telegram MarkdownV2缺表格+标题+列表不适合AI长内容。Hermes WebUI响应式但iPad需浏览器(无原生App)。平台对比详情见hermes-agent skill→references/im-platform-comparison.md。待决策：是否部署Mattermost验证。
§
Mattermost DM审批已打通(2026-05-19)：Bot API+DM模式(已验证完整闭环)，Webhook方案已移除。关键认知：StripActionIntegrations()只剥离API输出，DB保留→Bot API DM方案可行。env：MATTERMOST_CALLBACK_URL + MATTERMOST_CALLBACK_BIND + MATTERMOST_CALLBACK_PORT(18065)。_resolve_root_id()解决Invalid RootId。choice_map下划线格式(approve_once)。action id纯字母(approveonce)。升级恢复：~/.hermes/scripts/hermes-patches.sh（14 patches）。文档：~/.hermes/workspace/mattermost-dm-approval-plan.md v2.0
§
iMessage发送规则：用户要求通过iMessage发送内容给老婆时，必须先在当前频道中显示完整内容，再发送iMessage。严禁只发iMessage而频道中无输出（用户无法看到自己没发出的内容）。发送后应在频道中简短确认"已发送✅"。
§
MM审批13个Pitfall要点(2026-05-19)：1) integration被API剥离但DB保留，Bot API DM+props.attachments可行(Webhook备选用顶层attachments)；2) Action id纯字母(approveonce)；3) context.action下划线(approve_once)须与choice_map匹配；4) root_id须是thread根帖子→_resolve_root_id()向上遍历；5) Bot API用props.attachments/Webhook用顶层attachments(位置搞反则按钮消失)
§
iMessage skill 优先级(2026-05-19)：builtin `imessage` 禁止加载。所有 iMessage 发送用 `imessage-nomad`（custom/imessage-nomad v3.2.0）。加载：/skill imessage-nomad。bridge 脚本在 skill 内：~/.hermes/skills/custom/imessage-nomad/references/imsg-bridge.command。发送：Python socket → 127.0.0.1:8899 JSON-RPC。前置：brew install socat + Terminal.app FDA。
§
自定义Skill创建规则(2026-05-19)：所有用户自定义 Skill 统一放在 ~/.hermes/skills/custom/。创建时 skill_manage 必须加 category='custom'。存量的 Skill 已全部迁移到 custom/。gitignore 已配置为整目录追踪 custom/、忽略其他分类目录。