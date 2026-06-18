# Hermes Patches 上游合入检查 + 防误报 + _do_patch 规范

> 最后更新：2026-05-28 | 基准版本：`origin/main` (2d5dcfabc) — 经 `git show origin/main:<file>` 逐项验证

## 一、检查方法

### Step 1: 获取上游原始代码

**⚠️ 必须对比 `origin/main`，不是 `HEAD`**。`HEAD` 是当前工作副本（可能已打过本地 patch），只有 `origin/main` 才反映真正的上游状态。

```bash
cd ~/.hermes/hermes-agent
# ✅ 正确：对比上游
git show origin/main:<file> | grep '<check_pattern>'

# ❌ 错误：对比本地（本地可能已经打过 patch）
git show HEAD:<file> | grep '<check_pattern>'
```

### Step 2: 确认是本地修改还是上游合入

```bash
git status --short <file>        # M = 本地修改
git diff <file>                  # 对比差异
```

### Step 3: 确认后可安全移除

1. 从注册表删除条目
2. 从 `apply_all()` 删除对应代码块
3. 从 `check_status()` 删除对应检查
4. 更新 header 注释和 total 计数
5. `git checkout <file>` 还原（如果 upstream 已修复）

---

## 二、Check Pattern 防误报（⚠️ 关键）

### 问题

grep check pattern 是 patch 已生效的唯一判据。如果太宽，会命中上游已有但**不相关**的同名代码，导致假阳性——check 说"已修复"，实际上 patch 从未被应用。

### 已发生的误报案例

| Patch | 旧 pattern | 为什么误报 | 新 pattern |
|-------|-----------|-----------|-----------|
| 主脚本 3b | `not grp["models"]` | 上游有 `bool(api_key) or not grp["models"]`（不同语义） | `bool.*api_key.*and not grp["models"]` |
| 插件 P1 | `user_id=source.user_id` | 上游 3 处同名（task tracking / analytics，非审批传参） | `user_id=source.user_id.*hasattr` |

### 原则

**check pattern 必须包含 patch 的唯一签名**——不能只匹配子串，要匹配 patch 特有的上下文组合。

### 验证方法

```bash
git checkout <file>             # 回滚到上游
grep -q '<pattern>' <file>      # 应该 NO MATCH（0 行）
```

---

## 三、`_do_patch` 函数规范（⚠️ 关键）

### 问题

所有 Python heredoc patch 在两种情况下都 `exit(0)`：
- `print("APPLIED")` → 确实应用了
- `print("SKIP")` → 没应用（条件不满足）

只检查 `$?` 会把 SKIP 误判为成功。

### 正确实现

```bash
_do_patch() {
    # ... pre-check ...
    local output
    output=$(python3 - "$file" 2>&1)
    local rc=$?
    if [[ $rc -eq 0 && "$output" == *"APPLIED"* ]]; then
        ok "$label — applied successfully ✅（修复成功）"
    elif [[ $rc -eq 0 && "$output" == *"SKIP"* ]]; then
        ok "$label — skipped, code already matches（跳过，代码已符合预期）"
    else
        warn "$label — failed ❌（修复失败）"
        [[ -n "$output" ]] && echo "  $output"
    fi
    return $rc
}
```

---

## 四、Python 防重复条件（⚠️ 关键）

### 问题

Python heredoc 中 `"<substring>" not in content` 条件可能**永假**，导致 patch 永远 SKIP：

```python
# ❌ 永远 False——上游已有 3 处 user_id=source.user_id
if old in content and "user_id=source.user_id" not in content:
```

### 已发生的案例

插件 P1 审批传参——防重复条件是 `"user_id=source.user_id" not in content`，但上游 `gateway/run.py` 已有 3 处同名（task tracking / analytics），条件永假。配合 `_do_patch` 只看 `$?` 的 bug，P1 从第一天起就是"成功 SKIP"：

```
SKIP
[OK] Fix: approval card ... — applied successfully ✅   # ← 假！
```

修复后 `_do_patch` 正确报告：
```
[OK] Fix: approval card ... — skipped, code already matches（跳过）  # ← 真
```

### 原则

**防重复条件必须使用和 check pattern 相同的独特签名**：

```python
# ✅ 只匹配 patch 自身的完整行
if old in content and "user_id=source.user_id if hasattr" not in content:
```

---

## 五、当前状态（2026-05-28，已验证 origin/main）

> **验证方法**：每个 check pattern 均在 `git show origin/main:<file>` 上执行 `grep`。
> **结论：全部 12 个 patch（主脚本 7 + 插件 5）均未合入上游。** 本地 `check` 通过仅表示 patch 已在本机 apply。

### 主脚本 `hermes-patches.sh`（7 个，全部 NOT in origin/main）

