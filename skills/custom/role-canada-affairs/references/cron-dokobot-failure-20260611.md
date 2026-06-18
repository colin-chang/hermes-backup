# Cron 故障记录：2026-06-11 — Dokobot Bridge 宕机 + Agent 跳过连通性检测

## 事件时间线

| 时间 (UTC) | 时间 (CST) | 事件 |
|:---|:---|:---|
| 2026-06-10 14:09 | 2026-06-10 22:09 | Bridge 正常退出 `stdin ended, shutting down` |
| 2026-06-10 ~22:20 | 2026-06-11 ~06:20 | **Chrome 崩溃**（`exit_type: Crashed`） |
| 2026-06-11 约 06:20+ | 2026-06-11 约 14:20+ | Chrome 自动重启，Bridge **未自动重连** |
| **2026-06-11 09:00** | **2026-06-11 17:00** | **Cron 触发** |
| 2026-06-11 09:00:37 | 2026-06-11 17:00:37 | Agent 开始执行，**跳过了 1.3 节连通性检测**，直接走 `web_search` 降级 |
| 2026-06-11 09:03:40 | 2026-06-11 17:03:40 | 日报输出（仅 RSS/curl 数据，无社区平台内容） |
| 2026-06-11 09:11 | 2026-06-11 17:11 | 手动打开 `chrome://extensions` 触发扩展重载 → Bridge 恢复 ✅ |

## 根因分析

### 基础设施：Bridge 宕机（Chrome 崩溃后遗症）
- Chrome 进程崩溃导致 Native Messaging 连接断裂
- Chrome 重启后，Dokobot 扩展虽已加载但 Bridge 进程**未自动重连**
- 形成死锁：bridge 已死 → `dokobot read --local` 无法通知 Chrome 冷启动 → bridge 永远起不来
- `dokobot install-bridge` 对此模式**无效**（文件未损坏，问题在运行时状态）

### 模型行为：连通性检测被跳过
- doubao-seed-2.0-pro 在 9 次 API 调用中**完全未执行 1.3 节连通性检测**
- 直接跳到了 `web_search` 降级搜索（Reddit/X/CanadaVisa）
- 可能原因：prompt 太长（~40KB），连通性检测位于 1.3 节，被 1.1 节 RSS curl 的大批量输出"淹没"后模型选择性忽略了

### 雪上加霜：Brave Search 部分失败
- Reddit 降级搜索：0 结果
- X 降级搜索：SSL `UNEXPECTED_EOF_WHILE_READING`
- CanadaVisa 降级搜索：同上 SSL 错误

## 恢复步骤（已验证）

```bash
# 1. 打开 Chrome 扩展页面触发重载（无需重启 Chrome）
open -a "Google Chrome" "chrome://extensions/?id=dlbiigchkpmpijahmlofleeemiomaneo"

# 2. 等待 3-5 秒后验证
sleep 5 && dokobot doko list
# → 应返回: 1d6b1ae5-bed4-428f-9f57-4f45159c1018  pid XXXXX, Chrome, ext 0.3.1

# 3. 功能验证
dokobot read --local 'https://www.reddit.com/r/ImmigrationCanada/' --screens 1 --timeout 30
```

## 长期加固建议

### Prompt 加固：提升连通性检测优先级
当前连通性检测位于 1.3 节（RSS → 静态页 → 连通性检测），模型可能在处理大量 RSS 输出后"忘记"这一步。

建议方案（待评估）：
- 将连通性检测提升为**阶段 0**（在所有数据抓取之前执行）
- 使用更短的、带强制性语气的指令（如 "在开始任何抓取之前，必须先执行..."）
- 或：将连通性检测改为 cron job 的 **pre-check watchdog**（独立 cron，在日报 cron 前 5 分钟运行）

### Bridge 健康自检 Cron
考虑增加一个独立的 bridge health check cron：
- 每 30 分钟运行一次 `dokobot doko list`
- 检测到 "No available devices" 时自动触发恢复（`open chrome://extensions`）
- 日报 cron 触发前确保 bridge 存活

### 相关参考
- `dokobot-operations` skill — 模式 E：Chrome Crashed → Bridge Dead 的完整诊断流程
- `immigration-monitor-prompt.md` — 日报 prompt 原文（1.3 节为连通性检测位置）
