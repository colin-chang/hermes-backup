# P46：Clarify 阻塞等待时，用户回复触发 Session 分裂

## 级别

**非插件 Bug — Gateway session 路由缺陷。**

## 症状

- Agent 调用 `clarify` 向用户提问（多选或开放式）
- 用户在同一 Thread 中回复
- 回复**没有**在当前对话中继续，而是启动了一个**全新的 Session**（`history=0`）
- 用户看到 Agent「失忆」——完全不知道刚才在讨论什么
- 同时，原 Session 的 `clarify` **也**收到了回复（延迟 100-300 秒），原 Session 继续处理
- 结果：**一个 Thread 中两个 Session 并行运行**

## 根因

当 `clarify` 工具阻塞等待用户输入时，Gateway 的 inbound message handler 对同一 Thread 的新消息执行了**双路由**：

1. ✅ **正确路由**：消息被传递给等待中的 `clarify` 工具（`Gateway intercepted clarify text response`）
2. ❌ **错误路由**：同一条消息也被当作新的 `conversation turn`，创建了全新 Session

两个 Session 使用不同的 `session_key`，即使它们在同一个 Thread 中：
- Session A (原): `20260523_073705_484dfd29`
- Session B (新): `20260523_074054_c148324a`

## 与相似 Bug 的区分

| Bug | 关键特征 | `history=N` | Session Key |
|-----|---------|-------------|-------------|
| **P36** 并发 Thread 串台 | `send()` 消息落到错误频道/Thread | N > 0（上下文是别人的） | 同 Thread 不同 key |
| **P38** Thread 根帖进度丢失 | root_id 为空 → 进度消息落频道 | N > 0 | 同 key |
| **P39** 网关重启会话丢失 | 重启清空内存，重启后 history=0 | N = 0（重启后） | **同 key** |
| **P46** Clarify + Session 分裂 | clarify 阻塞 + 用户回复 → 双 Session | N = 0（新 Session） | **不同 key** |

## 诊断方法

### 步骤 1：确认 Session 分裂

```bash
grep 'conversation turn.*history=0' ~/.hermes/logs/agent.log | \
  grep -E '2026-05-23 07:(3[7-9]|40)'
```

如果短时间内同一 Thread 出现两个不同 `session=` 值 → P46。

### 步骤 2：确认 clarify 双路由

```bash
grep -E 'clarify.*intercepted|conversation turn.*history=0' ~/.hermes/logs/agent.log | \
  grep '2026-05-23 07:4'
```

期望看到：
```
07:40:54  conversation turn: session=B ... history=0          ← 错误的新 Session
07:43:37  Gateway intercepted clarify text response (session=A) ← 延迟的 clarify 回复
```

### 步骤 3：确认 Session A 仍在运行

```bash
grep 'session=A_SESSION_ID' ~/.hermes/logs/agent.log | tail -5
```

如果 Session A 在 Session B 创建后仍在执行工具调用 → 确认并行运行。

## 日志追踪示例（2026-05-23 真实事故）

```
07:37:05  Turn 1: Session A (073705_484dfd29)  start, history=0
07:37~38  API calls #1~#7: 读取文件 + 生成审计报告
07:38:26  API #7: 1584 tokens out → clarify 工具被调用（3选项）
          └─ clarify 阻塞等待用户回复

07:40:54  ⚠️ Gateway inbound: user replies in same Thread
          source.thread_id = xwoo1oaztiri3dctxnyb5due8o ✅ (正确 Thread)
          └─ ❌ Session B (074054_c148324a) 创建, history=0
          
07:42:11  Session B 被中断 → 恢复 → text_response 结束

07:43:37  ✅ Session A 的 clarify 收到回复（310.72s total）
          └─ Session A 继续执行 API #8~#18...
```

**时间差**：用户 07:40:54 发送 → clarify 07:43:37 收到（延迟 163 秒）。

## 加剧因素：Clarify 交互卡片 Mattermost 不渲染

**Mattermost 适配器不支持渲染 `clarify` 的交互式卡片**（多选按钮/选项列表）。当 Agent 调用 `clarify` 时：

