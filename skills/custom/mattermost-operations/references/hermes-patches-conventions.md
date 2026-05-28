# hermes-patches.sh 编写规范与已知 Pitfall

> 本文档记录 `hermes-patches.sh` 的编写约定和已踩过的坑，确保新增补丁时不重蹈覆辙。

## 脚本结构

```
_patch_registry=( ... )      # 注册表：check 用
_do_patch() { ... }          # 补丁执行函数
apply_all() { ... }          # 所有 _do_patch 调用
show_status() { ... }        # 从注册表读取，一一 grep
```

## Pitfall 1：`_do_patch` 必须放在 `apply_all()` 函数体内

❌ **错误做法** — 补丁代码放在脚本顶层（函数外）：

```bash
# 辅助函数
# ...

    # ── P46b: Clarify concurrency guard  ──
    _do_patch "gateway/run.py" \
        "Clarify concurrency guard" \
        'check pattern' <<'PYEOF'
    ...
    PYEOF

_do_patch() { ... }
```

这会导致 `_do_patch: command not found`，因为顶层代码在函数定义之前执行。

✅ **正确做法** — 补丁代码放在 `apply_all()` 函数内，紧跟相关补丁之后：

```bash
apply_all() {
    # ── P46: Clarify Session 分裂 ──
    _do_patch "gateway/run.py" ... <<'PYEOF'
    ...
    PYEOF

    # ── P46b: Clarify concurrency guard ──
    _do_patch "gateway/run.py" ... <<'PYEOF'
    ...
    PYEOF
}
```

## Pitfall 2：注册表 check_grep 必须能匹配到文件内容

`show_status()` 对每个注册表项执行 `grep -q "$check" "$file"`。

- ✅ `startswith.*"custom:"` — 存在于 Python 源码
- ✅ `_canonical_entry = self.session_store.get_or_create_session` — 存在于 Python 源码
- ❌ `兜底分支` — 中文字符串，在 Python 源文件中永远匹配不到 → 永远显示 ✗

**特别说明：base.py 的 MEDIA 正则收紧补丁（已修复 2026-05-23）**

原始补丁使用二进制替换 `b'|\\$)|\\\\S+)' → b'|\\$))'`，但上游代码演进后 `extract_media()` 中正则结构已变化——旧 byte pattern 不再匹配。经诊断确认补丁**实际未生效**（文件中仍存在 `|\S+` 兜底分支）。

**修复方案：**
- Patch 逻辑改为字符串匹配（`read('r')` + `replace()`），适配当前源码结构
- check_grep 改为 `|\\$))`（bash escaping: `\\\\$))` → grep 接收 `|\$))` → 匹配 patched 状态的 `|$))`）

**验证方法（已过时，保留供参考）：**
```python
with open('gateway/platforms/base.py', 'rb') as f:
    raw = f.read()
if b'|\\$)|\\\\S+)' in raw:
    print('NOT APPLIED')
else:
    print('APPLIED')
```

## Pitfall 3：同一文件多个补丁 → 注册表必须一一对应

如果对 `gateway/run.py` 打了两个补丁（P46 + P46b），注册表必须有两条独立记录：

```bash
_patch_registry=(
    ...
    "gateway/run.py|P46: Session 分裂修复|_canonical_entry = self.session_store.get_or_create_session"
    "gateway/run.py|P46b: Concurrency guard|Gateway intercepted clarify at session guard"
)
```

每个 check_grep 必须唯一且只匹配自身补丁。P46 的 check_grep 被 P46 消费后，P46b 必须使用不同的 pattern。

## Pitfall 5：check_grep 含 `$` 时的 bash 转义陷阱

当 check_grep 需要匹配 `|$))` 这种含 `$` 的字符串时，必须经过**两层转义**才能让 `grep` 正确匹配：

1. **bash 双引号层**：注册表字符串 `"...|\\\\$))"` 中：
   - `\\\\` → bash 处理 → `\\`
   - `\\$` → bash 处理 → `\$`
   - 变量值 = `|\\$))`

2. **grep 调用层**：`grep -q "$check"` 中：
   - bash 再次处理双引号：`\\` → `\`，`\$` → `$`
   - grep 收到 `|\$))`
   - grep 中 `\$` 匹配字面 `$` → 匹配到 `|$))` ✅

**完整链路**：源码 `\\\\$` → bash 第一遍 → 变量 `\\$` → bash 第二遍 → grep pattern `\$` → 匹配字面 `$`。

❌ 只写 `\\$` → 变量值 `\$` → grep 收到 `$`（EOL）→ 匹配失败。
❌ 写 `$` → bash 变量展开 → 空/报错。

**验证方法**：`echo "$check" | cat -v` 查看实际字符。应为 `|$))`。

## Pitfall 6：check_grep 跨行匹配需用 `ML:` 前缀

`grep` 默认按行匹配，无法跨行搜索。当补丁引入的代码跨越两行时（如函数调用参数列表中插入新参数），普通 `grep -q` 会失败。

新增 `ML:` 前缀支持：在 `_patch_registry` 中以 `ML:` 开头，`_do_patch()` 和 `show_status()` 自动切换为 `python3 -c "import re; re.search(pattern, content)"` 跨行匹配。

```bash
# ❌ 普通 grep — 跨行匹配失败
"gateway/stream_consumer.py|P55: fallback reply_to|content=chunk,\\n.*reply_to=self._initial_reply_to_id"

