# P53：幽灵代码围栏导致消息内容消失

## 症状

用户在 Mattermost 中看到一条多方案消息，方案 A、C、D 正常但方案 B 的内容和标题「消失了」——不是被拆到另一条帖子里，而是在同一条帖子中内容不完整。具体表现为：

- 方案 A 标题和内容正常
- 方案 B 的 CSS 代码块正常、优缺点文字正常，但 **`#### 🥈 方案 B：...` 标题被渲染为纯文本**（不像是标题）
- 方案 C/D 后续内容正常

## 根因

`BasePlatformAdapter.truncate_message()` 的代码块 carry-over 机制在特定条件下失效：

1. Chunk 1 在 fenced code block 内被截断 → 正确检测到 `in_code=True`，设置 `carry_lang="scss"`
2. Chunk 2 的剩余内容触发 short-circuit 路径（line 3666-3668）：
   ```python
   if _len(prefix) + _len(remaining) <= max_length - INDICATOR_RESERVE:
       chunks.append(prefix + remaining)
       break
   ```
3. **Bug**：short-circuit 路径应该将 `prefix`（如 `"```scss\n"`）prepend 到 chunk 2 开头，但实际交付的消息开头缺失了 code fence
4. 缺少开启围栏 → Chunk 2 中 Chunk 1 末尾的闭合 ` ``` ` 在 CommonMark 解析器中变成**新的开启围栏**（幽灵围栏）
5. 幽灵围栏之后、下一个 ` ``` ` 之前的所有内容（包括 `#### 🥈 方案 B` 标题）被吞入代码块，渲染为纯文本

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