- 消息本身可能以纯文本形式发出（用户能看到提问文字，但看不到可点击的选项）
- 用户体感：「AI 没反应」「没有任何需要我回复的东西」
- 用户自然地发送普通追问（而非「回复 clarify 卡片」）
- Gateway 将此消息同时路由给 clarify 和作为新 Session → **P46 触发概率大幅上升**

这是两个独立 Bug 的连锁效应：
1. **Mattermost Adapter Bug**：`clarify` 交互卡片不渲染（归属：`gateway/platforms/mattermost.py`）
2. **Gateway Bug (P46)**：clarify 等待时 inbound handler 双路由（归属：`gateway/run.py`）

## 影响范围

- 所有使用 `clarify` 工具的对话
- 用户在 `clarify` 等待期间回复 → 几乎 100% 触发
- Thread 中影响更严重（用户看不到 Session B 的上下文丢失）
- **Mattermost 平台尤为严重**：clarify 卡片不渲染 + P46 双路由叠加

## 临时规避

在 Gateway 修复前：

1. **Agent 侧**：`clarify` 提问后，若下一 Turn 看到 `history=0`，主动用 `session_search` 找回上下文
2. **用户侧**：若发现 Agent 失忆，直接说「上下文丢了，继续之前的讨论」

## 修复方向（Gateway 侧）

Gateway 的 inbound message handler 需要在创建新 Session 前检查：
1. 当前 chat+thread 是否有活跃 Session？
2. 该 Session 是否在 `clarify` 阻塞等待？
3. 若 1 && 2 → 仅路由给 clarify，不创建新 Session

## 实际修复（2026-05-23）

### 修复 1：Mattermost clarify 卡片渲染（`mattermost-enhancer` 插件）

在插件 `adapter.py` 中覆盖 `send_clarify()`，用 MM interactive card button 渲染选项：

- 有 choices → 每个选项渲染为一个按钮 + 「✍️ 其他」按钮
- 无 choices → 纯文本提问
- 回调处理：`cmd_clarify_choice`（resolve）和 `cmd_clarify_other`（mark_awaiting_text）
- 卡片更新：选择后显示确认卡片 / 「请输入」提示卡片

新增 `cards.py` 函数：`render_clarify_card()`、`render_clarify_choice_confirmed_card()`、`render_clarify_other_prompt_card()`

**⚠️ Pitfall: Mattermost action `id` 必须纯字母数字。** 按钮的 `id` 字段不能用下划线（`_`）或连字符（`-`），否则 MM 返回 "找不到该页面"。与 Pitfall 4（Slash Command action id）同源。

- ❌ `clarify_{id}_{i}` → MM 报错
- ✅ `clarify{id}{i:02d}` → 正常

### ❓ "找不到该页面" 的双重根因诊断

用户点击 clarify 按钮后看到"对不起，我们找不到该页面"**有两种可能原因**：

| 原因 | 诊断信号 | 修复方向 |
|------|---------|---------|
| **P47: action_id 含特殊字符** | 所有按钮都失败，且 `action_id` 含 `_` / `-` | 改为纯字母数字 |
| **Callback URL 不可达** | 集中在 Gateway 重启后的卡片；日志有 `Clarify choice callback: resolve failed` | 确认 `host.docker.internal:18065` 可达 |

**诊断步骤**：

```bash
# 1. 确认是否 P47（action_id 问题）
grep 'send_clarify' ~/.hermes/logs/agent.log | grep 'clarify_id=' | tail -5
# 看 clarify_id 是否含特殊字符

# 2. 确认是否 callback URL 不可达
# 同时看 gateway 重启时间 + clarify 回调失败时间
grep -E 'Gateway running|MattermostApproval callback server on' ~/.hermes/logs/agent.log | grep '2026-05-23'
grep 'Clarify choice callback.*failed' ~/.hermes/logs/agent.log | grep '2026-05-23'
# 如果 clarify 卡片在 Gateway 重启**前**发出，但用户在重启**后**点击 → callback URL 不可达

# 3. 验证 callback 可达性（从 Docker 内）
docker exec mm-app wget -qO- http://host.docker.internal:18065/mattermost/callback 2>&1
# 注意: mm-app 是无 shell 容器，需用 docker run 临时容器测试
docker run --rm alpine/curl curl -s -o /dev/null -w '%{http_code}' http://host.docker.internal:18065/mattermost/callback
```

