# Mattermost 客户端消息自动折叠（Show More）

## 现象

Mattermost 频道视图中，长消息会被自动截断，显示「Show More」按钮，需要点击才能展开完整内容。

## 关键结论

**这是 Mattermost Web/桌面客户端的固定 UI 行为，不可通过用户设置关闭。**

Settings → Display 中没有「Collapse posts that exceed N lines」这样的选项。
唯一的折叠相关设置是「Collapsed Reply Threads (CRT)」——控制回复是以侧边面板
还是内联方式显示，与消息内容的 Show More 截断无关。

## 触发条件

- 频道视图中（Center Panel），消息超过约 10-15 行文本时触发
- Thread 右侧面板中消息**完整展开**，不截断
- 搜索结果中消息**完整展开**，不截断

## 混淆风险

| 概念 | 可配置？ | 说明 |
|------|:---:|------|
| Show More 消息截断 | ❌ 不可配置 | 硬编码 UI 行为 |
| CRT 线程折叠 | ✅ Settings → Display | 控制回复显示方式（侧面板/内联） |
| MAX_POST_LENGTH 分片 | ✅ Hermes 侧 | P51，控制 Hermes 发帖长度上限 |

## 常见误判

❌ 「Settings → Display 里有个 Collapse posts that exceed 5 lines 选项」
   → **此选项不存在**。之前给出此建议是错误的。

✅ 正确解释：Mattermost 客户端自动折叠长消息，无用户级开关。

## 变通方案

| 方式 | 说明 |
|------|------|
| 点击 Show More | 手动展开，最直接 |
| 点击进 Thread | Thread 面板中消息完整显示 |
| Cmd/Ctrl+K 搜索 | 搜索结果中显示完整内容 |
| 减少消息长度 | P51 修复到 16000 可减少拆分→减少折叠概率 |

## 验证环境

- Mattermost Team Edition v11.7.0
- 桌面客户端（macOS）
- 2026-06-14 确认
