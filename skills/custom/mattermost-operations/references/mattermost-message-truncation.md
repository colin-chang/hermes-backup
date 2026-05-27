# P51: MAX_POST_LENGTH 消息截断问题

## 问题

Hermes Agent 发送给 Mattermost 的长消息被截断——用户只看到第一部分内容（如"方案 A"），后续内容（"方案 B/C/D"）
消失。

## 根因

> **v0.14.0 迁移后**，bundled adapter 位于 `hermes-agent/plugins/platforms/mattermost/adapter.py` 第 37 行：

```python
MAX_POST_LENGTH = 4000  # ← OpenClaw 遗留值
```

Mattermost 服务器实际支持 **16383 字符/帖**，但 Hermes 的 `truncate_message()` 按 4000 字符分片，
将长消息拆分为多条独立帖子。在 CRT Thread 模式下，连续的 Bot 帖子被折叠（Show More），
用户看到的只是第一段。

## 修复方案

将硬编码常量改为读取环境变量，默认 16000：

```python
MAX_POST_LENGTH = int(os.getenv("MATTERMOST_MAX_POST_LENGTH", "16000"))
```

**`.env` 配置：**

```bash
MATTERMOST_MAX_POST_LENGTH=16000
```

## 当前状态

**⚠️ 尚未修复。** P51 文档已存在但**未注册到 `hermes-patches.sh`**，也未在 `mattermost-enhancer` 插件中覆盖。
插件 `adapter.py` 第 30 行从 bundled adapter 导入 `MAX_POST_LENGTH`，当前值为 `4000`。

修复方式二选一：
1. 在 `mattermost-enhancer` 的 `adapter.py` 中覆盖 `MAX_POST_LENGTH = 16000`（推荐，不碰上游代码）
2. 在 `hermes-patches.sh` 注册 P51，patch bundled adapter

> **历史说明**：v2026-05-27 审计确认此问题存在于 bundled adapter，`hermes-patches.sh` 中从未有 P51 条目。之前的「已在 hermes-patches.sh 注册」描述有误。

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
