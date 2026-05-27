# P53：幽灵代码围栏导致消息内容消失

## 症状

用户在 Mattermost 中看到一条多方案消息，方案 A、C、D 正常但方案 B 的内容和标题「消失了」——不是被拆到另一条帖子里，而是在同一条帖子中内容不完整。具体表现为：

- 方案 A 标题和内容正常
- 方案 B 的 CSS 代码块正常、优缺点文字正常，但 **`#### 🥈 方案 B：...` 标题被渲染为纯文本**（不像是标题）
- 方案 C/D 后续内容正常

## 根因（纠正于 2026-05-27）

> ⚠️ **初版诊断有误**。初始分析认为是 "short-circuit 路径未 prepend prefix"，但实际 bug 是相反的 —— prefix **确实被 prepend 了**，但原始内容中紧接其后的 ` ``` ` 立即将其闭合，产生幽灵空块。

`BasePlatformAdapter.truncate_message()` 的代码块 carry-over 机制：

1. Chunk 1 在 fenced code block 内被截断 → 正确检测到 `in_code=True`，设置 `carry_lang="python"`
2. Chunk 1 末尾追加 `\n``` ` 闭合围栏
3. Chunk 2 循环时 `carry_lang` 仍然为 `"python"` → 正确 `prefix = "```python\n"`
4. **Bug**：此时 `remaining` 的开头就是原始内容中的闭合 ` ``` `（因为上一轮 split 正好切在闭合围栏之前）：
   ```
   prefix = "```python\n"
   remaining = "```\nsome content\n..."
   ```
5. Chunk 2 的完整内容变成 ` ```python\n```\nsome content` — 前两行构成一个**幽灵空代码块**
6. Chunk 2 后续正常处理会检测到 `in_code=False`（围栏已闭合），不追加额外闭合围栏
7. 幽灵空块本身无害（空内容），但如果 `remaining` 在触发 short-circuit 前**同时包含**幽灵块和后续内容，CommonMark 解析时幽灵块后的内容不受影响

### 真正的危害场景

当幽灵空前缀 + 剩余内容触发 short-circuit（line 4161）时：
```python
if _len(prefix) + _len(remaining) <= max_length - INDICATOR_RESERVE:
    chunks.append(prefix + remaining)  # "```python\n```\nsome content..."
    break
```
Chunk 2 = ` ```python\n```\nsome content... (2/2)` — 幽灵空块 + 内容。

**更严重的情况**：如果 `remaining` 头部就是 ` ``` ` 但后续没有另一个 ` ``` ` 来重新开启 → 后续内容（如 markdown 标题）被吞入幽灵块的开围栏中，渲染为纯文本。

### 修复（已应用于 base.py）

在 while 循环中，判断前缀之前先检测：**如果 `carry_lang` 不为 None 且 `remaining` 首行就是 bare ` ``` `**，说明这是原始内容的闭合围栏，不应重新打开：

```python
if carry_lang is not None:
    stripped_line = remaining.lstrip().split("\n", 1)[0].rstrip()
    if stripped_line.startswith("```") and not stripped_line[3:].strip():
        # 首行是 bare ``` — 消费它，不重新打开围栏
        idx = remaining.index("```")
        remaining = remaining[idx + 3:]
        if remaining.startswith("\n"):
            remaining = remaining[1:]
        remaining = remaining.lstrip()
        carry_lang = None
        continue
```

已注册为 `hermes-patches.sh` P53。

## 复现条件

- `MAX_POST_LENGTH` 较小（如 4000）
- 消息包含 fenced code block（```scss 等）
- 截断点落在 code block 内部
- 剩余内容 + prefix 的长度在 max_length 范围内（触发 short-circuit）
- 幽灵围栏吞掉的内容中包含 markdown 格式化元素（标题、粗体等）

## 诊断方法

### 1. 通过 Mattermost API 拉取原始消息

```python
import json, urllib.request

thread_id = "xxx"
url = f"http://127.0.0.1:8065/api/v4/posts/{thread_id}/thread?per_page=80"
req = urllib.request.Request(url, headers={
    "Authorization": "Bearer MATTERMOST_TOKEN"
})
data = json.loads(urllib.request.urlopen(req).read())
```

### 2. 逐行检查消息结构

关注：
- 消息开头是否有 code fence 前缀（如 ````scss`）
- 消息中是否有孤立的 ` ``` `（行首，前后无配对）
- 孤立的 ` ``` ` 之后的内容在 Mattermost 中是否渲染为代码

### 3. 判断标准

| 信号 | 含义 |
|------|------|
| API 返回的消息开头无 fence，直接是 4-space 缩进 | short-circuit 路径被触发但 carry-over 未生效 |
| 消息中某行 ` ``` ` 前后缺少配对 | 幽灵围栏确认 |
| 幽灵围栏后的 `**text**` / `#### heading` 渲染为纯文本 | 内容被吞 |

## 修复方向

**根本修复**：确保 `truncate_message()` 的 short-circuit 路径正确 prepend `prefix`。

**规避方案**：提高 `MAX_POST_LENGTH` 到接近 Mattermost 服务器上限（16383），避免不必要的分片。大多数消息（<16000 字符）根本不会触发 truncate_message 分片。

## 错误诊断清单

当用户报告「消息内容消失」时，按以下顺序排查：

1. ✅ 先通过 API 取证，确认原始消息内容
2. ✅ 检查是否多 chunk 分片导致内容分散
3. ✅ 逐行检查 markdown 结构，寻找幽灵围栏
4. ❌ 不要直接假设是 MAX_POST_LENGTH 导致的分片/折叠问题
5. ❌ 不要在确认根因之前修改代码

## 源码位置

- `gateway/platforms/base.py` line 3617-3746: `truncate_message()` 静态方法
- `gateway/platforms/mattermost.py` line 37: `MAX_POST_LENGTH` 常量
- `plugins/mattermost-enhancer/adapter.py` line 1256: 插件侧调用 truncate_message
