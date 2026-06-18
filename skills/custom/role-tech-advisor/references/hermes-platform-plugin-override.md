# Hermes Platform Plugin Override — 模式与陷阱

> 创建日期：2026-05-27（Hermes v0.14.0 升级后审计）

## 背景

Hermes 的 `register_platform` 机制采用 **"last writer wins"** 策略。当自定义插件调用 `ctx.register_platform(name="mattermost", ...)` 时，会**完整替换** bundled plugin 注册的 `PlatformEntry`，包括其所有 hooks 和 callbacks。

## 核心陷阱：`apply_yaml_config_fn` 丢失

### 症状

`config.yaml` 中的平台配置项（如 Mattermost 的 `require_mention: false`、`free_response_channels`、`allowed_channels`）全部失效，表现为静默忽略（无任何错误日志）。

### 根因

```python
# ❌ 错误的 override 写法（enhancer 原始代码）
ctx.register_platform(
    name="mattermost",
    label="Mattermost (Approval)",
    adapter_factory=lambda cfg: MattermostApprovalAdapter(cfg),
    check_fn=check_mattermost_requirements,
    # ⚠️ 没有 apply_yaml_config_fn → PlatformEntry 中该字段为 None
    # Gateway 遍历时遇到 None 直接 continue 跳过
    required_env=[...],
)
```

Bundled plugin 注册时传入了 `apply_yaml_config_fn=_apply_yaml_config`，但 enhancer 覆盖时未传递，导致该函数引用丢失。

### Gateway 处理逻辑

```python
# gateway/config.py:890
for platform_name, entry in platform_registry.items():
    if entry.apply_yaml_config_fn is None:
        continue  # ← 静默跳过！
    entry.apply_yaml_config_fn(yaml_cfg, platform_cfg)
```

### 修复

从 bundled plugin 显式导入并传递：

```python
from hermes_plugins.platforms_mattermost.adapter import _apply_yaml_config

ctx.register_platform(
    name="mattermost",
    ...
    apply_yaml_config_fn=_apply_yaml_config,  # ← 必须携带
    ...
)
```

## 通用清单：override `register_platform` 时必须检查的字段

覆盖 bundled plugin 时，检查以下字段是否需要从原注册中携带：

| 字段 | 丢失后果 | 是否需要携带 |
|------|---------|:--:|
| `apply_yaml_config_fn` | config.yaml 平台配置静默失效 | ✅ 必须 |
| `setup_fn` | 交互式 setup wizard 不可用 | 按需 |
| `is_connected` | 平台连接状态检测失效 | ✅ 建议 |
| `standalone_sender_fn` | Cron out-of-process 投递失败 | ✅ 建议 |
| `cron_deliver_env_var` | Cron 投递目标丢失 | ✅ 必须 |
| `allowed_users_env` / `allow_all_env` | 用户授权失效 | ✅ 建议 |

## 修复后的验证方法

```bash
# 确认 apply_yaml_config_fn 已注册
grep -A20 'register_platform' __init__.py | grep apply_yaml_config_fn

# 重启后验证配置生效（以 Mattermost 为例）
env | grep MATTERMOST_REQUIRE_MENTION
# 应输出: false（如果 config.yaml 中设置了 require_mention: false）
```
