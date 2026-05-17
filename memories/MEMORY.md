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
**Hermes 生成插件:** ZenMux 图片+视频插件。GitHub：`colin-chang/hermes-plugin-zenmux-<image|video>`。视频插件用 google-genai SDK + Vertex AI Compatible API 异步轮询。**Veo 3.1 时长仅支持 [4,6,8]s**（已修 duration_range），标准版生成约 60-180s。
§
**Chrome CDP（2026-05-17）：** 脚本 `~/.hermes/scripts/browser-configure.sh [bb-browser|buildin-isolation|buildin-inspect]`。①`bb-browser`（★默认）daemon 管 Chrome + 拷 6 profile 文件 + **精简 Local State**（只保留 Default，同步 gaia 信息）+ **删除 `--use-mock-keychain`**（cli.js 硬编码，致 Chrome 用假 Keychain 无法解密 cookie → 必须删除，**更新后需重删**）。②`buildin-isolation` 拷 7 文件 + 写 `.env`；③`buildin-inspect` 不拷文件 + 写 `.env`。Cookie v10 加密绑定 macOS 用户账户。
§
用户对解决方案的审美偏好：**追求优雅、拒绝过度设计**。对于浏览器登录态保留问题，用户明确拒绝"将默认profile拷贝到另一个目录"这种方案（"感觉这种方式并不是非常优雅"），也拒绝为单一浏览器功能安装整套 OpenClaw（"显然是过度设计或者太重"）。这说明用户偏好：**轻量、自洽、内聚的解决方案**，而非堆叠工具链。
§
用户技术探索风格：**深度调研型**。用户要求在给出结论前做深度调研（"做一个深度调研，之后再给出结论"），不喜欢浅尝辄止或仅凭表面信息就给结论。涉及技术方案时会深入源码、竞品对比、安全机制原理，追求"知其然且知其所以然"。