| # | 文件 | 功能 | origin/main |
|---|------|------|:--:|
| 1 | `providers.py` | custom: provider 聚合器识别 | ❌ `is_aggregator` 无 `startswith("custom:")` |
| 2 | `doctor.py` | custom: provider vendor-prefix 假警告跳过 | ❌ 0 处匹配 |
| 3a | `model_switch.py` | models 白名单优先（user providers） | ❌ `if api_url and api_key and discover:` 缺 `and not models_list` |
| 3b | `model_switch.py` | models 白名单优先（custom_providers） | ❌ `should_probe` 仍是 `or not grp["models"]` |
| 5 | `cron/jobs.py` | `ensure_ascii=False` | ❌ 0 处匹配 |
| P50 | `stream_consumer.py` | 评论合并到正文缓冲区 | ❌ 0 处匹配 |
| P53 | `base.py` | 幽灵代码围栏修复 | ❌ 0 处匹配 |

### 插件脚本 `hermes-mattermost-enhancer.sh`（5 个，全部 NOT in origin/main）

| # | 文件 | 功能 | origin/main |
|:---:|------|------|:--:|
| P1 | `run.py` | DM 审批传入 user_id（可选） | ❌ 0 处匹配 |
| P2 | `run.py` | 工具进度消息进 Thread | ❌ 0 处匹配 |
| P3 | `run.py` | Clarify Session 分裂修复 | ❌ 0 处匹配 |
| P4 | `run.py` | Clarify 并发守护 | ❌ 0 处匹配 |
| P5 | `run.py` | auto-resume session 串台去重 | ❌ 0 处匹配 |

### ⚠️ 已知问题

#### 1. P55 误标为「上游已合入」

- **位置**：主脚本第 20 行、插件脚本第 24 行
- **声称**：`_send_fallback_final 已传 reply_to — ✅ 上游已合入`
- **事实**：`git show origin/main:gateway/stream_consumer.py` 第 800 行 `adapter.send()` 无 `reply_to` 参数
- **源 commit**：`126ef48`（分支 `fix/stream-fallback-thread-routing`），从未 merge 到上游
- **修复**：将两处注释从 "✅ 上游已合入" 改为 "⚠️ 待 PR（分支 fix/stream-fallback-thread-routing）"

#### 2. bf178fe (send_multiple_images Thread routing) 完全遗漏

- **源 commit**：`bf178fe`（分支 `fix/mm-media-thread-routing`）
- **修复内容**：`send_multiple_images()` 从 metadata 提取 `thread_id` 并注入 `root_id`
- **状态**：主脚本注释 "Mattermost 6 个 Patch → 迁移到插件"，但插件脚本**无对应 patch**
- **影响**：批量图片上传始终落到频道顶层，不进 Thread
- **修复**：需在插件脚本中新增此 patch

#### 3. P5 编号冲突

- 插件脚本注释区同时出现两个 P5：
  - 第 23 行：`❌ P5. 评论→正文合并 — 已迁回主脚本`（旧）
  - 第 26 行：`P5. Session 串台修复`（新）
- 历史原因：旧 P5 移走后新 P5 补充时未重新编号
- **修复**：旧注释改为 `❌ P5(old)` 或直接删除（已迁回主脚本的记录在 header 注释中即可）

#### 4. `_do_patch` 主脚本未遵循规范

`hermes-config-management` Skill 已明确要求捕获 stdout 以区分 APPLIED/SKIP，但主脚本 `hermes-patches.sh` 的 `_do_patch` 仍只检查 `$?`（exit code），未遵循规范。插件脚本 `hermes-mattermost-enhancer.sh` 已正确实现。

### 分工原则

| 放哪里 | 条件 |
|--------|------|
| `hermes-patches.sh` | 通用 Hermes Bug Fix，任何平台受益 |
| `hermes-mattermost-enhancer.sh` | 修改 `gateway/run.py` 调用方代码，`register_platform` API 无法触及 |
| ❌ 不放插件 | 平台无关修复（如 `stream_consumer.py` / `base.py`）——即使 Mattermost 触发了发现 |

---

## 六、输出格式规范

两个脚本统一使用以下格式：

```
═══════════════════════════════════════════════════
  🔍 Checking Hermes core patches...
     （正在检查 Hermes 核心补丁）
═══════════════════════════════════════════════════

  ── Built-in capabilities ... ──       # [INFO] 前缀，始终出现在最前面
[INFO]  WebSocket heartbeat 15s ...

  ── Check ①: ... ──                    # [OK]/[FAIL]/[OPT] 前缀
[OK]    Fix: ... — already applied, skipping（已经好了，跳过）

───────────────────────────────────────────────────
  Shell patches: X/Y required + Z optional
  （Shell 补丁：X/Y 必需 + Z 可选）
───────────────────────────────────────────────────
```

注册表 label 格式：
```
"<file>|Fix: <English description>（修复「中文描述」的问题）|<check_pattern>"
```
