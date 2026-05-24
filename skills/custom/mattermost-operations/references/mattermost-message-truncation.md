# P51: MAX_POST_LENGTH 消息截断问题

## 问题

Hermes Agent 发送给 Mattermost 的长消息被截断——用户只看到第一部分内容（如"方案 A"），后续内容（"方案 B/C/D"）
消失。

## 根因

`gateway/platforms/mattermost.py` 第 37 行：

```python
MAX_POST_LENGTH = 4000  # ← OpenClaw 遗留值
```

Mattermost 服务器实际支持 **16383 字符/帖**，但 Hermes 的 `truncate_message()` 按 4000 字符分片，
将长消息拆分为多条独立帖子。在 CRT Thread 模式下，连续的 Bot 帖子被折叠（Show More），
用户看到的只是第一段。

## 修复

将硬编码常量改为读取环境变量，默认 16000：

```python
MAX_POST_LENGTH = int(os.getenv("MATTERMOST_MAX_POST_LENGTH", "16000"))
```

**`.env` 配置：**

```bash
MATTERMOST_MAX_POST_LENGTH=16000
```

## Patch 注册

已在 `hermes-patches.sh` 注册为 P51：

```
"gateway/platforms/mattermost.py|长消息被截断成多条帖子—Agent回复太长被切成4000字符小段|MATTERMOST_MAX_POST_LENGTH"
```

## 工作原理

```
LLM 生成完整响应（8000~10000 字符）
  ↓
mattermost.py format_message() → 去图像语法
  ↓
base.py truncate_message(content, MAX_POST_LENGTH)
  ├── < 16000 字符 → 1 条帖子 ✅
  └── ≥ 16000 字符 → N 条帖子 + (1/N) 标记
  ↓
mattermost.py send() → REST API 发帖
```

## 配置优先级

| 来源 | 值 | 说明 |
|------|-----|------|
| 环境变量 `MATTERMOST_MAX_POST_LENGTH` | 用户定义 | 最高优先级 |
| Python 默认值 | `16000` | 未设环境变量时生效 |
| Mattermost 服务端上限 | `16383` | 不可逾越的硬限制 |
