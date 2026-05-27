# Patch 分类：插件化可行 vs 必须保持 source patch

> 评估日期：2026-05-22

## 核心原则

一个补丁能否迁移到插件，取决于它处于消息处理链的**入站侧**还是**出站侧**：

```
入站（Inbound）                          出站（Outbound）
  WebSocket event                           send()
    → _handle_ws_event()                       → _resolve_root_id()
      → thread_id 计算                           → _send_local_file()
      → build_source()                           → _send_url_as_file()
      → handle_message()                         → send_typing()
                                              → send_exec_approval()
```

## 出站补丁 → ✅ 可插件化

出站方法的特征是：**接口契约明确**（入参/返回值固定），重写安全，升级不敏感。

成功案例：

| 补丁 | 方法 | 迁移方式 |
|------|------|----------|
| P6 _resolve_root_id | `send()`, `_send_local_file()`, `_send_url_as_file()` | 覆写三个方法，内部调用 `_resolve_root_id()` |
| P7 DM 审批 | `send_exec_approval()`, `connect()`, `disconnect()` | 覆写五个方法 |
| P10c MEDIA 静默跳过 | `_send_local_file()` | 覆写方法，内部 try/except |

## 入站补丁 → ❌ 不能插件化

入站修复的特点是：**深入消息处理循环内部，无可重写的接口边界**，修改的是局部变量而非方法返回值。

| 补丁 | 位置 | 为什么不能插件化 |
|------|------|-----------------|
| P38 thread_id 计算 | `_handle_ws_event()` L768 | `thread_id` 是局部变量，在 `build_source()` 之前计算，无可 hook 的扩展点 |

三条死路分析：

1. **重写 `_handle_ws_event()`**：~200 行逻辑（去重、白名单、@mention、文件下载），复制整个方法 → 上游每次改动都可能断裂
2. **重写 `build_source()`**：太晚——`thread_id` 由调用方传入，重写无法修正已错误的参数
3. **重写 `handle_message()` 后改 `source.thread_id`**：dirty hack，`source` 在 `handle_message()` 之前已被多处引用（session key 构建等），事后篡改会漏网

## 决策速查

```
这个补丁在哪一层？
├── 出站方法（send/send_typing/send_exec_approval...）
│   → ✅ 可行，覆写方法 + 内部调用自定义逻辑
│
├── 出站方法的辅助（如 _resolve_root_id）
│   → ✅ 可行，作为插件私有方法
│
├── 入站消息处理（_handle_ws_event 内部）
│   → ❌ 不可行，保持 source patch
│
└── 生命周期（connect/disconnect）
    → ✅ 可行，覆写方法 + super() 调用
```

## P38 的妥协方案

P38 的增强版（API 反查）留在 `hermes-patches.sh`，PR 提交给上游的是最小修复版（无 API 调用）——两者通过同一个 grep 检测共存，上游合入后 patch 自动跳过。

## 案例研究：P46/P46b — 双归属策略（2026-05-23 更新）

> 评估日期：2026-05-23

### 场景

P46（clarify session 分裂）和 P46b（concurrency guard）都修改 `gateway/run.py`——这与插件脚本中已有的两个补丁（DM 审批 `user_id`、工具进度 `Platform.MATTERMOST`）修改的是同一个文件。

### 最终决策：双归属

P46/P46b 是通用 Gateway bug（影响所有 Thread 平台），但 Mattermost CRT 用户是其**主要受害者**（CRT Thread 模式 + clarify 卡片渲染缺失 → 双重加剧）。

- **全局 `hermes-patches.sh`**：保留 P46 + P46b（我们本机使用）
- **插件 `hermes-mattermost-enhancer.sh`**：增加 Patch 3 (P46) + Patch 4 (P46b)（面向第三方 Mattermost 用户，他们只有插件脚本，没有全局脚本）
- **`source.thread_id` 守卫**确保非 Thread 场景（Telegram DM lobby 等）不受影响
- 两处共享相同的 check_grep，防重复应用

### 新的分类原则（更新）

