# P1: apply_yaml_config_fn 丢失（Hermes v0.14.0 迁移问题）

## 问题

升级 Hermes v0.14.0 后，`config.yaml` 中 `mattermost.require_mention: false` 不生效。即使未 @提及机器人，消息也被静默跳过。

## 根因

v0.14.0 将 MattermostAdapter 从 `gateway/platforms/mattermost.py` 迁移为 bundled plugin (`plugins/platforms/mattermost/`)。Bundled 插件通过 `apply_yaml_config_fn=_apply_yaml_config` 将 `config.yaml` 的 `mattermost:` 键翻译为 `MATTERMOST_*` 环境变量。

`mattermost-enhancer` 插件调用 `ctx.register_platform(name="mattermost", ...)` 重新注册同名平台时，**完全替换** bundled 插件的 `PlatformEntry`（platform_registry.py 采用 "last writer wins" 策略）。由于 enhancer 的注册调用**未包含 `apply_yaml_config_fn`**，该字段变为 `None`。

`gateway/config.py` 遍历 `all_entries()` 时遇到 `apply_yaml_config_fn=None` 直接 `continue` 跳过，YAML→env 翻译永不执行。

**影响的配置项：**
- `require_mention`
- `free_response_channels`
- `allowed_channels`

## 修复

在 enhancer 的 `__init__.py` 的 `register_platform()` 调用中显式传入：

```python
from hermes_plugins.platforms_mattermost.adapter import _apply_yaml_config

ctx.register_platform(
    name="mattermost",
    ...
    apply_yaml_config_fn=_apply_yaml_config,  # ← 关键
    ...
)
```

## 诊断方法

1. 检查 `os.environ.get("MATTERMOST_REQUIRE_MENTION")` — 若为 `None`（非 `"false"`），则翻译未生效
2. 检查 gateway 日志：`grep -i "require_mention\|MATTERMOST_REQUIRE\|skipping.*without @mention" gateway.log`
3. 未修复时，非 DM 消息无 @mention 会触发 `Mattermost: skipping non-DM message without @mention` 日志行

## 相关

- P2: `hermes-mattermost-enhancer.sh` Patch 2 检查模式过期
- bundled plugin `_apply_yaml_config` 源码: `plugins/platforms/mattermost/adapter.py:1095`
- gateway `config.py:884-906` — `all_entries()` 遍历 + `apply_yaml_config_fn` 调用
