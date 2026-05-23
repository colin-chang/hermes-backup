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