```
这个补丁 Mattermost 用户需要吗？
├── ✅ 仅 Mattermost 需要 → 插件脚本（user_id, progress_reply_to）
├── ✅ Mattermost 用户也需要 → 双归属（P46/P46b）
│   全局脚本保留（我们本机）+ 插件脚本也加（第三方用户）
└── ❌ Mattermost 无关 → 仅全局脚本（MEDIA 正则, config 桥接...）
```

## Patch 可消除性审查（2026-05-29 深度源码分析）

> 逐项审查每个 patch 是否真的需要修改 Hermes 源码，还是可以在插件内覆写实现。

### 🟢 A 类：已在插件内部实现，Patch 不必要（应移除）

| Patch | 描述 | 分析 |
|-------|------|------|
| **P6** (全局 P54) | WebSocket 心跳 30→15s | enhancer 的 `connect()` 调 `super().connect()` → `_ws_loop()` → `_ws_connect_and_listen()`。只需**覆写 `_ws_connect_and_listen`**，设 `heartbeat=15.0` 即可。Python 私有方法可被子类覆写。 |
| **P8** (全局 P56) | `_api_put` 缺少 timeout | `_api_put` 仅有一个调用者：`edit_message()`。enhancer 已**完整覆写 `edit_message`**（自实现 HTTP PUT + 30s timeout + 分类异常处理），根本不走上游的 `_api_put`。Patch 多余。 |

### 🟡 B 类：可优化但保留 Patch

| Patch | 描述 | 分析 | 决策 |
|-------|------|------|------|
| **P1** (全局 P38) | DM 审批传入 `user_id` | enhancer 的 `send_exec_approval()` 已有降级：`_get_user_id_from_channel(chat_id)` 反查 user_id。Patch 让 run.py 多传参数是优化（省一次 API 调用），但**不是必需的**。 | 标记为可选，保留 patch（优化省一次 API 调用） |
| **P9** (全局 P53) | 幽灵代码围栏 | `truncate_message` 是 `BasePlatformAdapter` 的方法，理论上可覆写。但该方法 130+ 行，含 UTF-16 计量、inline code 拆分等复杂逻辑，覆写意味着复制整段上游代码并维护同步。 | **保留 shell patch** — 覆写代价远大于 patch，每次 Hermes 更新需对比 130 行变化 |

### 🔴 C 类：必须修改 Gateway 源码，无法在插件内实现

| Patch | 描述 | 原因 |
|-------|------|------|
| **P2** (全局 P57) | 工具进度消息进 Thread | 修改 `gateway/run.py` 中 `_progress_reply_to` 和 `_progress_thread_id` 的计算逻辑。当用户在 Channel 根级别发消息时 `source.thread_id=None`，gateway 不传 `reply_to` 也不传 `metadata.thread_id`，adapter 无法凭空生成 Thread 路由。**关键**：`_progress_thread_id` 走 else 分支 `= source.thread_id = None`，导致 `_progress_metadata = None`，enhancer 的 `metadata.thread_id` 降级方案根本不会被触发。 |
| **P3** (全局 P46) | Clarify Session 分裂 | 修改 gateway 内部 `_quick_key` vs `canonical_key` 匹配逻辑。`pre_gateway_dispatch` hook 可访问 `gateway` 和 `session_store`，但修改点在 try/except 块内，hook 无法精确介入。 |
| **P4** (全局 P46b) | Clarify 并发守护 | 拦截点在 session key 校验处，`pre_gateway_dispatch` hook 在更早位置触发。P4 需调用 `clarify_gateway.resolve_gateway_clarify()` 并 return None（阻止后续 dispatch），hook 的 skip/rewrite/allow 三种 action 无法表达「已消费」语义。 |
| **P5** (全局 P50) | 评论→正文合并 | 修改 `StreamConsumer` 内部 `_send_commentary` 调用逻辑。`StreamConsumer` 是 gateway 内部类，不由 adapter 创建，无法从插件端介入。 |
| **P7** (全局 P55) | stream fallback 丢 `reply_to` | 修改 `StreamConsumer._send_fallback_final` 的 `adapter.send()` 调用参数。同 P5，`StreamConsumer` 不由 adapter 控制。 |

