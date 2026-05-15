🔭 探索路线图 (Exploration Roadmap): **Productivity:** Gmail 邮件摘要与处理。
§
🔭 探索路线图 (Exploration Roadmap): **Finance:** 金融市场实时行情与资产看板。
§
👤 用户偏好 (User Preferences): 统一使用 **Lark（飞书国际版）** 管理个人工作与生活事务，不使用国内版飞书。
§
📅 工具常识 (Tool Facts): **飞书/Lark 日历限制：** 全天日程 + 非全天日程**均不支持自定义提醒时间**，仅能选择官方预设的特定时间点，移动端/桌面端均无自定义选项。
§
User prefers a curated, filtered model list for custom providers in the Hermes model picker, rather than listing all models from the provider's API. For the 'custom:zenmux' provider, I implemented this by adding a 'models:' whitelist to config.yaml and patching Hermes code (model_switch.py, doctor.py) and the WebUI (ui.js) to recognize 'custom:*' providers as aggregators and suppress vendor-prefix mismatch warnings.
§
**Hermes 自定义聚合器补丁维护:** 用户在 `/Users/Colin/workspace/hermes-patches.sh` 维护一个补丁脚本，用于 hermes-agent 升级后重新应用 4 个 patch（providers.py is_aggregator、doctor.py vendor-prefix、model_switch.py §3 §4），使 `custom:zenmux` 等自定义聚合器提供商正常工作。每次 hermes-agent 升级后需运行 `./hermes-patches.sh apply`。