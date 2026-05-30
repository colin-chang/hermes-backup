iMessage：用nomad-imessage（禁builtin），发前先预览再确认"已发送✅"，以本人口吻不提AI。
§
自定义Skill放 ~/.hermes/skills/custom/，category='custom'。开源模板：双语README+SECURITY+PRIVACY+LICENSE。
§
文档：面向小白说人话，功能用「痛点→改善」格式，Bug拆表。脚本双语输出（英语为主+中文括号）。禁技术术语（patch/聚合器/桥接/转义符等）。详见mattermost-operations skill。
§
YAML一律block style（`key:\n  subkey: value`），禁inline flow。适用于config.yaml/教程/Skill/README。
§
UI/UX或技术选型：先调研出评估报告 → 审阅 → 再动手改。不要直接实施未经审阅的变更。
§
iMessage bridge：已废弃 LaunchAgent（FDA链断裂）。bridge 路径：/Users/Colin/.hermes/skills/nomad-imessage/references/imsg-bridge.command。Cron prompt 已改为自包含 send 代码（内部 subprocess.run(['open', cmd_path]) 自动启动 bridge），不再依赖 LLM 分步执行 auto-start。