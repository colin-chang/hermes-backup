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

1. [ ] 在 `_patch_registry` 中添加注册表项（`file|label|check_grep`）
2. [ ] 在 `apply_all()` 函数内添加 `_do_patch` 调用（**确认在函数体内，不在顶层**）
3. [ ] check_grep 是补丁**引入的新字符串**（不是补丁移除的旧字符串），且在文件中确实存在
4. [ ] 运行 `./hermes-patches.sh check` 验证新增项显示 ✅
5. [ ] 如果同一文件已有补丁，check_grep 不与已有项冲突

## 当前补丁清单（2026-05-23）

| # | 文件 | 标签摘要 | check_grep |
|---|------|---------|-----------|
| 1 | `hermes_cli/providers.py` | 自定义 provider 聚合器识别 | `startswith.*"custom:"` |
| 2 | `hermes_cli/doctor.py` | doctor 假阳性修复 | `startswith.*"custom:"` |
| 3a | `hermes_cli/model_switch.py` | 模型白名单优先 | `and not models_list` |
| 3b | `hermes_cli/model_switch.py` | custom_providers 白名单 | `if not grp\["models"\]` |
| 4a | `gateway/config.py` | 重启通知桥接 | `"gateway_restart_notification" in platform_cfg` |
| 4b | `gateway/config.py` | extra fallback 读取 | `extra.*gateway_restart_notification` |
| 5 | `cron/jobs.py` | Cron 中文修复 | `ensure_ascii=False` |
| 9 | `utils.py` | YAML 中文写入 | `allow_unicode=True` |
| 10a | `gateway/run.py` | MEDIA 正则收紧 | `_TOOL_MEDIA_RE` |
| 10b | `gateway/platforms/base.py` | MEDIA 兜底移除 | `|\\$))` |
| 11/P38 | `gateway/platforms/mattermost.py` | Thread root_id fallback | `_raw_root = post.get` |
| P46 | `gateway/run.py` | Clarify Session 分裂 | `_canonical_entry = self.session_store.get_or_create_session` |
| P46b | `gateway/run.py` | Clarify concurrency guard | `Gateway intercepted clarify at session guard` |
