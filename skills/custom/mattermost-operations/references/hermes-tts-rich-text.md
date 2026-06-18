# Hermes TTS 富文本处理分析

> 最后更新：2026-05-28 | 基准版本：Hermes v0.14.x

## 两套 TTS 路径对比

| 路径 | 触发方式 | Markdown 预处理 |
|------|---------|---------------|
| CLI Voice 模式 | `/voice on` + CLI 交互 | ✅ `speak_text()` 有 regex 清洗 |
| `text_to_speech` 工具 | 模型直接调用 | ❌ 零预处理，raw text → TTS provider |

## speak_text() 清洗规则（hermes_cli/voice.py:785-794）

```python
tts_text = re.sub(r'```[\s\S]*?```', ' ', tts_text)         # fenced code blocks → 空格
tts_text = re.sub(r'\[([^\]]+)\]\([^)]+\)', r'\1', tts_text) # [text](url) → text
tts_text = re.sub(r'https?://\S+', '', tts_text)            # bare URLs → 删除
tts_text = re.sub(r'\*\*(.+?)\*\*', r'\1', tts_text)         # **bold** → bold
tts_text = re.sub(r'\*(.+?)\*', r'\1', tts_text)             # *italic* → italic
tts_text = re.sub(r'`(.+?)`', r'\1', tts_text)               # `inline code` → inline code
tts_text = re.sub(r'^#+\s*', '', tts_text, flags=re.MULTILINE)  # headers → 去#号
tts_text = re.sub(r'^\s*[-*]\s+', '', tts_text, flags=re.MULTILINE) # list bullets → 去-*
tts_text = re.sub(r'---+', '', tts_text)                     # horizontal rules → 删除
tts_text = re.sub(r'\n{3,}', '\n\n', tts_text)               # excess newlines → 压缩
```

## 盲区：未被处理的富文本元素

| 元素 | speak_text() | text_to_speech 工具 | TTS 朗读效果 |
|------|-------------|-------------------|------------|
| 代码块 | ✅ 整体删除 | ❌ | 读出语言标签+代码内容 |
| 链接 `[text](url)` | ✅ 去 URL | ❌ | 读出方括号+URL |
| 粗体/斜体 | ✅ 去标记 | ❌ | 读出星号 |
| 行内代码 | ✅ 去反引号 | ❌ | 读出反引号 |
| 标题 `#...` | ✅ 去#号 | ❌ | 读出#号 |
| 列表符号 | ✅ 去-* | ❌ | 读出-* |
| **表格** `|col|col|` | ❌ | ❌ | **读出管道符 + 对齐线 + 单元格串在一起** |
| **引用块** `> text` | ❌ | ❌ | 读出 `>` |
| **复选框** `- [x]` | 半处理 | ❌ | `[x] task` 残留在文本中 |
| **图片** `![alt](url)` | ❌ | ❌ | alt text 残留 |

## 根本问题

`text_to_speech_tool`（`tools/tts_tool.py:1819`）是模型直接调用的工具，**没有任何预处理步骤**——模型传入什么就喂给 TTS 引擎什么。`speak_text()` 的清洗逻辑仅限 CLI voice 模式。

## 表格是最大盲区

表格语法 `| col | col |` 在任何路径中都没有被处理。一张 5x3 表格会让 TTS 引擎逐字读出：
```
管道符 | 单元格1 | 单元格2 | 单元格3 | 换行 | 连字符-连字符-连字符 | 管道符
```
完全无法理解。如果要支持 TTS，需要在 `text_to_speech_tool` 或 `speak_text` 入口处追加表格 → 自然语言的转换（如 `|` → `, `，展开为「列名1：值1，列名2：值2」逐行朗读）。
