# Hermes Patch 生命周期管理

## 核心原则

> **上游修复 → 直接删除 patch，不要添加兼容层。**

本地 patch 脚本的本质是填补上游缺口。缺口一旦被上游修复，patch 就没有存在意义了。保留"检测新版跳过"的兼容代码是自欺欺人——增加维护负担，且阻碍对"未修复"状态的真实判断。

## 反面案例：P57（hermes-mattermost-enhancer.sh Patch 2 — 不验证就删除）

### 背景

Hermes v0.14.0 上游将 Mattermost 工具进度路由从：
```python
if source.platform == Platform.FEISHU and source.thread_id and event_message_id
```
改为：
```python
if source.platform in (Platform.FEISHU, Platform.MATTERMOST) and source.thread_id and event_message_id
```

commit `73439a4` 看到 changelog 声明"fixed Mattermost progress thread routing"，就直接删除了 Patch 2。

### 严重后果

上游"修复"保留了 `source.thread_id` 条件。当用户在 **Channel 根级别发消息**时，`source.thread_id` 为 None（Thread 是 Hermes 回复后才创建的），导致 `_progress_reply_to` 仍为 None，工具进度消息全部泄露到频道根级别。**等价于没有修复。**

正确逻辑：对 Mattermost 只要求 `event_message_id`，不要求 `source.thread_id`，因为 adapter 内部的 `_resolve_root_id` + metadata fallback 会处理 Thread 路由。

### 根因

仅凭 changelog 声明或上游 commit message 就删除本地 patch，没有验证上游修复的完整语义。

### 修复

恢复 Patch 2（`patch_progress_thread`），`hermes-patches.sh` 注册为 P57。插件 v2.3.0 发布。

### 教训规则

**删除本地 patch 前必须验证上游修复的完整语义：**

1. **读源码**：在源码中确认上游修复的条件分支覆盖了所有本地 patch 覆盖的场景
2. **端到端测试**：至少做一次实际测试，验证删除 patch 后功能正常
3. **不要信任 changelog**：changelog 声明"fixed"不等于真正修复了所有边界情况

## Patch 删除 Checklist

当确认上游已修复某个本地 patch 时：

- [ ] 删除 patch 函数体
- [ ] 删除 `apply_all()` 中的调用
- [ ] 删除 `check_status()` 中的检查条目（减少 total）
- [ ] 重新编号后续 Check/Patch 注释
- [ ] 更新 header 注释（标注「已移除」）
- [ ] 更新 `_patch_registry`（如适用）
- [ ] 减 1 对应的计数变量

## 新增 Patch Checklist

- [ ] 在 `apply_all()` 中添加 `_do_patch` 调用
- [ ] 在 `_patch_registry` 中添加注册条目（`file_rel|label|check_grep_pattern`）
- [ ] `check_grep` 选取单行内可匹配的子串（跨行 grep 不生效）
- [ ] `_do_patch` 的 check 字符串与 registry 保持一致
- [ ] 更新 header 注释的 patch 清单
- [ ] 运行 `check` 验证通过

## 双脚本同步原则

`hermes-patches.sh`（全局）和 `hermes-mattermost-enhancer.sh`（插件）必须**同步覆盖所有 Mattermost 关键 patch**。原因：第三方用户只有插件脚本，没有全局脚本——插件脚本遗漏 = 第三方用户功能缺失。

**同步检查**：每次修改 `hermes-patches.sh` 中涉及 Mattermost 的 patch 后，必须检查插件脚本是否也需要同步更新。具体而言，以下 hermes-patches.sh 中的 patch 必须同时出现在插件脚本中：

| hermes-patches.sh 编号 | 插件脚本编号 | 功能 |
|------------------------|------------|------|
| P46/P46b | P3/P4 | Clarify Session 分裂 + 并发守护 |
| P50 | P5 | 评论→正文合并 |
| P53 | P9 | 幽灵代码围栏 |
| P54 | P6 | WebSocket 心跳优化 |
| P55 | P7 | stream fallback 丢失 reply_to |
| P56 | P8 | _api_put 缺少 timeout |
| P57 | P2 | 工具进度消息进 Thread |

**血泪教训**：commit `73439a4` 只更新了 `hermes-patches.sh`，插件脚本因"上游已修复"误删 Patch 2。后续新增 P53-P57 时仅添加到全局脚本，插件脚本遗漏了 5 项关键 patch（P5/P6/P7/P8/P9），直到用户报告工具调用不在 Thread 中才发现。

## 模拟全新安装验证

每次修改插件脚本后，必须验证在全新安装场景下所有 patch 能正确应用：

```bash
cd ~/.hermes/hermes-agent
git stash --include-untracked      # 还原原始上游代码
echo "n" | bash ~/.hermes/plugins/mattermost-enhancer/scripts/hermes-mattermost-enhancer.sh apply
bash ~/.hermes/plugins/mattermost-enhancer/scripts/hermes-mattermost-enhancer.sh check
# 期望：9/9 passed（7 源码 patch + 2 adapter 覆写检查）
git checkout -- . && git stash pop  # 恢复本地完整 patch 状态
```

---

## hermes-patches.sh 全量过时审查（2026-05-30）

对比 Hermes v0.14.0 当前源码，逐项 grep 验证 14 个 patch 状态：

