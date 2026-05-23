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

## P4: `_do_patch` 调用放在函数外导致脚本启动失败

**现象：** `./hermes-patches.sh check` 报 `_do_patch: command not found`，脚本根本跑不起来。

**根因：** `_do_patch` 函数定义在脚本靠后位置（~L124），但某个 patch 的 `_do_patch` 调用被误放在 `apply_all` 函数**之外**、在 `_do_patch` 定义**之前**（脚本顶层）。Bash 逐行执行，遇到调用时函数还没定义。

**修复：** 将游离的 `_do_patch` 调用移入 `apply_all` 函数体内部。

**检测方法：** 在 `apply_all() {` 之后和 `}` 之前的 `_do_patch` 调用是正确的；在 `show_status() {` 之前或 `_do_patch()` 定义之前的调用是错误的。

## P5: 注册表 check_grep 与实际文件内容不匹配

**症状 A — 中文匹配 Python 源码：** check_grep 使用中文字符串（如 `兜底分支`），但目标文件是 Python 源码，永远匹配不到 → `check` 永远显示 ✗，即使补丁已生效。check_grep 必须使用**目标文件实际包含的字符**。

**症状 B — 标签错配：** 同一注册表项中 label 描述的是 A 补丁，但 check_grep 是 B 补丁的匹配模式 → 两个补丁状态互相干扰。

**修复原则：**
1. check_grep 必须取自补丁**生效后**目标文件中**确定存在**的唯一字符串
2. 注册表每项对应一个补丁，label 和 check_grep 必须属于同一补丁
3. 新增补丁后立即跑 `check` 验证

## P6: Byte 级 patch 因上游代码演进失效（静默跳过）

**现象：** `hermes-patches.sh apply` 时某补丁永远输出 `SKIP`，但目标文件确实需要修复。

**根因：** Patch 使用 Python bytes 精确匹配（如 `b'|\\$)|\\\\\\\\S+)'`），上游代码重构后目标字符串的 exact bytes 发生变化（引号转义方式、换行位置、变量名、regex 结构等），导致 `old in raw` 永远为 `False`。

**检测方法：**
```bash
# 提取 patch 中的 old 模式，在目标文件中搜索
python3 -c "
with open('target_file.py', 'rb') as f:
    raw = f.read()
print(b'<old_pattern>' in raw)
"
```

**预防：** 优先使用**字符串级匹配**（`open(file, 'r')` + `old in content`）而非 byte 级匹配。字符串匹配对缩进/换行的容忍度更高，且可以加注释说明匹配意图。

**⚠️ 注意：** 从 byte 级改为字符串级 patch 时，转义规则不同。Byte pattern 中的 `\\\\\\\\S` (4 个反斜杠在 Python bytes 字面量中) 对应文件中的 `\\S` (2 个字符)，但字符串 pattern 中只需写 `\\S`（Python 自动处理）。建议用 `repr()` 打印目标内容确认。
