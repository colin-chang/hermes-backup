# DEFAULT_CONFIG 快速参考

## 入口位置

`hermes_cli/config.py` 第 883 行（⚠️ 行号随版本漂移，以 `grep -n 'DEFAULT_CONFIG = {'` 定位为准）：
```python
DEFAULT_CONFIG = {
    "model": "",
    "providers": {},
    ...
}
```

字典体量约 ~2800 行（883–3660），涵盖所有配置键的默认值。

## 常用键快速定位

> ⚠️ 以下行号为快照，随上游更新会漂移。以 `grep -n` 实时定位为准。

| 配置段 | 行号（快照） | 默认值特征 |
|--------|------|-----------|
| `model` / `providers` / `fallback_providers` | 884–886 | `""` / `{}` / `[]` |
| `credential_pool_strategies` | 887 | `{}` |
| `toolsets` | 888 | `["hermes-cli"]` |
| `max_concurrent_sessions` | 891 | `None` |
| `agent.*` | 892–960+ | `max_turns: 90`, `gateway_timeout: 1800`（`reasoning_effort` 不在 dict 中，运行时默认 `"medium"`） |
| `terminal.*` | ~1008+ | `cwd: "."`, `timeout: 180` |
| `web.*` | ~1160 | `backend: ""`, `search_backend: ""` |
| `browser.*` | ~1190 | `inactivity_timeout: 120` |
| `compression.*` | ~1300 | `enabled: true`, `threshold: 0.5` |
| `auxiliary.*` | ~1430 | 各功能 provider/model 配置 |
| `display.*` | ~1840 | `language: "en"`, `streaming: true` |
| `streaming.*` | ~2355 | `enabled: true`, `cursor: " ▉"` |
| `sessions.*` | ~2470 | `auto_prune: true` |
| `onboarding.*` | ~2540 | `profile_build: "ask"` |
| `updates.*` | ~2560 | `pre_update_backup: true` |
| `_config_version` | ~2582 | `29`（随版本递增） |
| `code_execution.*` | ~2209 | `mode: "project"` |
| `security.*` | ~2630 | `allow_private_urls: false` |

## 验证某配置项是否为默认值

```bash
# 方法 1：grep 定位（适合 DEFAULT_CONFIG 中有的键）
grep -n '"<key>":' /Users/Colin/.hermes/hermes-agent/hermes_cli/config.py

# 方法 2：从 DEFAULT_CONFIG 开始阅读上下文
read_file hermes-agent/hermes_cli/config.py offset=883 limit=200

# 方法 3：对于不在 DEFAULT_CONFIG 中的键，查 cfg_get docstring 和调用点
grep -rn 'cfg_get.*<key>\|cfg.get.*"<key>"' hermes-agent/hermes_cli/ hermes-agent/ --include='*.py'
```

## 常见 Desktop / YAML 规范化工具写入的默认值清单

以下值在 DEFAULT_CONFIG 中已定义或运行时默认，Desktop / 规范化工具覆写后必须移除：

- `credential_pool_strategies: {}`
- `toolsets: ["hermes-cli"]`
- `max_concurrent_sessions: null`
- `code_execution.mode: project`
- `streaming.cursor: " ▉"`
- `_config_version: <N>`
- `onboarding.profile_build: ask`
- `approvals.mcp_reload_confirm: true`（当 mode 为 smart 时）
- `agent.reasoning_effort: medium`（不在 DEFAULT_CONFIG["agent"] 中，但 `cfg_get` 运行时默认 `"medium"`，规范化工具常写入）
- `mcp_servers.<name>.enabled: true`（`mcp_config.py` 中 `cfg.get("enabled", True)` 默认 True，规范化工具常写入）
- `terminal.backend: local` / `terminal.modal_mode: auto`
- `browser.*` 全部子键（默认全为默认值）
- `checkpoints.*` 全部子键
- `compression.*` 全部子键
- `agent.*` 除 `max_turns` 外的全部子键
- `display.*` 除显式配置外的全部子键
- `security.*` 除 `allow_private_urls` 外的全部子键