| # | 文件 | 修复内容 | 上游状态 | grep 验证 |
|---|------|---------|:--:|------|
| 1 | providers.py | custom: is_aggregator | ✅ 上游 | `startswith("custom:")` L498 |
| 2 | doctor.py | vendor-prefix 假阳性 | ✅ 上游 | `startswith("custom:")` L703 |
| 3a | model_switch.py | models 白名单优先 | ✅ 上游 | `and not models_list` L1530 |
| 3b | model_switch.py | custom_providers 白名单 | ✅ 上游 | `and not grp["models"]` L1713 |
| 4a | config.py | restart_notification bridge | ✅ 上游 | L871-872 |
| 4b | config.py | extra fallback | ✅ 上游 | `_grn = data.get(...)` L329 |
| 7 | cron/jobs.py | ensure_ascii=False | ✅ 上游 | L461 |
| 8 | utils.py | allow_unicode=True | ✅ 上游 | L173-174 |
| 9a | run.py | MEDIA 正则收紧 | ✅ 上游 | `_TOOL_MEDIA_RE` L16944/17250 |
| 9b | base.py | 移除 `\|\\S+` 兜底 | ✅ 上游 | L2416 不再有 fallback |
| P50 | stream_consumer.py | 评论→正文合并 | ✅ 上游 | `Accumulate commentary` L588 |
| P53 | base.py | 幽灵代码围栏 | ✅ 上游 | `reopening the fence` L4152 |
| P55 | stream_consumer.py | fallback reply_to | ✅ 上游 | `self._initial_reply_to_id` L805 |
| P57 | run.py | 进度消息 Thread 路由 | ⚠️ 部分 | 上游加了 MATTERMOST 但保留 thread_id 条件 |

### P57 详解

上游"修复"（L16067）：
```python
if source.platform in (Platform.FEISHU, Platform.MATTERMOST) and source.thread_id ...
```
对 Mattermost 仍要求 `source.thread_id` 非空 → Channel 根帖时 `thread_id` 为 None → `_progress_reply_to = None`。

但 enhancer 插件 `send()` 中的 `metadata.thread_id` fallback 已覆盖此场景——`_progress_metadata` 会携带 `thread_id`，即使 `_progress_reply_to` 为 None，adapter 也能通过 metadata 正确路由到 Thread。**所以在插件生效时 P57 不触发实际问题。**

### 结论

13/14 上游已完全修复，P57 被 enhancer 降级方案覆盖。
**hermes-patches.sh 整体过时，建议移除或归档到 `references/`。**

注意：`git stash pop` 可能与 apply 产生的修改冲突，此时先 `git checkout -- .` 丢弃 apply 的修改再 pop。

## 补丁验证方法论：old-string 存在性对比

验证 `hermes-patches.sh` 中所有补丁在代码库中的实际状态时，使用以下三分类法：

### 步骤

1. **提取每个补丁的 `old` 字符串**（即 `_do_patch` 中被替换的原始文本）
2. **对比两个版本**：
   - **committed 版本**：`git show HEAD:<file>` — 上游原始代码
   - **current 版本**：工作区文件 — 包含已应用的 patch
3. **按 `old` 存在性分类**：

| `old` 在 committed | `old` 在 current | 判定 | 含义 |
|:--:|:--:|------|------|
| ✅ | ❌ | ✅ PATCHED | 补丁已正确应用（old 被替换为 new） |
| ❌ | ❌ | 🟡 OBSOLETE | 上游已重写相关代码，old 不再存在，补丁无意义 |
| ✅ | ✅ | ❌ NOT APPLIED | 补丁尚未应用（old 仍在） |

### 关键注意事项

- **忽略工作区未提交修改**：用户可能已通过 patch 脚本修改了源码，但这些修改尚未 commit。验证时应对比 `committed` 和 `current`，而非用 `git diff`
- **OBSOLETE 补丁**：`_do_patch` 在 `old` 不存在时会 SKIP，不会造成错误，但增加维护噪音。建议定期清理
- **P53 幽灵围栏假阳性**：Python 转义可能导致字符串匹配失败，需用 `grep` 行号比对交叉验证
- **批量验证用 execute_code**：15+ 个补丁的手动比对易出错，建议用 Python 脚本自动化：提取 old → 逐文件检查 → 生成分类报告

### 示例代码框架

```python
# 伪代码 — 批量验证 hermes-patches.sh 补丁状态
for patch in patches:
    committed = subprocess.check_output(['git', 'show', f'HEAD:{file}'])
    current = open(file).read()
    old_in_committed = patch.old in committed
    old_in_current = patch.old in current

    if old_in_committed and not old_in_current:
        status = "PATCHED"
    elif not old_in_committed and not old_in_current:
        status = "OBSOLETE"
    else:
        status = "NOT APPLIED"
```

## 涉及文件

| 脚本 | 用途 |
|------|------|
| `~/.hermes/scripts/hermes-patches.sh` | 全局 patch（provider/doctor/config/cron/MEDIA/base.py/adapter.py） |
| `~/.hermes/plugins/mattermost-enhancer/scripts/hermes-mattermost-enhancer.sh` | Mattermost 专属 patch（P1-P9 共 9 项，必须与全局脚本同步覆盖） |
