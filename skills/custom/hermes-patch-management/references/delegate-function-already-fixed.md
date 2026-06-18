# 委托函数已包含修复 — P5A 案例研究

## 背景

- 日期: 2026-06-17
- Hermes 版本: v2026.6.5-1117
- 涉及 patch: Mattermost Enhancer P5A (_progress_thread_id 路由)
- 上游 commit: `_resolve_progress_thread_id()` 函数提取

## 现象

双重验证显示 A=0, B=NO：
- 维度 A（check pattern）：在上游不命中（这是 patch 插入的 pattern）
- 维度 B（old_string）：old_string 不在 origin/main 中

初步印象：patch 需要重写。

## 关键判断步骤

### 1. 确认 old_string 为何消失

```bash
cd ~/.hermes/hermes-agent
git show origin/main:gateway/run.py | grep -B2 -A5 '_progress_thread_id'
```

上游将原来的 if/else 块替换为单一函数调用：

```python
# 旧代码（P5A old_string 目标）
if source.platform == Platform.SLACK:
    _progress_thread_id = source.thread_id or event_message_id
else:
    _progress_thread_id = source.thread_id

# 新代码
_progress_thread_id = _resolve_progress_thread_id(
    source.platform, source.thread_id, event_message_id,
)
```

### 2. 找到提取出的新函数

```bash
git show origin/main:gateway/run.py | grep -A10 'def _resolve_progress_thread_id'
```

### 3. 阅读新函数实现

```python
def _resolve_progress_thread_id(platform, source_thread_id, event_message_id):
    if source_thread_id:
        return str(source_thread_id)
    if platform_key in {"slack", "mattermost"} and event_message_id:
        return str(event_message_id)
    return None
```

### 4. 比较与原始 patch 的等价性

| 维度 | P5A 原始修复 | 上游实现 |
|------|------------|---------|
| 目标平台 | `Platform.MATTERMOST` | `"mattermost"`（含 `"slack"`） |
| 条件 | `not source.thread_id and event_message_id` | `event_message_id`（source_thread_id 提前返回） |
| 返回值 | 直接赋值 `event_message_id` | `str(event_message_id)` |

上游 `source_thread_id` 存在时提前返回（L409-410），等价于 `not source.thread_id` 守卫。**功能等价。**

### 5. 结论

**patch 可以直接移除** — 上游委托函数已包含等价修复。

## 与案例 C 的区别

| | 案例 C（MiniMax） | 案例 D（P5A） |
|---|---|---|
| 委托函数是否包含修复 | ❌ 未包含 | ✅ 已包含 |
| 动作 | 迁移 patch 到委托函数内部 | 移除 patch |
| 判断方法 | 读委托函数 → 确认缺失 → 添加 | 读委托函数 → 确认已存在 → 移除 |

## 通用检查清单

当维度 B 失败且发现上游提取了委托函数时：

- [ ] 找到新函数调用点：`git show origin/main:<file> | grep -B2 -A5 '新函数名('`
- [ ] 定位函数定义：`grep -A15 'def 新函数名'`
- [ ] 逐条件对比：patch 修复了哪些条件？新函数覆盖了哪些条件？
- [ ] 判断等价性：等价 → 移除 patch；缺漏 → 迁移 patch 到新函数内部
