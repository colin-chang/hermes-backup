# Runtime Footer 拦截 → 编辑合并模式

> 日期：2026-05-24 | 插件：mattermost-enhancer v2.2.0

## 问题

Hermes Gateway 在流式模式下，`runtime_footer` 作为**独立消息**发送（`gateway/run.py:8092`），因为正文已通过 WebSocket 实时推送，Gateway 无法回溯修改。Mattermost 中表现为 footer 是一条单独的帖子，而非脚注。

## 解决方案

在插件的 `send()` 方法中拦截 footer 消息，改用 Mattermost `PUT /api/v4/posts/{post_id}` API **编辑上一条 Bot 帖子**，将 footer 追加到消息末尾。

### 实现要点

**1. Footer 检测**

Footer 由 `gateway/runtime_footer.py` 的 `format_runtime_footer()` 生成，特征：
- 单行（无 `\n`）
- 含 ` · ` 分隔符（`_SEP = " · "`）
- 长度 < 120 字符
- 纯文本，无 Markdown 格式字符

```python
@staticmethod
def _is_footer_line(content: str) -> bool:
    if "\n" in content or len(content) > 120:
        return False
    if " · " not in content:
        return False
    return True
```

**2. 帖子追踪**

在 `__init__` 中维护 `_tracked_posts: Dict[str, Tuple[str, str]]`，key 为 `chat_id`，value 为 `(post_id, content)`。非 footer 消息发送成功后更新追踪。

**3. 编辑合并**

Footer 到达时：
1. 从 `_tracked_posts` 查找上一条帖子
2. 通过 `_api_get(f"posts/{post_id}")` **实时拉取**当前内容（流式模式下 `send()` 收到的 `content` 不完整）
3. 拼接 footer 后 `_api_put(f"posts/{post_id}", {"id": post_id, "message": edited})`

**4. 降级策略**

- 无追踪帖子 → 回退为正常 `_api_post` 发送
- `PUT` 请求失败 → 回退为正常发送
- API 拉取内容失败 → 回退为正常发送

### 格式化

```python
footer_text = content.replace(" · ", " ")  # "deepseek-v4-pro 34%"
footer_md = f"`── {footer_text} ──`"       # inline code = 灰色小字
edited = f"{current_text}\n\n{footer_md}"
```

最终效果：`` `── deepseek-v4-pro 34% ──` ``

### 完整代码位置

`adapter.py` → `send()` 方法，共 ~48 行增量（含检测、编辑、降级、追踪）。

## 关键 Pitfall

**编辑前必须 API 拉取内容**：流式模式下，`send()` 收到的 `content` 参数是截断/不完整的（正文已通过 edit transport 分段推送）。直接拼接 `prev_content + footer` 会覆盖推送的正文。必须 `_api_get(f"posts/{post_id}")` 获取 Mattermost 服务端的实际内容。
