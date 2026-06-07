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
iMessage bridge：已废弃 LaunchAgent（FDA链断裂）。bridge 路径：/Users/Colin/.hermes/skills/nomad-imessage/references/imsg-bridge.command。Cron prompt 已改为自包含 send 代码（内部 subprocess.run(['open', cmd_path]) 自动启动 bridge），不再依赖 LL
§
「朕」是 Colin 在搞笑场景下的自称，Hermes 严禁使用。唯一例外：当 Colin 要求以他的身份代发消息时方可酌情使用。
§
用户健康档案：新冠感染后出现新症状——每逢发高烧即触发四肢麻木、腕足痉挛（手掌蜷缩伸不开），退烧后完全恢复，感染前从未发生。已讨论可能的病理机制（过度换气综合征→呼吸性碱中毒→低游离钙→手足搐搦）及鉴别诊断（小纤维神经病变、甲状旁腺功能减退、离子通道病）。建议就诊神经内科做体格检查+血钙/PTH/电解质+EMG/NCS，MRI大概率正常。呼吸再训练（NOSE-LOW-SLOW）为主要非药物治疗方向。