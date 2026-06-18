# P61 — 图片/视频/文件 Thread 路由丢失

## 现象

在 Mattermost Thread 中通过 `image_generate` / `video_generate` 工具生成图片或视频后，文件被发送到**频道顶层**而非当前 Thread。

## 根因

bundled `mattermost-platform` 适配器（`~/.hermes/hermes-agent/plugins/platforms/mattermost/adapter.py`）的 4 个媒体发送方法接收 `metadata` 参数但**未将其用于 Thread 路由**。

## 完整调用链

### 路径 1：图片（image_generate → MEDIA 标签）

```
LLM 调用 image_generate
  → 生成图片保存到本地
  → LLM 输出: MEDIA:/path/to/image.png
  → Gateway _deliver_media_from_response()                     [run.py:11506]
  → adapter.send_multiple_images(                              [run.py:11567]
      chat_id, images, metadata=_thread_meta)  ← metadata 含 thread_id
  → bundled send_multiple_images() [adapter.py:520]
  → payload = {channel_id, message, file_ids}                  ← 无 root_id！
  → _api_post("posts", payload)  → 图片落到频道
```

**Bug 位置**：`adapter.py:594-598`，payload 构建未从 metadata 提取 thread_id。

### 路径 2：视频（video_generate → MEDIA 标签）

```
Gateway → adapter.send_video(chat_id, video_path, metadata=_thread_meta)
  → bundled send_video() [adapter.py:392] 接收 metadata
  → return _send_local_file(chat_id, video_path, caption, reply_to=None)
                                                        ↑ metadata 被丢弃
  → enhancer _send_local_file() [adapter.py:1606]
  → _get_thread_root_id(None) → None  (reply_to 为空)
  → payload 无 root_id → 视频落到频道
```

### 路径 3：文件（send_document 同理）

```
Gateway → adapter.send_document(chat_id, file_path, metadata=_thread_meta)
  → bundled send_document() [adapter.py:365] 接收 metadata
  → return _send_local_file(chat_id, file_path, caption, reply_to=None, file_name)
                                                        ↑ metadata 被丢弃
  → 同路径 2 → payload 无 root_id
```

### 路径 4：背景任务图片/文件

```
Gateway → adapter.send_image(chat_id, image_url, metadata=_thread_metadata)  [run.py:11852]
  → bundled send_image() [adapter.py:339]
  → return _send_url_as_file(chat_id, image_url, caption, reply_to=None, "image")
                                                    ↑ metadata 被丢弃
  → enhancer _send_url_as_file() [adapter.py:1652]
  → 内部调用 _send_local_file() with reply_to=None → 无 root_id
```

## 对比：为什么文本消息没问题

| 消息类型 | 适配器方法 | metadata → root_id | 状态 |
|---------|-----------|-------------------|:--:|
| 文本 | enhancer `send()` | ✅ `metadata.get("thread_id")` → `payload["root_id"]` | 正常 |
| 图片(批量) | bundled `send_multiple_images()` | ❌ metadata 完全未使用 | Bug |
| 图片(单张) | bundled `send_image()` → `_send_url_as_file()` | ❌ metadata 被丢弃 | Bug |
| 视频 | bundled `send_video()` → `_send_local_file()` | ❌ metadata 被丢弃 | Bug |
| 文件 | bundled `send_document()` → `_send_local_file()` | ❌ metadata 被丢弃 | Bug |

enhancer 的 `send()` 方法（adapter.py:1491-1498）正确处理了 metadata fallback：

```python
# send() — 正确逻辑
elif metadata and metadata.get("thread_id"):
    payload["root_id"] = str(metadata["thread_id"])
```

但 enhancer 未覆写 `send_multiple_images()` / `send_image()` / `send_video()` / `send_document()`，这 4 个方法仍使用 bundled 版本。

## 责任归属

| 组件 | 责任 |
|------|------|
| zenmux-image / zenmux-video | ✅ 无责 — 只管生成，不管发送 |
| mattermost-enhancer | ⚠️ 未覆盖 — 覆写了 `send()` 但遗漏了 4 个媒体方法 |
| bundled mattermost-platform | 🔴 根因 — 4 个方法接收 metadata 但不用于 Thread 路由 |

## 修复方案

### 插件侧（已实施）

在 enhancer `adapter.py` 中覆写 4 个方法，补充 metadata → thread_id fallback（已实施，当前代码）：
- `send_multiple_images()` — 覆写父类上传逻辑，payload 注入 root_id
- `send_image()` / `send_video()` / `send_document()` / `send_voice()` — 转发前从 metadata 推导 reply_to

### 上游侧（已提交 PR）

[PR #33391](https://github.com/NousResearch/hermes-agent/pull/33391) 修复 bundled adapter 的 `send_multiple_images()`——payload 构建时从 metadata 提取 thread_id 并解析为 root_id。仅覆盖批量图片路径，单张媒体方法的 metadata→reply_to 推导保留在插件侧。

```python
# MattermostApprovalAdapter 中新增

async def send_multiple_images(
    self, chat_id, images, metadata=None, human_delay=0.0
):
    """覆写父类：metadata.thread_id → root_id 确保图片进 Thread."""
    # 复用父类上传逻辑...
    # 构建 payload 时注入 root_id:
    if self._reply_mode == "thread":
        if metadata and metadata.get("thread_id"):
            payload["root_id"] = str(metadata["thread_id"])
    return await self._api_post("posts", payload)

async def send_image(
    self, chat_id, image_url, caption=None, reply_to=None, metadata=None
):
    """覆写：metadata.thread_id → reply_to 推导."""
    if reply_to is None and metadata and metadata.get("thread_id"):
        reply_to = metadata["thread_id"]
    return await self._send_url_as_file(chat_id, image_url, caption, reply_to, "image")

async def send_video(
    self, chat_id, video_path, caption=None, reply_to=None, metadata=None
):
    """覆写：metadata.thread_id → reply_to 推导."""
    if reply_to is None and metadata and metadata.get("thread_id"):
        reply_to = metadata["thread_id"]
    return await self._send_local_file(chat_id, video_path, caption, reply_to)

async def send_document(
    self, chat_id, file_path, caption=None, file_name=None,
    reply_to=None, metadata=None
):
    """覆写：metadata.thread_id → reply_to 推导."""
    if reply_to is None and metadata and metadata.get("thread_id"):
        reply_to = metadata["thread_id"]
    return await self._send_local_file(chat_id, file_path, caption, reply_to, file_name)
```

`send_multiple_images()` 需要复制父类的上传逻辑（约 90 行），其余 3 个方法只需 5 行转发包装。
