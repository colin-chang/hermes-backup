# Hermes v2026.6.5-617 — mattermost-enhancer 兼容性审计

审计日期：2026-06-11
Hermes 版本：v2026.6.5-617-g955fa4006 (origin/main=85503dce)
插件版本：mattermost-enhancer v2.4.3-1-gfe47192

---

## 架构变更概览

相对上次审计（v2026.6.5-181-gc98637723），gateway/run.py 经历了 God-file Phase 3 重构（-4,931/+924 行）：
- GatewayAuthorizationMixin 提取
- GatewaySlashCommandsMixin 提取
- GatewayKanbanWatchersMixin 提取

Bundled Mattermost 插件（`plugins/platforms/mattermost/`）零变更。

---

## 一、Shell Patch 双重验证（5 个补丁）

### 维度 A：Check Pattern（修复是否已入上游）

| Patch | 文件 | Check Pattern | grep 匹配数 | 结论 |
|-------|------|--------------|:---:|------|
| P1 | gateway/run.py | `or source.platform == Platform.MATTERMOST` | 0 | ❌ 未合入 |
| P2 | gateway/run.py | `_canonical_entry = self.session_store.get_or_create_session` | 0 | ❌ 未合入 |
| P3 | gateway/run.py | `Gateway intercepted clarify at session guard` | 0 | ❌ 未合入 |
| P4 | gateway/run.py | `Deduplicate.*keep only the most recent` | 0 | ❌ 未合入 |
| P5 | gateway/run.py | `source.platform == Platform.MATTERMOST and not source.thread_id` | 0 | ❌ 未合入 |

### 维度 B：old_string（Patch 是否可命中）

| Patch | old_string 在 origin/main 中存在？ |
|-------|:---:|
| P1 | ✅ YES |
| P2 | ✅ YES |
| P3 | ✅ YES |
| P4 | ✅ YES |
| P5 Part A | ✅ YES |
| P5 Part B | ✅ YES |

### 结论

全部 5 个 patch 均未合入上游，old_string 全部可命中。gateway/run.py 的 God-file Phase 3 重构提取了其他功能区块，未触及 patch 目标区域。

**仅需更新脚本 Header 版本标注**（v2026.6.5 → v2026.6.5-617）。

---

## 二、Bundled Adapter 变更对照

### 2.1 `register()` 参数

零变更。与上次审计完全一致。

### 2.2 Enhancer `register_platform` 参数

已在 v2.4.2 修复的 9 个缺失参数全部保留。无新增参数缺口。

---

## 三、Adapter 覆写方法签名兼容性

所有覆写方法与 bundled adapter 签名完全匹配。

| 方法 | 状态 |
|------|:--:|
| `send()` | ✅ |
| `edit_message()` | ✅ |
| `connect()` / `disconnect()` | ✅ |
| `_ws_connect_and_listen()` | ✅ |
| `send_image/send_image_file/send_document/send_video/send_voice` | ✅ |
| `send_multiple_images()` | ✅ |
| `_send_local_file/_send_url_as_file` | ✅ |
| `_resolve_root_id` | ✅ |
| `send_typing` | ✅ |
| `send_clarify` / `send_exec_approval` | ✅ enhancer 独有 |

### WebSocket 重连链验证

```
enhancer.connect() → super().connect() [bundled]
  → bundled._ws_loop()
    → self._ws_connect_and_listen() [enhancer, 15s heartbeat]
      → self._handle_ws_event() [bundled]
```

MRO 链正确，enhancer 的 15s heartbeat 正常工作。

---

## 四、Gateway 新功能影响评估

所有 c98637723 → 85503dce 期间的 gateway 改动均不影响 Mattermost Enhancer：

- `96af61b6e` memory/skills approve/deny gate → Gateway 层，不影响 adapter
- `639c1e363` max session cap → Gateway 层
- `9351cbafa` auto-deliver image_generate → Gateway 层
- `619bd7827` slash-command handlers 提取 → 重构，enhancer 的 /model /new 走自己的回调服务器
- 其余 25+ commits → 均为 Gateway 层改动或平台无关修复

---

## 五、审计结论

- **Shell Patch**：5/5 仍需要 + 可正常 apply ✅
- **Adapter 覆写**：全部兼容 ✅
- **`register_platform` 参数**：已完整 ✅
- **脚本 Header**：已更新版本标注 ✅
- **Bundled adapter**：零变更，无需适配 ✅

**综合结论：无需任何代码修改。所有 patch 可直接 apply。**
