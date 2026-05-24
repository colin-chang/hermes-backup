# Runtime Footer 内联渲染

> **记录日期：2026-05-24 | 实现状态：✅ 已上线**

## 问题

`display.runtime_footer` 开启后，Mattermost 中 footer **以独立消息出现**，而非内嵌在回复底部。

## 根因

Hermes Gateway 对 footer 有**两条代码路径**（`gateway/run.py`）：

| 路径 | 条件 | 行为 | 效果 |
|------|------|------|------|
| 非流式 | `not agent_result.get("already_sent")` | 拼接到 response 正文末尾 | 同一条消息 ✅ |
| 流式 | `already_sent == True` | 单独调用 `adapter.send()` | 独立消息 ❌ |

源码：

```python
# gateway/run.py:7876 — 非流式路径
if _footer_line and response and not agent_result.get("already_sent"):
    response = f"{response}\n\n{_footer_line}"

# gateway/run.py:8092 — 流式路径
if _footer_line:
    await _foot_adapter.send(source.chat_id, _footer_line, metadata=...)
```

注释写明："streaming already delivered the body, we can't mutate the sent text, so we fire a separate trailing send below"

Mattermost 配置了 `display.platforms.mattermost.streaming: true`，走流式路径。

## Footer 格式

`gateway/runtime_footer.py` 的 `format_runtime_footer()`：
```
_SEP = " · "
```
输出示例：`deepseek/deepseek-v4-pro · 34%`（单行纯文本，无 Markdown）

## 解决方案：插件拦截 → 编辑上一条消息

在 `mattermost-enhancer` 插件 `adapter.py` 的 `send()` 中实现。

### 追踪字典（`__init__`）

```python
self._tracked_posts: Dict[str, Tuple[str, str]] = {}  # chat_id → (post_id, content)
```

### Footer 检测

```python
@staticmethod
def _is_footer_line(content: str) -> bool:
    if "\n" in content or len(content) > 120:
        return False
    if " · " not in content:
        return False
    return True
```

### 拦截（`send()` 开头） — 编辑上一条消息

```python
if self._is_footer_line(content):
    tracked = self._tracked_posts.get(chat_id)
    if tracked:
        post_id, _prev_content = tracked
        # 实时拉取当前帖子内容（流式模式下 send() 收到的 content 不完整）
        current = await self._api_get(f"posts/{post_id}")
        current_text = current.get("message", "") if isinstance(current, dict) else ""
        if current_text:
            footer_text = content.replace(" · ", " ")
            footer_md = f"`── {footer_text} ──`"
            edited = f"{current_text}\n\n{footer_md}"
            result = await self._api_put(f"posts/{post_id}", {
                "id": post_id, "message": edited,
            })
            if result and result.get("id"):
                self._tracked_posts[chat_id] = (post_id, edited)
                return SendResult(success=True, message_id=post_id)
        logger.warning(...)
    # 无追踪或失败 → 降级正常发送
```

### Mattermost Markdown 样式约束

Mattermost **不支持自定义 CSS/颜色/字号**。实现「灰色小字脚注」的唯一可靠方案是 **inline code** `` ` ``：
- 等宽字体天然小于正文
- 灰色背景 + 略暗文字色 → 视觉上低调不抢眼
- 其他尝试过的方案：
  - 斜体 `*text*` — 仅倾斜，颜色/字号不变 ❌
  - HTML `<span style="...">` — Mattermost 剥离 ❌
  - 引用 `>` — 缩进+竖线，不适合脚注 ❌

### 效果

```
── `deepseek-v4-pro 34%` ──
```

整行包裹在 inline code 中，外观统一为灰色等宽小字脚注。注意：`runtime_footer.py` 的 `_model_short()` 已剥离 vendor 前缀（`deepseek/deepseek-v4-pro` → `deepseek-v4-pro`）。

### 追踪（`send()` 末尾）

```python
if last_id and not self._is_footer_line(content):
    self._tracked_posts[chat_id] = (last_id, content)
```

### 效果对比

```
之前：                         之后：
┌──────────────┐              ┌──────────────────────┐
│ 正文回复     │              │ 正文回复             │
└──────────────┘              │                      │
┌──────────────┐              │ ── deepseek-v4-pro 34% ── │  ← 灰色等宽脚注
│ model · 34%  │ ← 独立消息    └──────────────────────┘
└──────────────┘                    ↑ 同一条消息内
```

### 边界

| 场景 | 行为 |
|------|------|
| Footer 是第一条消息 | 降级正常发送 |
| 消息 split 为多 chunk | 追踪最后 chunk，footer 追加到末 chunk |
| 编辑 API 失败 | 降级正常发送 |
| 多 channel 并发 | `_tracked_posts` 按 `chat_id` 隔离 |

### 降级

编辑失败 → footer 回退独立发帖。安全降级：宁可格式不佳，不丢 footer。