# ✅ ML: 前缀 — python3 re.search 跨行匹配
"gateway/stream_consumer.py|P55: fallback reply_to|ML:content=chunk,\\n.*reply_to=self._initial_reply_to_id"
```

注意：
- `ML:` 模式中使用 `\\n` 表示换行（bash 层转义后传给 python 的 `\n`）
- `.*` 匹配换行符（`re.search` 默认 `.` 不匹配 `\n`，但 `\\n` 在模式中显式写为字面换行即可）

1. [ ] 在 `_patch_registry` 中添加注册表项（`file|label|check_grep`）
2. [ ] 在 `apply_all()` 函数内添加 `_do_patch` 调用（**确认在函数体内，不在顶层**）
3. [ ] check_grep 是补丁**引入的新字符串**（不是补丁移除的旧字符串），且在文件中确实存在
4. [ ] 运行 `./hermes-patches.sh check` 验证新增项显示 ✅
5. [ ] 如果同一文件已有补丁，check_grep 不与已有项冲突

## 当前补丁清单（2026-05-29）

| # | 文件 | 标签摘要 | check_grep | 上游状态 |
|---|------|---------|-----------|---------|
| 1 | `hermes_cli/providers.py` | 自定义 provider 聚合器识别 | `startswith.*"custom:"` | 待提交 |
| 2 | `hermes_cli/doctor.py` | doctor 假阳性修复 | `startswith.*"custom:"` | 待提交 |
| 3a | `hermes_cli/model_switch.py` | 模型白名单优先 | `and not models_list` | 待提交 |
| 3b | `hermes_cli/model_switch.py` | custom_providers 白名单 | `if not grp\["models"\]` | 待提交 |
| 4a | `gateway/config.py` | 重启通知桥接 | `"gateway_restart_notification" in platform_cfg` | 待提交 |
| 4b | `gateway/config.py` | extra fallback 读取 | `extra.*gateway_restart_notification` | 待提交 |
| 5 | `cron/jobs.py` | Cron 中文修复 | `ensure_ascii=False` | 待提交 |
| 9 | `utils.py` | YAML 中文写入 | `allow_unicode=True` | 待提交 |
| 10a | `gateway/run.py` | MEDIA 正则收紧 | `_TOOL_MEDIA_RE` | 待提交 |
| 10b | `gateway/platforms/base.py` | MEDIA 兜底移除 | `|\\$))` | 待提交 |
| P50 | `gateway/stream_consumer.py` | 评论→正文合并 | `Accumulate commentary` | 待提交 |
| P53 | `gateway/platforms/base.py` | 幽灵代码围栏 | `reopening the fence would create` | 待提交 |
| P54 | `plugins/platforms/mattermost/adapter.py` | WebSocket 心跳 30→15s | `heartbeat=15.0` | 待提交 |
| P55 | `gateway/stream_consumer.py` | stream fallback 缺 reply_to | `reply_to=self._initial_reply_to_id` | [PR #33335](https://github.com/NousResearch/hermes-agent/pull/33335) |
| P56 | `plugins/platforms/mattermost/adapter.py` | _api_put 缺 timeout | `timeout=aiohttp.ClientTimeout(total=30)` | [PR #33335](https://github.com/NousResearch/hermes-agent/pull/33335) |
| P57 | `gateway/run.py` | 工具进度消息不在Thread中：Mattermost不应要求source.thread_id | `or source.platform == Platform.MATTERMOST` | 待提交 |

**注**：P38/P46/P46b 已迁入 `mattermost-enhancer` 插件或已合并，不再存在于 `hermes-patches.sh`。

## Pitfall 6：上游"修复"不完整 — 删除本地 patch 前必须验证语义

**血泪教训（P57）**：`hermes-mattermost-enhancer.sh` 的 Patch 2（progress→thread）在 commit `73439a4` 中被删除，理由是"Hermes v0.14.0 上游已修复"。但上游修复是不完整的：

```python
# 上游 v0.14.0（有 Bug — source.thread_id 在 Channel 根消息时为 None）
_progress_reply_to = (
    event_message_id
    if source.platform in (Platform.FEISHU, Platform.MATTERMOST) 
       and source.thread_id    # ← 问题在这！Channel 根消息时为 None
       and event_message_id
    else None
)

# 正确修复（对 Mattermost 不要求 source.thread_id）
_progress_reply_to = (
    event_message_id
    if (
        (source.platform == Platform.FEISHU and source.thread_id)
        or source.platform == Platform.MATTERMOST   # ← 不要求 thread_id
    ) and event_message_id
    else None
)
```

上游"修了"但保留了 `source.thread_id` 条件，而 Mattermost 的 Thread 是 Hermes 回复时才创建的——用户在 Channel 根级别发消息时 `source.thread_id` 始终为 None，所以修复对 Channel→Thread 场景完全无效。

**验证方法**（删除本地 patch 前必做）：
1. 在源码中确认上游修复的条件分支覆盖了所有本地 patch 覆盖的场景
2. 至少做一次端到端测试（特别是本地 patch 专门处理的边界场景）
3. 不止看 changelog/commit message，要看实际代码变更

**安全策略**：如果无法确认上游修复的完整性，宁可保留本地 patch（带 `else: SKIP` 幂等检测），也不要贸然删除。