**2026-05-23 实际案例**：Gateway 在 08:24 连续重启 4 次（SIGTERM），期间发出的测试 clarify 卡片（`clarify_id=1996fd44b1`）在用户 08:38 点击时 callback server 已重新绑定但卡片仍指向旧路由，报"找不到该页面"。08:41 日志确认：`Clarify choice callback: resolve failed (already resolved?) clarify_id=test123`。

### 修复 2：P46 Gateway session key fallback（`gateway/run.py`）

**根因**：`_handle_message` 用 `_session_key_for_source(source)` 的 `_quick_key` 查 pending clarify，但 `_quick_key` 可能使用 `thread_sessions_per_user: false`（config 级），而 clarify 注册时的 session_key 始终包含 thread_id → 查不到 → 创建新 Session。

**修复**：`_quick_key` 查不到时，用 `get_or_create_session(source)` 的 canonical session_key 二次匹配。

```python
if _pending_clarify is None:
    try:
        _canonical_entry = self.session_store.get_or_create_session(source)
        _canonical_key = _canonical_entry.session_key
        if _canonical_key != _quick_key:
            _pending_clarify = _clarify_mod.get_pending_for_session(_canonical_key)
    except Exception:
        pass
```

### ⚠️ 已知回归：P46 在非 Thread 场景触发副作用（2026-05-23）

**症状**：上游 PR #30669 CI 中 2 个 Telegram topic mode 测试失败：
- `test_root_telegram_dm_prompt_is_system_lobby_when_topic_mode_enabled`
- `test_root_telegram_dm_new_shows_create_topic_instruction`

两个测试都断言 `get_or_create_session.assert_not_called()`，但 P46 的 fallback 在 `_pending_clarify is None` 时**无条件**调用 `get_or_create_session`，即使在 Telegram DM lobby（无需创建 session 的场景）也会触发。

**根因**：Clarify session 分裂只在 **Thread 上下文**中才可能发生（`_quick_key` ≠ `session_key` 源于 `thread_sessions_per_user` 配置差异）。在非 Thread 场景（DM、频道主消息流），两个 key 始终一致，不需要 canonical key fallback。

**修复（待应用）**：加 `source.thread_id` 守卫，只在 Thread 场景下执行 fallback：

```python
if _pending_clarify is None and source.thread_id:
    try:
        _canonical_entry = self.session_store.get_or_create_session(source)
        _canonical_key = _canonical_entry.session_key
        if _canonical_key != _quick_key:
            _pending_clarify = _clarify_mod.get_pending_for_session(_canonical_key)
    except Exception:
        pass
```

> **注意**：此修复已于 2026-05-23 应用到 `hermes-patches.sh` P46 和上游 PR #30669。

### P46b：Clarify concurrency guard（第二层防御）

**额外修复**（`_handle_message_with_agent` 中的 session guard intercept）：
在 `get_or_create_session` 返回 canonical `session_key` 之后、启动 agent 之前，再次检查 clarify。这是 belt-and-suspenders 防护——当 Layer 1 (P46) 中的 `_quick_key` 检查失败、`session_key` ≠ `_quick_key`、且在 `_running_agents` 中找不到 agent 时，在最后一刻拦截消息并路由给 clarify，阻止新 Session 创建。

**归属**：`hermes-patches.sh` P46b，check_grep: `Gateway intercepted clarify at session guard`。

### 上线状态

- ✅ 插件渲染修复：已部署（`mattermost-enhancer` 插件 `adapter.py` + `cards.py`）
- ✅ P46 源码修复：已在 `hermes-patches.sh` 注册为 patch（`P46`），已加 `source.thread_id` 守卫
- ✅ P46b 源码修复：已在 `hermes-patches.sh` 注册为 patch（`P46b`）
- ✅ 上游 PR #30669：已推送 `source.thread_id` 守卫修复，等待 CI 重新运行
