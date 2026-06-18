# 假阳性案例：`not grp["models"]` 误判

## 背景

`hermes-patches.sh` 的 patch 3b 修改 `hermes_cli/model_switch.py` 中 custom_providers 的
模型探测逻辑：

```python
# 上游原始（有 Bug）
should_probe = bool(api_url) and (bool(api_key) or not grp["models"])

# Patch 后（修复）
should_probe = bool(api_url) and bool(api_key) and not grp["models"]
```

## 假阳性

旧 check pattern `not grp\["models"\]` 在上游原始代码中 grep 命中（因为 upstream 也有
`not grp["models"]` 子串），导致 `check` 命令在**未应用 patch 的情况下显示为已修复**。

## 验证

```bash
cd ~/.hermes/hermes-agent

# 回滚到上游
git checkout hermes_cli/model_switch.py

# 旧 pattern（假阳性）
grep -q 'not grp\["models"\]' hermes_cli/model_switch.py && echo "MATCH (FALSE POSITIVE)"

# 新 pattern（正确）
grep -q 'bool.*api_key.*and not grp\["models"\]' hermes_cli/model_switch.py || echo "NO MATCH (correct)"
```

## 修复

Check pattern 收紧为：`bool.*api_key.*and not grp\["models"\]`

## 教训

任何 check pattern 在投入使用前，必须对上游原始代码做**零匹配验证**。
