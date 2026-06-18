# Cron Jobs 配置与排障

> 本文档补充 `hermes-config-management` 技能，覆盖定时任务的存储、字段语义、排障方法。

## 存储位置

- **jobs.json**: `/Users/Colin/.hermes/cron/jobs.json`
- **运行输出**: `/Users/Colin/.hermes/cron/output/<job_id>/<timestamp>.md`
- **运行日志**: `/Users/Colin/.hermes/logs/agent.log`（含 cron session）

## 字段语义

### 有效字段（按重要性）

| 字段 | 类型 | 说明 |
|------|------|------|
| `no_agent` | bool | **true=纯脚本任务，不调用 LLM**。此时 model/provider/base_url 无意义 |
| `script` | string | `no_agent=true` 时的脚本路径（相对于 `~/.hermes/scripts/`） |
| `prompt` | string | `no_agent=false` 时的任务指令 |
| `skills` | array | 加载的 skill 列表 |
| `model` | string | 仅 `no_agent=false` 有效，如 `bytedance/doubao-seed-2.0-pro` |
| `provider` | string | 仅 `no_agent=false` 有效，如 `custom:zenmux` |
| `enabled_toolsets` | array | 仅 `no_agent=false` 有效 |
| `schedule` | object | `{kind, expr, display}` |
| `deliver` | string | 投递目标 |
| `context_from` | array | 依赖的上游 job ID |

### 装饰性字段（no_agent=true 时无意义）

- `model` — LLM 不会被调用，设了也没用
- `provider` — 同上
- `base_url` — 同上

### 非标准字段（手动编辑残留）

- `toast_notifications` — 不属于 cron job schema，需清理
- `profile` — 为 null 时可保留

### 遗留字段

- `skill` (单数) — 与 `skills[0]` 重复。可能是旧版 API 残留，也可能是主 skill 标记。暂不删除以防副作用。

## 排障流程

### 1. 确认任务是否真正成功

`cronjob list` 的 `last_status: "ok"` 不代表内容正确。需检查实际输出：

```bash
# 查看最新输出文件
ls -lt /Users/Colin/.hermes/cron/output/<job_id>/ | head -3
# 翻尾部确认非垃圾
tail -20 /Users/Colin/.hermes/cron/output/<job_id>/<latest>.md
```

### 2. 检查 LLM 是否正常工作

```bash
# 搜索 cron session 日志
grep "cron_<job_id>" /Users/Colin/.hermes/logs/agent.log | tail -20
```

关键指标：
- `api_calls` — 调用次数。1 次且 `tool_turns=0` = 模型直接摆了
- `tool_turns` — 工具调用轮数。0 = 没干活
- `response_len` — 输出长度。几十字符 = 垃圾输出
- `finish_reason` — 应为 `stop`，`length` 表示截断

### 3. 模型能力排查

如果 `tool_turns=0` 且 `response_len` 极小，模型可能不支持工具调用或在该场景下失效：

```
# 正常（doubao）
api_calls=10 tool_turns=9 response_len=2239 ✅

# 异常（minimax）
api_calls=1  tool_turns=0 response_len=13   ❌
```

### 4. 流中断错误

```
RemoteProtocolError: peer closed connection without sending complete message body
```

这是 Cloudflare/Provider 端问题，Hermes 会自动重试（最多 3 次）。如果最终 session 正常结束则无需处理。

## 清理无效字段

直接编辑 `jobs.json`：

```bash
# 偏好：用 write_file 工具重写整个文件，避免 JSON 格式问题
# 1. read_file 读取当前内容
# 2. 移除无效字段后 write_file 写回
# 3. cronjob list 验证
```

清理后 Hermes 调度器会自动读取更新后的 JSON，无需重启。
