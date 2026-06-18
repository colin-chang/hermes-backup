# Hermes v0.14.0 → mattermost-enhancer v2.2.1 兼容性审计

审计日期：2026-05-27
Hermes 版本：v0.14.0 (2026.5.16)，86 commits behind upstream
插件版本：mattermost-enhancer v2.2.1（last writer wins 覆盖 bundled mattermost-platform）

---

## 架构变更：Mattermost 适配器从 gateway/platforms/ 迁移至 bundled plugin

v0.14.0 的重大变更：`gateway/platforms/mattermost.py` 不再存在，改为 bundled plugin：

```
~/.hermes/hermes-agent/plugins/platforms/mattermost/
├── __init__.py       # from .adapter import register
├── adapter.py        # MattermostAdapter (1192行)
└── plugin.yaml       # name: mattermost-platform
```

该 plugin 由 Hermes 内置插件系统自动加载为 `hermes_plugins.platforms_mattermost`。

mattermost-enhancer v2.2.1 已通过 commit `7e5492d` 适配此变更——`adapter.py` 导入从：
```python
from gateway.platforms.mattermost import MattermostAdapter, MAX_POST_LENGTH
```
改为：
```python
from hermes_plugins.platforms_mattermost.adapter import MattermostAdapter, MAX_POST_LENGTH
```
并附 fallback importlib 机制应对非标准环境。

---

## P1（阻断）：`apply_yaml_config_fn` 丢失

### 根因

`PlatformRegistry.register()` 采用 **last writer wins** 策略。当 `mattermost-enhancer` 调用 `ctx.register_platform(name="mattermost", ...)` 时，**完整替换** bundled `mattermost-platform` 的 `PlatformEntry`。

bundled plugin 注册时包含 `apply_yaml_config_fn=_apply_yaml_config`，该函数负责将 `config.yaml` 的 `mattermost:` 设置翻译为 `MATTERMOST_*` 环境变量：

```python
def _apply_yaml_config(yaml_cfg: dict, mattermost_cfg: dict) -> dict | None:
    if "require_mention" in mattermost_cfg and not os.getenv("MATTERMOST_REQUIRE_MENTION"):
        os.environ["MATTERMOST_REQUIRE_MENTION"] = str(mattermost_cfg["require_mention"]).lower()
    # ... free_response_channels, allowed_channels
```

但 enhancer 的 `register_platform()` 调用**未设置 `apply_yaml_config_fn`**，默认 `None`。

### 调用链路

```
gateway/config.py:890  for entry in _pr.all_entries():
                          if entry.apply_yaml_config_fn is None:
                              continue         # ← 跳过 enhancer 的 entry
                          seeded = entry.apply_yaml_config_fn(yaml_cfg, platform_cfg)
```

### 影响

| 配置项 | config.yaml 设置 | 实际行为 |
|--------|-----------------|---------|
| `mattermost.require_mention: false` | 不 @ 也能回复 | ❌ 仍需 @mention |
| `mattermost.free_response_channels` | 指定频道免 @ | ❌ 无效 |
| `mattermost.allowed_channels` | 频道白名单 | ❌ 无效 |

### 修复

在 enhancer `__init__.py` 的 `register_platform()` 调用中补充：

```python
from hermes_plugins.platforms_mattermost.adapter import _apply_yaml_config

ctx.register_platform(
    name="mattermost",
    ...
    apply_yaml_config_fn=_apply_yaml_config,  # ← 新增
    ...
)
```

---

## P2（阻断）：`hermes-mattermost-enhancer.sh` Patch 2 检查模式过期

### 根因

Patch 2 试图修复 `_progress_reply_to` 只检查 `Platform.FEISHU` 的问题。但 v0.14.0 上游已用不同方式修复：

```python
# 上游当前代码 (run.py:16064)
_progress_reply_to = (
    event_message_id
    if source.platform in (Platform.FEISHU, Platform.MATTERMOST) and source.thread_id and event_message_id
    else None
)
```

脚本的 grep 检查 `'or source.platform == Platform.MATTERMOST'` 无法匹配新的 `in (Platform.FEISHU, Platform.MATTERMOST)` 模式。

### 现象

- `check` 报告 Check ② 失败（误报）
- `apply` 因找不到旧字符串而 SKIP

### 修复

更新检查条件为通用匹配：`grep -qE 'Platform\.MATTERMOST'`

或直接移除 Patch 2——上游已修复。

---

## P3（中）：MAX_POST_LENGTH=4000 未修复

bundled plugin 仍硬编码 `MAX_POST_LENGTH = 4000`（adapter.py:37）。Mattermost 服务端支持 16383。

已在 enhancer 中通过 `from hermes_plugins.platforms_mattermost.adapter import MAX_POST_LENGTH` 继承此缺陷。

修复：在 enhancer `adapter.py` 中覆盖常量 `MAX_POST_LENGTH = 16000`。

---

## P4（中）：WebSocket 频繁重连（close code 258）

日志模式：约 50 秒一次 `WebSocket closed (258)` → 立即重连。258 为 Mattermost 服务端策略关闭（可能为 keepalive 超时）。bundled adapter 的 ping/pong 心跳可能未正确配置。

暂时非致命——自动重连正常。需进一步调研 Mattermost 服务端 `config.json` 的 WebSocket 相关超时设置。

---

## P5（低）：时区配置错误

`config.yaml` 设置 `timezone: Asia/Shanghai`，但用户实际在加拿大东部（EDT/EST）。导致 macOS 自动深色模式不触发、cron job 执行时间偏移。

修复：`timezone: America/Toronto`。

---

## P6（已知遗留）：幽灵代码围栏（P53）和消息截断（P51）

这两个问题存在于 `BasePlatformAdapter.truncate_message()` 和 bundled adapter 的 `MAX_POST_LENGTH`，非本次迁移引入，但迁移未解决。

---

## 迁移状态总结

| 项目 | v0.13.x 旧状态 | v0.14.0 新状态 | 兼容性 |
|------|---------------|---------------|--------|
| 源代码位置 | `gateway/platforms/mattermost.py` | `plugins/platforms/mattermost/` bundled plugin | ✅ v2.2.1 已适配 |
| `_resolve_root_id` | enhancer override | enhancer override（沿用） | ✅ |
| `send()` | enhancer override | enhancer override（沿用） | ✅ |
| `send_typing()` | enhancer override | enhancer override（沿用） | ✅ |
| `send_clarify()` | enhancer override | enhancer override（沿用） | ✅ |
| `send_exec_approval()` | enhancer override | enhancer override（沿用） | ✅ |
| `connect()`/`disconnect()` | enhancer override | enhancer override（沿用） | ✅ |
| `_send_local_file()` | enhancer override | enhancer override（沿用） | ✅ |
| `_send_url_as_file()` | enhancer override | enhancer override（沿用） | ✅ |
| Patch 1 (user_id) | 脚本 patch | 脚本 patch（沿用） | ✅ |
| Patch 2 (progress) | 脚本 patch | **上游已修复**，检查模式需更新 | ⚠️ |
| Patch 3 (clarify) | 脚本 patch | 脚本 patch（沿用） | ✅ |
| Patch 4 (clarify guard) | 脚本 patch | 脚本 patch（沿用） | ✅ |
| `apply_yaml_config_fn` | gateway/config.py 硬编码 | **PlatformEntry hook，enhancer 丢失** | ❌ P1 |
| MAX_POST_LENGTH | 4000 | 4000（未变） | ⚠️ P3 |
