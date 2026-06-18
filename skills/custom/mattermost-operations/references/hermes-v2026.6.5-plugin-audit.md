# Hermes v2026.6.5 — mattermost-enhancer 兼容性审计

审计日期：2026-06-08
Hermes 版本：v2026.6.5-181-gc98637723 (HEAD == origin/main)
插件版本：mattermost-enhancer v2.4.1

---

## 架构变更概览

v2026.6.5 的 bundled Mattermost adapter（`plugins/platforms/mattermost/`）相对 v0.14.0 无结构性重构，但 `register()` 调用新增了多个参数。

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

全部 5 个 patch 均未合入上游，old_string 全部可命中。**仅需更新脚本 Header 版本标注**（v2026.5.29 → v2026.6.5）。

---

## 二、Bundled Adapter 变更对照

### 2.1 `register()` 新增参数

v2026.6.5 的 bundled adapter `register()` 比 v0.14.0 多了以下参数：

```python
ctx.register_platform(
    name="mattermost",
    ...
    is_connected=_is_connected,           # 新增
    setup_fn=interactive_setup,           # 新增
    standalone_sender_fn=_standalone_send, # 新增
    max_message_length=MAX_POST_LENGTH,   # 新增
    emoji="💬",                           # 新增
    allow_update_command=True,            # 新增
    allowed_users_env="MATTERMOST_ALLOWED_USERS",    # 新增
    allow_all_env="MATTERMOST_ALLOW_ALL_USERS",      # 新增
    cron_deliver_env_var="MATTERMOST_HOME_CHANNEL",  # 新增
)
```

### 2.2 Enhancer `register_platform` 参数 Gap

Enhancer 的 `__init__.py` `register()` 仅传递了：

```python
ctx.register_platform(
    name="mattermost",
    label="Mattermost (Approval)",
    adapter_factory=lambda cfg: MattermostApprovalAdapter(cfg),
    check_fn=check_mattermost_requirements,
    apply_yaml_config_fn=_apply_yaml_config,
    required_env=["MATTERMOST_URL", "MATTERMOST_TOKEN"],
    install_hint="MATTERMOST_URL=... MATTERMOST_TOKEN=xxx ...",
)
```

**缺失参数清单**（由 bundled adapter 定义但 enhancer 未传递）：

| 参数 | 影响 |
|------|------|
| `is_connected=_is_connected` | 连接状态探测失效 |
| `setup_fn=interactive_setup` | CLI 交互式配置向导不可用 |
| `standalone_sender_fn=_standalone_send` | **cron 投递可能失败**（严重） |
| `max_message_length=MAX_POST_LENGTH` | 消息截断仍依赖 enhancer 类属性 |
| `emoji="💬"` | 平台图标丢失 |
| `allow_update_command=True` | 配置更新命令不可用 |
| `allowed_users_env` | 用户授权环境变量名不匹配 |
| `allow_all_env` | 全员允许标志不可用 |
| `cron_deliver_env_var` | cron 投递频道配置失效 |

### 2.3 关键兼容性结论

| 编号 | 问题 | 严重度 | 需修改？ |
|------|------|:--:|:--:|
| A1 | `MAX_MESSAGE_LENGTH` 冗余 | 🟢 低 | 可选（enhancer 类属性仍有效） |
| A2 | `_api_put` 无 timeout | 🟢 低 | 无需改（enhancer 已自实现） |
| A3 | WebSocket 心跳 15s vs 30s | 🟢 低 | 无需改（enhancer 已覆写） |
| A4 | `_resolve_root_id` 缓存 | 🟢 低 | 无需改（enhancer 优化） |
| A5 | Media Thread 路由 metadata → reply_to | 🟢 低 | 无需改（enhancer 已覆写） |
| **B1** | **`register_platform` 缺失 9 个参数** | **🔴 高** | **必须修复** |
| B2 | `_apply_yaml_config` 导入路径 | 🟢 低 | 无需改（已验证一致） |

---

## 三、需修复的 Action Items

### 🔴 紧急：补传 `register_platform` 参数

