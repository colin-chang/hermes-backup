# Patch 工具陷阱（Shell 脚本 + 大块删除）

> 关联：`mattermost-operations` skill
> 创建：2026-05-22 | 来源：移除 `hermes-patches.sh` patches 7a-7d 时的实操经验

## P1: Shell 脚本大块删除导致文件损坏

**现象：** 使用 `patch` 工具的 `mode='replace'` 从 shell 脚本中删除 ~500 行代码块时，`old_string` 匹配了 15 行后就停止，剩余 Python 代码裸露在 bash 中，导致整个文件语法损坏。

**根因：** `patch` 工具的模糊匹配策略在遇到 heredoc 语法（`<<'PYEOF'` … `PYEOF`）、转义引号（`\\"`）、或 bash 特有的转义序列时，匹配提前终止。`old_string` 包含的字符与文件中的实际字符在序列化/反序列化过程中产生偏移。

**修复步骤：**
```bash
# 1. 立即用 git 恢复文件
git checkout scripts/hermes-patches.sh

# 2. 用 execute_code 做精确行级删除
```

`execute_code` 脚本模板：
```python
with open('target.sh') as f:
    lines = f.readlines()

# 用内容标记定位边界（非行号）
start_line = None
end_line = None
for i, line in enumerate(lines):
    if "── 7. <section header>" in line:
        start_line = i
    if start_line is not None and "── 8. <next section header>" in line:
        end_line = i
        break

# 精确切片删除
del lines[start_line:end_line]

# 清理多余空行
# ...

with open('target.sh', 'w') as f:
    f.writelines(lines)
```

**优先级规则：** shell 脚本中删除 >50 行时，**禁止使用 `patch` 工具**，必须用 `execute_code`。

## P2: f-string 花括号触发 escape-drift

**现象：** `patch` 工具报 `Escape-drift detected: old_string and new_string contain the literal sequence '\\"'`

**根因：** Python f-string 中的 `{variable}` 花括号在工具调用序列化时被误解释。工具认为花括号是参数替换标记。

**修复：** 用 `read_file` 确认文件中的确切文本，然后用脚本重写整个文件（`write_file`），或分小块 patch。

## P3: `ast.walk` 漏掉异步函数

**现象：** `isinstance(node, ast.FunctionDef)` 只匹配同步函数，漏掉所有 `async def`。

**正确写法：**
```python
isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef))
```
