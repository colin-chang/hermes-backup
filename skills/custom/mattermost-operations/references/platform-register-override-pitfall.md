# Platform Register Override Pitfall — `apply_yaml_config_fn` 丢失

> 发现日期：2026-05-27 · Hermes v0.14.0 · mattermost-enhancer v2.2.1

## 问题

当自定义插件通过 `ctx.register_platform(name="mattermost", ...)` 覆盖 bundled 插件的平台注册时，**整个 `PlatformEntry` 被替换**（last writer wins），包括 `apply_yaml_config_fn` hook。

## 根因

`PlatformRegistry.register()` 使用字典覆盖语义（`platform_registry.py:186`）：

```python
self._entries[entry.name] = entry  # ← 完整替换，非 merge
```

Bundled `mattermost-platform` 插件注册时设置了 `apply_yaml_config_fn=_apply_yaml_config`，但 `mattermost-enhancer` 插件在重新注册时**未设置**该字段，默认 `None`。

Gateway 在 `config.py:888-906` 遍历时：

```python
for entry in _pr.all_entries():
    if entry.apply_yaml_config_fn is None:
        continue  # ← enhancer 的 entry 在此跳过
    seeded = entry.apply_yaml_config_fn(yaml_cfg, platform_cfg)
```

结果：`config.yaml` 中 `mattermost:` 下的所有设置（`require_mention`、`free_response_channels`、`allowed_channels`）通过 `_apply_yaml_config` → env var 的链路**完全断裂**。

## 影响范围

| 配置项 | 期望 | 实际 |
|--------|------|------|
| `require_mention: false` | 群聊免 @ | ❌ 依然要求 @mention |
| `free_response_channels: [...]` | 指定频道免 @ | ❌ 无效 |
| `allowed_channels: [...]` | 频道白名单 | ❌ 无效 |

## 修复

在 enhancer 插件的 `__init__.py` 中导入并传递 bundled 插件的 `_apply_yaml_config`：

```python
# __init__.py
from hermes_plugins.platforms_mattermost.adapter import _apply_yaml_config

def register(ctx):
    ctx.register_platform(
        name="mattermost",
        label="Mattermost (Approval)",
        adapter_factory=lambda cfg: MattermostApprovalAdapter(cfg),
        check_fn=check_mattermost_requirements,
        required_env=["MATTERMOST_URL", "MATTERMOST_TOKEN"],
        apply_yaml_config_fn=_apply_yaml_config,  # ← 修复
        ...
    )
```

## 通用教训

任何覆盖 bundled platform 的插件，必须检查 bundled 插件的 `PlatformEntry` 中设置了哪些非 `None` 字段，并在自己的注册中传递：

| 字段 | 默认值 | 丢失影响 |
|------|--------|---------|
| `apply_yaml_config_fn` | `None` | YAML→env 桥接失效 |
| `standalone_sender_fn` | `None` | Cron deliver 失败 |
| `max_message_length` | `None` | 使用默认值 |
| `cron_deliver_env_var` | `""` | Cron 投递路由丢失 |
| `setup_fn` | `None` | 交互式 setup 不可用 |
| `env_enablement_fn` | `None` | 自动启用检测失效 |

**检查清单**（每次 override 前）：
1. 读取 bundled plugin 的 `plugin.yaml` 和 `register()` 调用
2. 对比所有非默认字段是否在 override 中正确传递
3. 重启后验证：检查 `gateway.log` 中无 `apply_yaml_config_fn ... raised` 错误
