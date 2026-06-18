# enhancer 插件兼容性审计清单

Hermes 版本升级后，对照 bundled adapter 逐方法检查 enhancer 插件兼容性。

## 审计步骤

### 1. 确认当前版本基线

```bash
cd /Users/Colin/.hermes/hermes-agent && git log -1 --format="%H %ai %s"
cd /Users/Colin/.hermes/plugins/mattermost-enhancer && git log -1 --format="%H %ai %s"
```

### 2. 列出 bundled adapter 全部方法

```bash
grep -n "^\s*async def \|^\s*def " hermes-agent/plugins/platforms/mattermost/adapter.py
```

### 3. 列出 enhancer adapter 全部方法

```bash
grep -n "^\s*async def \|^\s*def " plugins/mattermost-enhancer/adapter.py
```

### 4. 逐方法对照

对 bundled adapter 每个方法判断：**覆盖 / 继承 / 需检查**

| 优先级 | 检查重点 |
|--------|---------|
| 🔴 必须覆盖 | `send()` `send_typing()` `_resolve_root_id()` `_send_local_file()` `_send_url_as_file()` `connect()` `disconnect()` |
| 🟡 扩展覆盖 | `send_clarify()` `send_exec_approval()` — 这两者来自 base.py, enhancer 新增了 MM 交互卡片能力 |
| 🟢 继承即可 | `format_message()` `truncate_message()` `edit_message()` `_api_get/post/put` `_upload_file` `_ws_loop` 等 |

### 5. 检查注册表

- `__init__.py` 中 `register_platform()` 是否传递了 `apply_yaml_config_fn=_apply_yaml_config`？
  - 缺少 → config.yaml 的 `mattermost:` 配置（require_mention/free_response_channels/allowed_channels）全部失效
- **v2026.6.5+ 新增**：`register_platform()` 是否传递了 bundled adapter 全部参数？
  - 必须包含：`is_connected`、`setup_fn`、`standalone_sender_fn`、`max_message_length`、`emoji`、`allow_update_command`、`allowed_users_env`、`allow_all_env`、`cron_deliver_env_var`
  - 缺失 `standalone_sender_fn` → cron 投递失败（**最严重**）
  - 缺失 `allowed_users_env` → 权限检查链路断裂
  - 缺失 `cron_deliver_env_var` → Home Channel 配置失效
  - 缺失其余 → 功能退化但不致命
- `plugin.yaml` 的 `min_hermes_version` 是否匹配？
- `plugin.yaml` 的 `hooks` 是否完整列出所有 `register_hook()` 调用？

### 6. 检查导入路径

v0.14.0 起 bundled adapter 位于 `hermes_plugins.platforms_mattermost.adapter`。

```python
# 正确 ✅
from hermes_plugins.platforms_mattermost.adapter import MattermostAdapter, MAX_POST_LENGTH

# 过时 ❌（旧 gateway/platforms/ 路径）
from gateway.platforms.mattermost import MattermostAdapter
```

### 7. 运行自动化检查

```bash
bash scripts/hermes-patches.sh check
bash plugins/mattermost-enhancer/scripts/hermes-mattermost-enhancer.sh check
```

两者应全部通过。

## 已知持续存在的 Gap（每次审计都需复核）

| # | 问题 | 影响 | 状态 |
|---|------|------|:--:|
| P51 | `MAX_POST_LENGTH = 4000` 未提升到 16000 | 长消息被截断，CRT Thread 中折叠 | ⚠️ 未修复 |

## 上次审计

- **日期**: 2026-06-08
- **Hermes 版本**: `v2026.6.5-181-gc98637723`
- **插件版本**: v2.4.1
- **结果**: 全部 adapter 覆写兼容。5/5 shell patch 仍需 apply。发现 `register_platform` 缺失 9 个 bundled adapter 参数（**严重**——cron 投递/权限/HomeChannel 失效）。详见 [hermes-v2026.6.5-plugin-audit.md](hermes-v2026.6.5-plugin-audit.md)
