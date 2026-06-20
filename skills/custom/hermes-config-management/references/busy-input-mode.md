# Busy Input Mode — 消息中断模式配置

控制用户发送新消息时 Hermes 正在工作中的行为。

## 三种模式

| 模式 | 行为 | 适用场景 |
|------|------|---------|
| `interrupt` | 立即打断当前对话，新消息成为下一个 turn | 需要立刻切换话题（默认） |
| `queue` | 排队等待，不打断，处理完后自动接上 | 想让当前任务跑完再处理 |
| `steer` | 在下一个工具调用后注入消息，不开启新 turn | 想中途微调方向但不重置对话流 |

## 配置位置

### `config.yaml`

```yaml
display:
  busy_input_mode: queue    # interrupt | queue | steer
```

### 环境变量（Gateway 覆盖）

```bash
export HERMES_GATEWAY_BUSY_INPUT_MODE=queue
```

Gateway 加载逻辑（`gateway/run.py:_load_busy_input_mode`）：
1. 先查 `HERMES_GATEWAY_BUSY_INPUT_MODE` 环境变量
2. 未设置则读 `config.yaml` 的 `display.busy_input_mode`
3. 都不是 `queue`/`steer` 时默认 `interrupt`

## CLI 的 `/busy` 命令（CLI-only）

```
/busy queue       # 切到排队模式
/busy steer       # 切到 steer 模式
/busy interrupt   # 切到打断模式（默认）
/busy status      # 查看当前模式
```

CLI 读取的是 `display.busy_input_mode` config 值，与 gateway 一致。

## 即时命令（CLI + Gateway 都可用）

```
/queue <prompt>   # 把一条消息排到下一个 turn
/steer <prompt>   # 在当前 turn 工具调用后注入消息
```

## 注意事项

- `steer` 模式仅支持纯文本，无法携带图片附件（图片会自动降级为 `queue`）
- `steer` 如果 agent 拒绝接受或在完成前没有更多工具调用，剩余消息会降级为 `queue` 作为下一个 turn 发送
- 与 `/background` 不同——`/background` 启动的是**独立新会话**，不属于消息处理模式
