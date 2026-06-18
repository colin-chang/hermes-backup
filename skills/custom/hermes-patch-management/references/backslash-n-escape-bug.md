# `\\n` Escape Bug — P3 Case Study

> 发现日期: 2026-06-08
> 修复: `hermes-mattermost-enhancer.sh` P3 改为三引号字符串

## 症状

`_do_patch()` 报告 `SKIP`（code already matches），但 `check_status()` 的 grep 显示 check pattern 未命中。同一脚本中的其他 4 个 patch 均正常 apply。

## 双重验证发现

执行维度 B 验证时，用文件中转方式检查 `old_string`：

```bash
git show origin/main:gateway/run.py > /tmp/_check.py
python3 <<'PYEOF'
with open('/tmp/_check.py') as f:
    content = f.read()
# 从脚本 heredoc 中提取的 old
old = "        session_key = session_entry.session_key\\n        self._cache_session_source(session_key, source)"
print('YES' if old in content else 'NO')
PYEOF
```

输出 `NO` — 但用三引号方式验证却输出 `YES`：

```python
old = """        session_key = session_entry.session_key
        self._cache_session_source(session_key, source)"""
print('YES' if old in content else 'NO')
# → YES
```

## 根因

Patch 脚本的 Python heredoc（`<<'PYEOF'`）中使用了双引号字符串 + `\\n`：

```python
# ❌ 错误 — \\n 是字面量两个字符 \ + n
old = "        session_key = session_entry.session_key\\n        self._cache_session_source(session_key, source)"
```

在 Python 中，双引号内的 `\\n` 是转义序列，产生两个字符 `\` (0x5c) + `n` (0x6e)。而目标文件 `run.py` 中两个代码行之间是真实换行符 `\n` (0x0a)。因此 `old in content` 永远为 `False`。

## 影响

- **P3（Clarify 并发守护）从未真正 apply 成功**
- `_do_patch()` 检测到 Python 脚本输出 `SKIP`（old not in content），误判为"代码已符合预期"
- `check_status()` 的 grep 正确显示 check pattern 未命中（即 patch 未生效）
- **维度 B 验证必须用文件中转 + 三引号字符串**，否则也会产生相同的假阴性

## 修复

将 `old` 和 `new` 全部改为三引号字符串：

```python
# ✅ 正确 — 三引号内嵌真实换行符
old = """        session_key = session_entry.session_key
        self._cache_session_source(session_key, source)"""

new = """        session_key = session_entry.session_key
        # Belt-and-suspenders clarify check using the canonical session
        # key. ...
        if session_key != _quick_key:
            ...
        self._cache_session_source(session_key, source)"""
```

## 教训

1. **所有 Python heredoc 中的多行字符串一律使用三引号**，禁止双引号 + `\\n`
2. **维度 B 验证必须用文件中转方式**（先 `git show` → 临时文件 → Python heredoc 读取），不能靠 `python3 -c` 管道——否则也会因 `\\n` 转义产生假阴性
3. **维度 B 是三引号方式**——验证代码本身也应使用三引号嵌入真实换行符
4. 同一脚本中，P1/P2/P4/P5 使用了三引号而 P3 例外——**审查代码时应检查风格一致性**
