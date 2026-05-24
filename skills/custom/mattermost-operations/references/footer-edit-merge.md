# Runtime Footer 编辑合并机制

> 记录日期：2026-05-24 | 插件版本：v2.2.0+

## 功能概述

Hermes 内置 `runtime_footer` 在流式模式下将 footer 作为独立消息发送（`gateway/run.py:8092`）。插件在 `send()` 中拦截 footer，改为编辑上一条 Bot 消息，将 footer 以脚注样式追加到末尾。

## 实现位置

`adapter.py` → `send()` 覆写 + `_is_footer_line()` + `_tracked_posts`

## 检测逻辑：`_is_footer_line()`

Footer 来自 `gateway/runtime_footer.py` 的 `format_runtime_footer()`，格式为 `model · 34%`（`_SEP = " · "` 拼接）。

检测特征：
- 单行（无 `\n`）
- 含 ` · ` 分隔符
- 长度 < 120 字符
- 无 markdown 格式字符

## 编辑流程

```
Gateway send(footer_line)
  → 插件 send() 拦截
  → _is_footer_line() = True
  → 查 _tracked_posts[chat_id] → 获取上一条消息的 post_id
  → ⚠️ 实时 API 拉取帖子内容（不能信任 _tracked_posts 中的 content）
  → 拼接 footer 为脚注格式
  → PUT /api/v4/posts/{post_id} 编辑帖子
  → 更新 _tracked_posts
  → 返回成功
```

## ⚠️ Pitfall: 流式模式下追踪的 content 不完整

**症状**：编辑后正文被截断，只剩下不完整的片段。

**根因**：流式模式下，Gateway 调用 `send()` 时传入的 `content` 是第一个 chunk 的内容，而非完整正文。如果信任 `_tracked_posts[chat_id]` 中的 `content` 来拼接 footer，会覆盖掉完整的流式推送内容。

**修复**：编辑前**实时通过 API 拉取**帖子内容：
```python
current = await self._api_get(f"posts/{post_id}")
current_text = current.get("message", "")
```
然后用拉取到的完整内容 + footer 拼接，PUT 回去。

**教训**：在流式模式下，`send()` 收到的 `content` 参数不可信。任何需要修改已发送消息的操作，都必须先 API 拉取当前内容。

## Footer 格式演变

| 迭代 | 格式 | 问题 |
|------|------|------|
| v1 | `── · · ──\n*model · 34%*` | 两行，斜体不够灰 |
| v2 | `── *model 34%* ──` | 斜体，字号不变 |
| v3 | `── \`model 34%\` ──` | 部分 inline code |
| v4（最终） | `` `── model 34% ──` `` | 整行 inline code，等宽+灰色背景+小字 |

最终格式使用 Mattermost inline code 的优势：
- 等宽字体天然比正文小
- 灰色背景让它看起来像脚注/状态栏
- Mattermost 不支持自定义 CSS，这是唯一可靠的"灰色小字"方案

## 降级策略

| 场景 | 行为 |
|------|------|
| 无追踪帖子（footer 是第一条消息） | 回退为正常发送（独立消息） |
| API 拉取帖子内容失败 | 回退为正常发送 |
| PUT 编辑失败 | 回退为正常发送 |

降级路径确保 footer 不会丢失——最坏情况下回到原始行为（独立消息）。

## 追踪字典

`_tracked_posts: Dict[str, Tuple[str, str]]` — `chat_id → (post_id, content)`

每次非 footer 的 `send()` 成功后更新。用于 footer 拦截时查找上一条消息。

键用 `chat_id`（channel ID），不用复合键。理由：同一 channel 内 footer 紧跟响应消息发送，在 asyncio 单线程模型下不会被其他 Thread 的响应插队。

## 配置

用户端只需在 Hermes `config.yaml` 中启用：
```yaml
display:
  runtime_footer:
    enabled: true
    fields:
      - model
      - context_pct
```

插件端自动拦截——无需额外配置。
