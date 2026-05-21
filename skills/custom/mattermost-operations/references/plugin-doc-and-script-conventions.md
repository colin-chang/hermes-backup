# 插件文档与脚本消息约定

> 适用于开源 Hermes 插件的 README 文档和配套 Shell 脚本的用户界面消息。
> 本参考面向外部用户，核心原则：**让小白用户看过文档之后知道这是个什么东西、要不要用、如何快速使用。**

## README 文档结构（面向小白用户）

### 1. 功能描述 — 用户视角 + 场景 + 截图位

每条功能遵循「问题 → 原来 → 现在」结构：

```markdown
### 🛡️ 1. 危险操作审批（私信卡片确认）

**场景：** 你让 Hermes 执行危险命令，不可逆。

**原来：** Hermes 二话不说就执行了 😱

**现在：** 私信你一张确认卡片，有 4 个按钮：
| Allow Once | Allow This Session | Always Allow | Deny |

> 📸 `[截图位]` — 私信中的审批卡片，展示 4 个按钮的界面
```

- 用大白话描述，拒绝技术名词
- 每个功能附 `[截图位]` 标记
- 回答两个问题：「这是什么？」和「为什么我需要它？」

### 2. Bug 修复 — 独立拆表

功能（Feature）和 Bug 修复分成两块。Bug 表格式：

| # | Bug 描述 | 造成的影响 | 修复后 |
|---|---------|-----------|--------|
| **1** | Thread 回复跑偏 | CRT 模式聊天混乱 | 回复正确出现在当前 Thread |

三列回答：「出了什么 Bug？」「对我有什么影响？」「修好之后什么样子？」

### 3. 插件 vs 配套脚本 — 大白话架构解释

面向小白解释 Hermes 工作原理：

```
你 → Mattermost → Hermes Gateway（机器人中枢）→ AI 大脑
                        │
                        ├── 插件：给机器人装新技能
                        └── 源码：机器人的"骨架"，改不了
```

说明插件能改什么（适配器）、不能改什么（调用方代码），配套脚本修的是什么。

### 4. 快速上手 — 步骤即可操作

- 优先使用 `hermes plugins install owner/repo --enable`（一行搞定，不推荐手动 clone + 改 config）
- 每步有明确的命令、输入/输出预期、注意事项
- 环境变量区分必填/可选，Docker 场景特别标注

### 5. 配套脚本 — 交互式体验

- 说明「什么时候需要运行」：首次安装 / 升级后 / 功能异常
- `apply` 完成后交互式询问重启，不在文档里单独写 `hermes gateway restart`
- 推荐流程：先 `check` → 2/2 已应用就跳过 → 未应用再 `apply` → 选择是否立即重启

## 脚本消息约定（双语中英）

### 格式规则

- 标题/分区头：英语一行 + 中文缩进下一行
  ```
  ── Check ①: Can approval cards reach your DMs? ──
     （审批卡片能不能发到你的私信）
  ```
- 单行结果：`English text（中文）`
  ```
  [OK]    Approval cards work ✅ (Hermes knows who to DM)（知道发给谁）
  ```

### 消息内容 — 禁止抽象术语

每条消息回答「在检查什么？」+「结果意味着什么？」：

| 旧（技术术语） | 新（大白话） |
|-------------|-----------|
| DM 审批传入 user_id 参数 — 未应用 | Approval cards may not arrive ⚠️ (Hermes doesn't know who to DM)（审批卡片可能收不到 — 不知道该私信谁） |
| 工具进度消息进入 Mattermost Thread — 已应用 | Progress stays in Threads ✅ (where you chat, progress follows)（进度显示在 Thread 里 — 在哪聊就在哪显示） |
| 2/2 patches 已应用 | Result: 2/2 passed（2/2 项通过） |

### 状态标签

| 场景 | 消息 |
|------|------|
| 已修复 | already applied ✅, skipping（已经好了，跳过） |
| 刚修复 | applied successfully ✅（修复成功） |
| 失败 | failed ❌, check if Hermes is properly installed（修复失败，请检查安装） |
| 全部 OK | All good, every fix is working ✨（一切正常，所有修复都已生效） |

### 交互式重启提示

```
───────────────────────────────────────────────────
Restart required for fixes to take effect. Restart now? [Y/n]（需要重启才能生效，是否现在重启？）
```

## 语言策略

- README：中英文双文件（`README.md` + `README.zh-CN.md`），先定稿中文再同步英文
- 脚本输出：英语为主，中文放括号或下行，面向国际用户 + 中国用户均能理解
