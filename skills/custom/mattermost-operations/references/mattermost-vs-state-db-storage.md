# Mattermost vs Hermes 双重存储机制

## 问题场景

用户同时使用 Mattermost（Docker Compose 自部署）+ Hermes Agent。当 Hermes 的 `auto_prune` 清理 `state.db` 后，Agent 丢失旧对话上下文，但 Mattermost 频道中历史消息仍然可见。

## 架构

```
┌─ Mattermost Docker ────────────────────────────┐
│  PostgreSQL（独立 Volume）                       │
│  ├─ 所有频道消息（含 Hermes 回复）                │
│  └─ 不受 Hermes 任何配置影响                      │
└────────────────────────────────────────────────┘

┌─ Hermes Agent ──────────────────────────────────┐
│  ~/.hermes/state.db（SQLite + FTS5）              │
│  ├─ 会话元数据 + 消息转录                         │
│  ├─ auto_prune 清理的就是这个                      │
│  └─ 清理后 Agent 丢失旧上下文                      │
└──────────────────────────────────────────────────┘
```

## 关键事实

1. **两层存储完全独立** — Mattermost PostgreSQL ≠ Hermes state.db
2. Gateway 从 state.db 加载历史（`gateway/run.py:7867`），不读 Mattermost API
3. Hermes `auto_prune` 只影响 state.db，Mattermost 消息不受影响
4. state.db 清理后重新对话 → Agent 从空历史开始
5. 想彻底删除对话 → 需要两边都清（Mattermost 频道 + `hermes sessions delete`）

## 相关代码

- `gateway/run.py:7867`: `history = self.session_store.load_transcript(session_entry.session_id)`
- `hermes_state.py:4195`: `maybe_auto_prune_and_vacuum(retention_days=90)`
- `gateway/session.py:628-670`: session_key 构造（platform 级隔离）
