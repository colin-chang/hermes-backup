🔀 OpenClaw→Hermes 迁移 — 已完成。1 Profile + 5角色Skill。角色：技术顾问(deepseek-v4-pro)/加拿大事务(claude-sonnet-4.6)/自媒体运营(doubao-seed-2.0-pro)/育儿专家(claude-sonnet-4.6)/投资顾问(claude-sonnet-4.6)。切换：/skill+自然语言+自动识别。记忆三层：全局MEMORY.md(1.4K/2.2K)+角色role-memory.md+user-context.md。QMD RAG已配置(97文档)。移民日报cron已绑定role-canada-affairs+claude-sonnet-4.6。迁移文档：hermes-agent/references/openclaw-agent-migration.md + qmd-obsidian-rag.md
§
IM平台评估(2026-05-18)：Discord渲染碎片化严重(2000字符溢出+工具进度+commentary)，Mattermost被识别为最接近理想的替代平台(GFM完整Markdown/16384字符/全平台原生客户端/自托管)。Telegram MarkdownV2缺表格+标题+列表不适合AI长内容。Hermes WebUI响应式但iPad需浏览器(无原生App)。平台对比详情见hermes-agent skill→references/im-platform-comparison.md。待决策：是否部署Mattermost验证。
§
升级恢复：~/.hermes/scripts/hermes-patches.sh（17 patches：15 hermes-agent + 1 WebUI + 1 send_typing）。已支持 WEBUI: 前缀路径（_do_patch_webui 函数）。WebUI 补丁 #11：api/config.py custom_providers models 白名单优先于 /v1/models live fetch。
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