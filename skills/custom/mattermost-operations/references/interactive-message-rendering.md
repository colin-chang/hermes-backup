# P47：Clarify 交互卡片 Mattermost 不渲染

## 级别

**Hermes Mattermost Adapter 缺陷** — `gateway/platforms/mattermost.py`。

## 症状

- Agent 调用 `clarify` 向用户提问（多选或开放式）
- Mattermost 中看到提问文字，但**没有可点击的按钮/选项**
- 用户体感：「AI 没反应」「没有任何需要我回复的东西」
- 用户自然发送普通追问 → 触发了 P46（Gateway 双路由 → Session 分裂）

## 根因

`clarify` 工具输出的交互式卡片格式（带 `choices` 按钮或 `question` 文本区域）不被 Mattermost 适配器正确转换。适配器将其作为纯文本消息发送，丢失了交互元素。

与其他平台对比：
- **Discord**：原生支持按钮组件（`components`），clarify 卡片可渲染
- **Telegram**：支持 inline keyboard，clarify 卡片可渲染
- **Mattermost**：支持 Interactive Message 格式（`props.attachments` + `actions`），但适配器可能未将 clarify 输出转换为此格式

## 诊断方法

### 确认 clarify 消息已发送但未渲染

```bash
grep -E 'send\(\) threading.*clarify|clarify.*send' ~/.hermes/logs/agent.log | tail -5
```

如果 `send()` 日志存在但用户在 Mattermost 中看不到可交互元素 → P47。

### 确认 P46 连锁触发

```bash
grep -E 'clarify.*intercepted|conversation turn.*history=0' ~/.hermes/logs/agent.log | tail -10
```

如果 clarify intercept 和 history=0 的 turn 同时出现 → P47 + P46 连锁。

## 日志追踪示例（2026-05-23）

```
07:38:26  clarify 工具被调用（3 选项多选）
07:38:26  send() → Mattermost Thread xwoo1o  ✅ 消息已发送
          └─ 用户在 Mattermost 看到提问文字，看不到 3 个选项按钮

07:40:54  用户回复「三个决策点是什么」      ← 体感：AI 没给选项，追问
          └─ P46 触发：Gateway 双路由
```

## 影响范围

- 所有在 Mattermost 平台上使用 `clarify` 的场景
- 与 P46 形成连锁：卡片不渲染 → 用户发普通回复 → Session 分裂
- 也可能影响其他需要交互式卡片输出的工具（如审批确认）

## 修复方向（Mattermost Adapter 侧）

Mattermost 适配器需要将 `clarify` 的输出转换为 Mattermost Interactive Message 格式：

```json
{
  "props": {
    "attachments": [{
      "text": "请选择一个选项：",
      "actions": [
        {"id": "opt1", "name": "选项 A", "type": "button"},
        {"id": "opt2", "name": "选项 B", "type": "button"}
      ]
    }]
  }
}
```

关键约束（已知 Pitfall）：
- 最多 5 个 action/attachment，5 个 attachment/message
- 开放式提问（无 choices）需用文本输入替代方案
- **`id` 必须纯字母数字**，不能含下划线/连字符 — 否则 MM 返回 "找不到该页面"（与 Pitfall 4 同源）

## 实际修复（2026-05-23）

通过 `mattermost-enhancer` 插件覆盖 `send_clarify()` 实现：

**`adapter.py`**：
- 覆盖 `send_clarify()`，将 clarify 输出转换为 MM interactive card
- 有 choices → 渲染按钮卡片（每个选项一个按钮 + "其他"按钮）
- 无 choices → 保持纯文本（Gateway text-intercept 自动捕获回复）
- 回调处理：`_handle_clarify_choice_callback()` 和 `_handle_clarify_other_callback()`
- 卡片更新：选择后显示确认卡片 / "请输入"提示卡片

**`cards.py`**（新增函数）：
- `render_clarify_card()` — 主渲染函数
- `render_clarify_choice_confirmed_card()` — 选择确认卡片
- `render_clarify_other_prompt_card()` — "其他"提示卡片

**⚠️ 踩坑：action_id 不能有下划线。** 最初用 `clarify_{id}_{i}` 格式，MM 返回 "找不到该页面"。改为 `clarify{id}{i:02d}` 后正常（纯字母数字）。

详见插件仓库 `mattermost-enhancer/adapter.py`。

## 临时规避

在修复前，Agent 在 Mattermost 平台上使用 `clarify` 时应避免多选模式，改用开放式提问（纯文本格式），让用户以自然语言回复。

## 与相关 Bug 的关系

```
P47（卡片不渲染）
  ↓ 用户看不到选项，发普通回复
P46（Gateway 双路由）
  ↓ 同一条消息创建新 Session
Session 分裂 → 用户体感「串台」
```
