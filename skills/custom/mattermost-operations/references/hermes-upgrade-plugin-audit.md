# Hermes Agent 升级 → Mattermost Enhancer 适配审计

> 每次 `hermes-agent` 升级后，必须对 enhancer 插件执行此审计清单。

## 审计清单

### 1. Shell Patch 双重验证（§A + §B）

对 `hermes-mattermost-enhancer.sh` 中的每个活跃 patch，执行双维度验证：

```bash
cd ~/.hermes/hermes-agent

# 维度 A：check pattern 是否命中 origin/main
git show origin/main:gateway/run.py | grep "<check_pattern>"
# 匹配数 == 0 → 未合入 ✅
# 匹配数 > 0 → 可能是假阳性，需排查

# 维度 B：old_string 是否仍存在于 origin/main
# ⚠️ 必须用文件中转 + 三引号方式
git show origin/main:gateway/run.py > /tmp/_audit_mm_run.py
python3 <<'PYEOF'
with open('/tmp/_audit_mm_run.py') as f:
    content = f.read()
for label, old in [
    ("P1", """..."""),
    ("P2", """..."""),
    # ... 每个 patch
]:
    print(f"{label}: {'YES' if old in content else 'NO — SKIP'}")
PYEOF
```

详见 `hermes-patch-management` skill §4 和 `references/dual-check-verification.md`。

### 2. register_platform 参数同步

Bundled Mattermost adapter（`~/.hermes/hermes-agent/plugins/platforms/mattermost/adapter.py`）的 `register()` 调用中新增的参数，必须同步到 enhancer 的 `__init__.py` 的 `register_platform()` 调用。

**检查方法**：

```bash
# 列出 bundled adapter register() 中的所有参数
grep -A30 'def register' \
  ~/.hermes/hermes-agent/plugins/platforms/mattermost/adapter.py \
  | grep -oE '\w+=' | tr -d '=' | sort

# 列出 enhancer register_platform() 中的所有参数
grep -A30 'register_platform' \
  ~/.hermes/plugins/mattermost-enhancer/__init__.py \
  | grep -oE '\w+=' | tr -d '=' | sort
```

**diff 结果中 enhancer 缺失的项即需导入并补传。**

历史遗漏案例（v2026.6.5）：
- `is_connected` — 连接状态探测
- `setup_fn` — 交互式安装向导
- `standalone_sender_fn` — cron 独立投递（**最关键**，缺失 = cron 投递失败）
- `max_message_length` — 消息长度限制
- `allowed_users_env` / `allow_all_env` / `cron_deliver_env_var`
- `emoji` / `allow_update_command`

### 3. import 路径验证

Enhancer `adapter.py` 从 bundled adapter 的 import 路径：

```python
from hermes_plugins.platforms_mattermost.adapter import MattermostAdapter, MAX_POST_LENGTH
```

确认 bundled adapter 仍在 `plugins/platforms/mattermost/` 目录下且 `MAX_POST_LENGTH` 未移除。

### 4. 函数签名兼容性

增强 adapter 覆写了以下 bundled 方法，需确认签名一致：

| 覆写方法 | 检查点 |
|----------|--------|
| `_ws_connect_and_listen()` | bundled 的 heartbeat 值（应为 30s） |
| `_resolve_root_id()` | 返回值类型、缓存逻辑 |
| `send()` | metadata 参数、reply_to 推导 |
| `edit_message()` | `_api_put` 是否需要 timeout |
| `send_image/send_document/send_video/send_voice` | metadata → reply_to 推导 |
| `send_multiple_images()` | metadata 参数 → Thread 路由 |
| `connect()/disconnect()` | 回调服务器启停是否在 super() 前后正确 |

### 5. Plugin 注册冲突检查

Gateway 启动日志中确认 enhancer 成功覆盖 bundled adapter：

```bash
grep 'Mattermost Approval Plugin registered' ~/.hermes/logs/gateway.log
```

日志应显示 enhancer 的广告语而非 bundled 的 `"Mattermost adapter registered"`。

### 6. MAX_MESSAGE_LENGTH 配置验证

两个位置需一致：
- Bundled adapter `register()`: `max_message_length=MAX_POST_LENGTH` (4000)
- Enhancer adapter 类: `MAX_MESSAGE_LENGTH = MAX_POST_LENGTH` (4000)
- Enhancer `register_platform()`: `max_message_length=MAX_POST_LENGTH` (4000)

原因：`stream_consumer.py` 通过 `getattr(adapter, "MAX_MESSAGE_LENGTH", 4096)` 读取 adapter 类属性，不走 registry；而 registry 值是冗余防护。