### C 类共同特征

修改的是 gateway 调用方代码（run.py / stream_consumer.py），它们决定了「传给 adapter 什么参数」和「怎么处理消息流」，这些逻辑在 adapter 被调用之前就已执行完毕，插件覆写 adapter 方法无法影响上游决策。

### P2 替代路径分析

P2 当前修改 `_progress_reply_to`（让 `reply_to=event_message_id`）。另一种方案是修改 `_progress_thread_id`（像 Slack 一样 `= source.thread_id or event_message_id`），这样 `_progress_metadata = {"thread_id": event_message_id}`，enhancer 的 `metadata.thread_id` 降级方案就能工作——但两者都需要修改 `gateway/run.py`，patch 不可避免，只是改哪个变量的区别。当前方案（改 `_progress_reply_to`）更直接，因为它让 adapter 的 `send()` 在 `reply_to` 参数中直接收到 Thread root，不需要再经过 metadata 解析。

**注意**：如果改 `_progress_thread_id` 方案，Channel 根消息的 `event_message_id` 就是 Hermes 回复后创建的第一个帖子 ID，在 Mattermost 中这就是 Thread 的 root post，所以 `thread_id = event_message_id` 语义上是正确的。

### 总结

| 类别 | Patch 数 | 占比 | 行动 |
|------|---------|------|------|
| 🟢 不必要（插件已覆盖） | 2 (P6, P8) | 22% | 移除 shell patch，由插件 adapter 覆写实现 |
| 🟡 可优化但保留 Patch | 2 (P1, P9) | 22% | P1 可选/优化，P9 覆写代价 > patch |
| 🔴 必须源码 patch | 5 (P2, P3, P4, P5, P7) | 56% | 保留，提上游 PR |

## 当前双归属覆盖（7 项 P1-P9，P6/P8 已由插件 adapter 覆写替代）

插件脚本 `hermes-mattermost-enhancer.sh` 覆盖 7 项必须/可选源码 patch（P6/P8 已从脚本移除，由 enhancer adapter 覆写 `_ws_connect_and_listen` 和 `edit_message` 实现）。

| 插件 P# | 全局 P# | 文件 | 功能 | 分类 | 备注 |
|---------|---------|------|------|------|------|
| P1 | P38 | run.py | DM 审批传入 user_id | 🟡 可选 | 插件已有 `_get_user_id_from_channel` 降级，patch 为优化 |
| P2 | P57 | run.py | 工具进度进 Thread | 🔴 必须源码 | gateway 不传 `reply_to` 也不传 `metadata.thread_id` |
| P3 | P46 | run.py | Clarify Session 分裂 | 🔴 必须源码 | 修改 `_handle_message` 内部逻辑 |
| P4 | P46b | run.py | Clarify 并发守护 | 🔴 必须源码 | hook 无法表达「已消费」语义 |
| P5 | P50 | stream_consumer.py | 评论→正文合并 | 🔴 必须源码 | `StreamConsumer` 不由 adapter 创建 |
| P7 | P55 | stream_consumer.py | stream fallback 丢 reply_to | 🔴 必须源码 | `_send_fallback_final` 调用参数 |
| P9 | P53 | base.py | 幽灵代码围栏 | 🟡 保留 patch | 覆写 130+ 行 `truncate_message` 代价 > patch |
| ~~P6~~ | ~~P54~~ | ~~adapter.py~~ | ~~WebSocket 心跳~~ | 🟢 插件覆写 | adapter 覆写 `_ws_connect_and_listen(heartbeat=15.0)` |
| ~~P8~~ | ~~P56~~ | ~~adapter.py~~ | ~~_api_put timeout~~ | 🟢 插件覆写 | adapter 已完整覆写 `edit_message`（自带 30s timeout） |

**维护规则**：
1. 每次新增 Mattermost 相关 patch 到 `hermes-patches.sh` 时，必须同步添加到插件脚本并更新此表
2. 新增 patch 前先做**可消除性审查**：能否通过覆写 adapter 方法实现？能否通过 `pre_gateway_dispatch` hook 实现？只有确认不可能时才保留为源码 patch
