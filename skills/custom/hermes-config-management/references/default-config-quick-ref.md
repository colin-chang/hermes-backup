# DEFAULT_CONFIG 快速参考

## 入口位置

`hermes_cli/config.py` 第 803 行：
```python
DEFAULT_CONFIG = {
    "model": "",
    "providers": {},
    ...
}
```

字典体量约 ~2800 行（803–3660），涵盖所有配置键的默认值。

## 常用键快速定位

| 配置段 | 行号 | 默认值特征 |
|--------|------|-----------|
| `model` / `providers` / `fallback_providers` | 803–807 | `""` / `{}` / `[]` |
| `credential_pool_strategies` | 807 | `{}` |
| `toolsets` | 808 | `["hermes-cli"]` |
| `max_concurrent_sessions` | 811 | `None` |
| `agent.*` | 812–926 | `max_turns: 90`, `gateway_timeout: 1800` |
| `terminal.*` | 928–1003+ | `cwd: "."`, `timeout: 180` |
| `web.*` | ~1080 | `backend: ""`, `search_backend: ""` |
| `browser.*` | ~1110 | `inactivity_timeout: 120` |
| `compression.*` | ~1220 | `enabled: true`, `threshold: 0.5` |
| `auxiliary.*` | ~1350 | 各功能 provider/model 配置 |
| `display.*` | ~1760 | `language: "en"`, `streaming: true` |
| `streaming.*` | ~2275 | `enabled: true`, `cursor: " ▉"` |
| `sessions.*` | ~2390 | `auto_prune: true` |
| `onboarding.*` | ~2460 | `profile_build: "ask"` |
| `updates.*` | ~2480 | `pre_update_backup: true` |
| `_config_version` | 2502 | `29`（随版本递增） |
| `code_execution.*` | 2129 | `mode: "project"` |
| `security.*` | ~2550 | `allow_private_urls: false` |

## 验证某配置项是否为默认值

```bash
# 方法 1：grep 定位（适合精确定位）
grep -n '"<key>":' /Users/Colin/.hermes/hermes-agent/hermes_cli/config.py

# 方法 2：从 803 行开始阅读上下文
read_file hermes-agent/hermes_cli/config.py offset=803 limit=200
```

## 常见 Desktop 写入的默认值清单

以下值在 DEFAULT_CONFIG 中已定义，Desktop 覆写后必须移除：

- `credential_pool_strategies: {}`
- `toolsets: ["hermes-cli"]`
- `max_concurrent_sessions: null`
- `code_execution.mode: project`
- `streaming.cursor: " ▉"`
- `_config_version: <N>`
- `onboarding.profile_build: ask`
- `approvals.mcp_reload_confirm: true`（当 mode 为 smart 时）
- `terminal.backend: local` / `terminal.modal_mode: auto`
- `browser.*` 全部子键（默认全为默认值）
- `checkpoints.*` 全部子键
- `compression.*` 全部子键
- `agent.*` 除 `max_turns` 外的全部子键
- `display.*` 除显式配置外的全部子键
- `security.*` 除 `allow_private_urls` 外的全部子键
