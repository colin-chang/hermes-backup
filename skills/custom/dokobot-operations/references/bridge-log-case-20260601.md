# 案例：2026-06-01 dokobot bridge 冷启动超时

## 时间线（北京时间 = UTC+8）

| 时间 (UTC) | 时间 (北京时间) | 事件 |
|:---|:---|:---|
| 5/31 20:04 | 5/31 04:04 | bridge 关闭 (`stdin ended, shutting down`) |
| （此后 13h 无任何 dokobot 活动） | | |
| **6/1 09:00** | **6/1 17:00** | **cron job 触发 → `dokobot read --local --timeout 15` → 冷启动超时 → "No local bridge running"** |
| 6/1 11:22 | 6/1 19:22 | bridge 被手动触发重新启动（冷启动成功） |

## 根因

1. bridge 从上次关闭到 cron 触发间隔 **13 小时**
2. cron prompt 中连通性检测超时仅 **15 秒**
3. bridge 冷启动全流程（CLI 通知 Chrome → fork → node init → 握手 → 页面加载）超过 15 秒
4. CLI 超时返回 "No local bridge running"
5. cron agent 按降级规则走 `web_search`（Brave），导致大量数据源跳过（小红书等登录墙内容）

## 前两日对比

| 日期 | 17:00 bridge 状态 | 原因 |
|:---|:---|:---|
| 5/30 | ✅ 热启动 | 当日 12:22 有其他操作触发过 bridge |
| 5/31 | ✅ 热启动 | 当日 16:28 bridge 启动（距 cron 仅 32 分钟） |
| 6/1 | ❌ 冷启动超时 | 上次活动 5/31 04:04，间隔 13h |

## 修复

将 prompt 1.3 节连通性检测从：
```bash
dokobot read --local '...' --screens 1 --timeout 15
```
改为：
```bash
for i in 1 2 3; do
  result=$(dokobot read --local 'https://www.reddit.com/r/ImmigrationCanada/' --screens 1 --timeout 30 2>&1)
  if echo "$result" | grep -q "sessionId="; then
    echo "DOKOBOT_OK"; break
  fi
  sleep 5
done
```

## Bridge 历史重启模式

从 bridge.log 观察到的模式（5/30-6/1）：
- bridge 频繁 `stdin ended → restart` 循环
- 重启触发来自 `dokobot read --local` 调用
- 最长无活动间隔即本次 13h（触发冷启动超时）
- Chrome 始终在运行（pid 32881 存活），问题仅在冷启动时间不够
