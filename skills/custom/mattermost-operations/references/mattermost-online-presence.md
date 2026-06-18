# Mattermost 在线状态（Presence）机制

> 最后更新：2026-05-29 | 基准版本：Mattermost Team Edition 11.7.0

## 核心认知

**Mattermost 的 presence 系统会持续重新评估用户状态，覆盖显式 API 设置。** 即使你调用 `PUT /users/{id}/status` 设置 `"status": "online"`，系统也会在下一个评估周期（~60s）根据 WebSocket 实际活动状态重新判定。

## 状态判定规则

| 状态 | 条件 |
|------|------|
| **online** | 最近 60s 内有活动（WebSocket 心跳/消息收发/typing） |
| **away** | 60s ~ 5min 无活动 |
| **offline** | 超过 5min 无活动，或 WebSocket 已断开 |

## Bot 在线状态的已知限制

### 1. 显式 status API 不持久

```bash
# ✅ 调用成功（200 OK）
PUT /api/v4/users/{bot_id}/status
{"user_id": "...", "status": "online"}
```

服务器日志显示成功，但绿点在几十秒后消失。根因：presence 评估器发现 bot 没有"人类活动模式"（无 typing、无频繁消息），自动降级为 away/offline。

### 2. 日志验证方法

```bash
# 查 bot 是否调了 status API
docker logs mm-app --tail 1000 2>&1 | grep "users/{bot_id}/status"

# 查 presence 评估日志（debug 级别）
docker logs mm-app --tail 1000 2>&1 | grep -i "presence\|status.*online\|status.*offline" | tail -20
```

### 3. 强制方案（不推荐）

- 每秒刷一次 status API → 浪费资源且可能被 rate limit
- 关闭 `EnableUserStatuses` → 所有人都不显示在线状态

## 用户在线状态丢失（移动端）

### 典型日志模式

```
02:11:46 desktop WS closed: i/o timeout                    ← 桌面端超时自动断开
02:11:53 mobile  WS closed: websocket: close 1006 (abnormal closure): unexpected EOF  ← App 切后台
02:11:53 mobile  WS reconnected: GET /api/v4/websocket     ← 重新打开 App 后重连
```

**重连后状态不会立即恢复。** Presence 系统需要下一次心跳（通常 30-60s）或用户主动发消息才会重新评估为 online。

### 影响范围

- 移动端：App 切后台 → WebSocket 被系统杀死 → 重开后短暂显示离线 → 自动恢复
- 桌面端：长时间空闲 → 自动降级为 away → 移动鼠标/打字后恢复
- 这是 Mattermost 标准行为，非异常

## Enhancer 插件的 status 上报

**已回滚（2026-05-29）。** 由于 presence 系统会立即覆盖API设置的 online 状态，在 `connect()` 中上报 online 没有实际意义。`disconnect()` 中上报 offline 虽然与 WebSocket 断开状态一致，但用户此时也看不到 bot 的绿点了——整体 ROI 为负。

**不要在 Enhancer 插件中添加 status 上报代码。** 这是 Mattermost 的 design limitation，不是代码缺失。
