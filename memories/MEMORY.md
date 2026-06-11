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
§
模型兼容性：minimax/m3 不兼容 Hermes 工具调用（tool_turns=0），在 cron 任务和交互会话中均无法完成工具调用。doubao-seed-2.0-pro 和 deepseek-v4-pro 经验证可用。切换模型前建议先查 ~/.hermes/skills/custom/ 下相关 Skill 的 model_compatibility 参考。
§
阿飞口语31天课程（路径：/Volumes/Colin-Lexar/Courses/英语/免费课程/阿飞口语/）：纠音内容为中文讲解（口型/舌位），场景应用mp3为中文讲解+英文示范混合格式，均不能作为英语精听材料。仅用于发音训练。
§
欧路词典：不喜欢（网络不稳定/Bug多/国外几乎不可用），仅因已有大量词汇积累和笔记而继续使用其词典查询功能。对 Anki 持开放态度（作为软件开发人员学新工具无难度），偏好免费开源跨平台工具，至少支持苹果全生态。
§
Colin 主力模型商：ZenMux（custom:zenmux，base_url: https://zenmux.ai/api/v1），主模型 deepseek/deepseek-v4-pro。MiniMax M3 仅用于辅助任务（mcp/session_search/skills_hub）。Claude Code 通过 ZenMux Anthropic endpoint（https://zenmux.ai/api/anthropic）路由，API Key 存在 macOS Keychain（service: zenmux-api-key, account: colin）。GUI 应用环境变量注入偏好：launchctl setenv + ~/.zshrc 持久化模式。
§
串台防范：Colin 明确纠正过——Mattermost 收到的消息和 TUI 会话是完全独立的对话流，不要默认把 Mattermost 消息当作上一个 TUI 会话的延续。他问"什么结果/为什么没回复"时，先检查 Mattermost 当前线程的实际上下文，而不是去翻 TUI 历史。他用过"又串台了吧"表示这是重复问题。