在 enhancer `__init__.py` 的 `register_platform()` 中补充 bundled adapter 已定义的所有关键参数：

```python
from hermes_plugins.platforms_mattermost.adapter import (
    _apply_yaml_config,
    _is_connected,
    _standalone_send,
    MAX_POST_LENGTH,
)

ctx.register_platform(
    name="mattermost",
    label="Mattermost (Approval)",
    adapter_factory=lambda cfg: MattermostApprovalAdapter(cfg),
    check_fn=check_mattermost_requirements,
    apply_yaml_config_fn=_apply_yaml_config,
    required_env=["MATTERMOST_URL", "MATTERMOST_TOKEN"],
    install_hint="MATTERMOST_URL=... MATTERMOST_TOKEN=xxx ...",
    # ── v2026.6.5 新增参数 ──
    is_connected=_is_connected,
    setup_fn=interactive_setup,          # from bundled plugin
    standalone_sender_fn=_standalone_send,
    max_message_length=MAX_POST_LENGTH,
    emoji="💬",
    allow_update_command=True,
    allowed_users_env="MATTERMOST_ALLOWED_USERS",
    allow_all_env="MATTERMOST_ALLOW_ALL_USERS",
    cron_deliver_env_var="MATTERMOST_HOME_CHANNEL",
)
```

**注意**：`interactive_setup` 需要从 bundled adapter 导入（`from hermes_plugins.platforms_mattermost.adapter import interactive_setup`）。

### 🟡 建议：更新 Shell 脚本 Header

将版本标注从 `v2026.5.29 / origin:main=aa32edcac` 更新为 `v2026.6.5 / origin:main=c98637723`。

---

## 四、无需修改的适配器方法（逐方法验证）

| 方法 | Bundled 实现 | Enhancer 覆写 | 结果 |
|------|------------|-------------|:--:|
| `_resolve_root_id` | 无缓存，API 直接调用 | 5 分钟 TTL 缓存 + 优雅降级 | ✅ 兼容，enhancer 更优 |
| `send()` | Thread 路由 + 分块 | + footer 内联合并 + 缓存优化 | ✅ 兼容 |
| `send_typing` | 直接 `_api_post` | Thread 路由修复 | ✅ 兼容 |
| `edit_message` | `_api_put` 无 timeout | 自实现 HTTP PUT + 30s timeout | ✅ 兼容，enhancer 更优 |
| `send_image/send_image_file/send_document/send_video/send_voice` | 未用 metadata 做 Thread 路由 | `_derive_reply_to(metadata=...)` | ✅ 兼容 |
| `send_multiple_images` | 未用 metadata 做 Thread 路由 | `_derive_reply_to(metadata=...)` | ✅ 兼容 |
| `_send_local_file` | 文件不存在时返回空 | MEDIA 静默跳过 | ✅ 兼容 |
| `_ws_connect_and_listen` | heartbeat=30s | heartbeat=15s | ✅ 兼容 |
| `connect/disconnect` | WebSocket 管理 | + 回调服务器启停 | ✅ 兼容 |
| `format_message/truncate_message` | — | 继承（无覆写） | ✅ 兼容 |
| `_api_get/_api_post/_api_put/_upload_file` | — | 继承（无覆写） | ✅ 兼容 |
| `send_clarify` | 无（base.py 默认） | MM 交互卡片 | ✅ enhancer 独有 |
| `send_exec_approval` | 无（base.py 默认） | DM 审批卡片 | ✅ enhancer 独有 |

---

## 五、审计结论

- **Shell Patch**：5/5 仍需要 + 可正常 apply ✅
- **Adapter 覆写**：全部兼容 ✅
- **`register_platform` 参数**：缺失 9 个 🔴 **必须修复**
- **脚本 Header**：需更新版本标注 🟡
- **`_build_session_key` chat_type 硬编码** 🔴 **新发现**：enhancer 硬编码 `"group"`，公开频道实际为 `"channel"` → 模型切换静默失效（2026-06-08 已修复，`"group"` → `"channel"`）
