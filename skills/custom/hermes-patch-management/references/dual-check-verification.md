# 双重验证检查清单

每次 Hermes 更新后，按此清单逐 patch 复核两个脚本。

## 基线记录

```bash
cd ~/.hermes/hermes-agent
git describe --tags                    # e.g. v2026.5.29-190-gaa32edcac
ORIGIN=$(git rev-parse origin/main)    # e.g. aa32edcac...
```

## 脚本 1: hermes-patches.sh

| # | 文件 | check_pattern | old_string 仍存在? | 结论 |
|---|------|--------------|:---:|------|
| 1 | `hermes_cli/model_switch.py` | `skip live /models discovery when` |   |   |
| 2 | `hermes_cli/model_switch.py` | `curated list takes priority over live discovery` |   |   |
| 3 | `cron/jobs.py` | `ensure_ascii=False` |   |   |
| 4 | `gateway/stream_consumer.py` | `Accumulate commentary` |   |   |
| 5 | `gateway/platforms/base.py` | `reopening the fence would create` |   |   |
| 6 | `gateway/stream_consumer.py` | `ML:content=chunk,\n.*reply_to=self._initial_reply_to_id` |   |   |
| 7 | `utils.py` | `m.startswith.*minimax` |   |   |
| 8 | `gateway/run.py` | `cross-thread routing` |   |   |
| 9 | `gateway/run.py` | `cross-thread interrupt` |   |   |

## 脚本 2: hermes-mattermost-enhancer.sh

| # | 文件 | check_pattern | old_string 仍存在? | 结论 |
|---|------|--------------|:---:|------|
| P1 | `gateway/run.py` | `or source.platform == Platform.MATTERMOST` |   |   |
| P2 | `gateway/run.py` | `_canonical_entry = self.session_store.get_or_create_session` |   |   |
| P3 | `gateway/run.py` | `Gateway intercepted clarify at session guard` |   |   |
| P4 | `gateway/run.py` | `Deduplicate.*keep only the most recent` |   |   |
| P5 | `gateway/run.py` | `Fallback: use _progress_thread_id when thread_metadata returns None` |   |   |

## 验证命令模板

### 维度 A：check_pattern 命中？

```bash
# 标准 grep
git show origin/main:<file> | grep -c '<check_pattern>'

# ML 跨行模式 — 用文件中转 + heredoc，避免 python3 -c "..." 的 bash 转义问题
git show origin/main:<file> > /tmp/_check_dim_a.py
python3 <<'PYEOF'
import re
with open('/tmp/_check_dim_a.py') as f:
    content = f.read()
print('MATCH' if re.search(r'<ml_pattern>', content) else 'NO MATCH')
PYEOF
```

### 维度 B：old_string 仍存在？

从 patch 脚本的 Python heredoc 中提取 `old` 变量的完整字符串，然后：

```bash
git show origin/main:<file> > /tmp/_chk.py
python3 << 'PYEOF'
with open('/tmp/_chk.py') as f:
    content = f.read()
old = '''<exact old_string from heredoc>'''
if old in content:
    print('YES — old_string exists')
else:
    print('NO — old_string not found, patch will SKIP')
PYEOF
```

### 批量验证（推荐）

当 patch 数量较多时，用 Python 脚本一次性遍历所有 patch 比逐条手工 grep 更高效且不易遗漏：

```python
import subprocess, re

def get_origin_file(rel_path):
    result = subprocess.run(
        ["git", "show", f"origin/main:{rel_path}"],
        capture_output=True, text=True, cwd="~/.hermes/hermes-agent"
    )
    return result.stdout if result.returncode == 0 else None

# 将每个 patch 定义为 {id, file, check, check_ml, old} dict
# 统一遍历输出 A/B 双维度结果表格
```

模板：直接使用 patch 脚本中 Python heredoc 的三引号 old 字符串（`'''...'''`），复制后作为 Python dict 的 old 字段，无需手动转义。

## 示例：2026-05-30 验证记录

- **Hermes 版本**：v2026.5.29-190-gaa32edcac（上次验证 v2026.5.16）
- **origin/main**：aa32edcac
- **结果**：14/14 check_pattern 未命中 → 全部未合入；14/14 old_string 仍存在 → 全部可 apply
- **特殊发现**：`providers.py` 的 `is_aggregator()` 上游已重构为 `pdef.is_aggregator` 委托模式，但 old_string（函数签名+docstring 前三行）未变，patch 仍可正常 apply。功能不受影响，因为 `startswith("custom:")` 检查插入在 `pdef = get_provider(provider)` 之前，return 语句保持不变。

## 示例：2026-06-08 验证记录

- **Hermes 版本**：v2026.6.5-181-gc98637723（上次验证 v2026.5.29）
- **origin/main**：c98637723
- **结果**：
  - 8/8 check_pattern 未命中 → 全部未合入
  - 7/8 old_string 仍存在 → 可 apply
  - **1 个需重写**：model_switch.py Patch 4（custom_providers 白名单）

### Patch 4 重写详情

**原因**：上游将 `should_probe` 从单行改为多行括号表达式，且新增了 `and grp.get("discover_models", True)` 条件。

**新 old_string**：
```python
            should_probe = (
                bool(api_url)
                and (bool(api_key) or not grp["models"])
                and grp.get("discover_models", True)
            )
```

**新 new_string**（逻辑变更不变：`or` → `and`）：
```python
            # Only run live discovery when the user has NOT supplied
            # a curated model list AND has credentials. A non-empty
            # curated list takes priority over live discovery.
            should_probe = (
                bool(api_url)
                and bool(api_key)
                and not grp["models"]
                and grp.get("discover_models", True)
            )
```

### 假阴性教训（Patch 8）

Patch 8（fallback Thread 路由）的维度 B 检查首次使用 `python3 -c` + pipe 方式时返回 `NO`。改用文件中转 + heredoc 方式后确认 `YES`——old_string 存在，patch 可正常 apply。这是 `python3 -c` + 管道转义的经典假阴性案例，已纳入 SKILL.md 已知陷阱。

### `\\n` 转义陷阱（P3 静默 SKIP）

2026-06-08 维度 B 验证发现 P3（Clarify 并发守护）的 `old_string` 在文件中转方式下仍返回 `NO`。根因：patch 脚本的 Python heredoc 中使用了双引号字符串 `"line1\\nline2"`——`\\n` 是字面量两个字符 `\` + `n`，而目标文件中的两行之间是真实换行符 `\n` (0x0a)，匹配永远失败。**P3 从未真正 apply 成功**，但 `_do_patch()` 误判为 SKIP。修复：将 old/new 字符串全部改为三引号（`"""..."""`）。教训：所有 Python heredoc 中的多行字符串一律使用三引号；维度 B 验证代码本身也应使用三引号。详见 `references/backslash-n-escape-bug.md`。

### providers.py 重构观察

`is_aggregator()` 上游从内联逻辑重构为 `pdef.is_aggregator` 委托模式。但 `get_provider("custom:xxx")` 返回的 `ProviderDef` 仍硬编码 `is_aggregator=False`（第 576/638/653 行），bug 本质未修复。Patch 1 的 old_string 仅在函数签名 + `pdef = get_provider(provider)` 处匹配（不包含后续的 return 行），仍可正常 apply。

## 示例：2026-06-11 验证记录

- **Hermes 版本**：v2026.6.5-617-g955fa4006（上次验证 v2026.6.5-181）
- **origin/main**：955fa4006（== HEAD，已是最新）
- **结果**：
  - **2 个已合入**（功能等价实现，应移除）：P1 providers.py、P2 doctor.py
  - **6 个未合入 + old_string 仍存在**（保留）：P3–P8
  - **1 个需重写**：P9 run_agent.py（MiniMax tokens）

### P1 & P2：上游等价实现（首次发现此模式）

| Patch | 我们的实现 | 上游等价实现 |
|-------|----------|------------|
| P1 `providers.py` | `if provider.startswith("custom:"): return True` 直接插入 `is_aggregator()` | 先 `normalize_provider()` 再 `provider_norm.startswith("custom:")` |
| P2 `doctor.py` | `and not provider_for_policy.startswith("custom:")` 从警告中排除 | `or provider_policy_id.startswith("custom:")` 加入 `provider_accepts_vendor_slug` 白名单 |

两处均需阅读上游代码确认等价性，而非仅依赖 grep。这是与「确切相同代码被合入」不同的模式，已补充到 SKILL.md §4.2。

### P9：需重写 — 上游重构提取了辅助函数

**根因**：上游将 `_max_tokens_param()` 的判断逻辑从内联 URL 检查重构为委托 `model_forces_max_completion_tokens(self.model)` 函数（`utils.py`）。

**现状**：
- 旧 old_string（含原 docstring + `if self._is_direct_openai_url()...`）在上游**不存在**
- `model_forces_max_completion_tokens()` 仅覆盖 OpenAI 家族（gpt-4o/4.1/5/o1/o3/o4），**不含 MiniMax**
- 上游 docstring 甚至提到了 MiniMax（「MiniMax's OpenAI-compatible models also reject the legacy key」），但未在函数中实现

**建议重写方案**：在 `utils.py` 的 `model_forces_max_completion_tokens()` 中新增：
```python
or m.startswith("minimax")
```
跟随上游重构方向，将修复集中到辅助函数而非调用点。

### Patch 8 ML 检查验证

手动执行 Python re.search 确认 `_send_fallback_final` 的 chunk 发送循环仍缺少 `reply_to=self._initial_reply_to_id`，check pattern 正确未命中。old_string 精确存在，patch 可正常 apply。

## 示例：2026-06-17 验证记录

- **Hermes 版本**：v2026.6.5-1117-g17251e865（上次验证 v2026.6.5-617，+500 commits）
- **origin/main**：17251e865（== HEAD）
- **结果**：
  - 8/9 check_pattern 未命中 → 全部未合入
  - 8/9 old_string 仍存在 → 可 apply
  - **1 个需重写**：P6 `stream_consumer.py`（fallback send Thread 路由）

### P6 重写详情

**原因**：上游将 `_send_fallback_final()` 中的 `metadata=self.metadata` 重构为 `metadata=self._metadata_for_send(final=True)`（commit `6373aba80` / `fc956b9db` — tool_progress_style 功能）。参数包装器调用发生在 `send()` 的兄弟参数位置，不影响代码结构。

**关键观察**：check pattern（`ML:content=chunk,\n.*reply_to=self._initial_reply_to_id`）不需改动——patch 应用前后该跨行引用不变，因为 `reply_to` 是新增行而非已有行的修改。

**上游当前代码**（`gateway/stream_consumer.py` L915-919）：
```python
                result = await self.adapter.send(
                    chat_id=self.chat_id,
                    content=chunk,
                    metadata=self._metadata_for_send(final=True),  # 变了
                )
```

**新 old_string**：
```python
                result = await self.adapter.send(
                    chat_id=self.chat_id,
                    content=chunk,
                    metadata=self._metadata_for_send(final=True),
                )
                if result.success:
                    break
                if attempt == 0 and self._is_flood_error(result):
```

**新 new_string**（加 `reply_to=self._initial_reply_to_id`）：
```python
                result = await self.adapter.send(
                    chat_id=self.chat_id,
                    content=chunk,
                    reply_to=self._initial_reply_to_id,
                    metadata=self._metadata_for_send(final=True),
                )
                if result.success:
                    break
                if attempt == 0 and self._is_flood_error(result):
```

### 兄弟参数包装器重构模式

上游将裸属性 `self.metadata` 替换为包装器方法 `self._metadata_for_send(final=True)`——这是首次遇到的 old_string 断裂原因类型。与「代码提取到命名函数」不同，这里的整体结构未变，仅一个参数表达式变了。特征：`git diff` 显示代码块形状相同，仅 `self.metadata` → `self._metadata_for_send(...)` 一字之差。当维度 B 失败但 `git show` 的代码结构看似相似时，应优先检查是否存在参数级别的表达式变更。

### 批量验证脚本

本次验证使用单个 Python 脚本一次性检查全部 9 个 patch（而非逐条手工 grep），确认全部结果无遗漏。脚本结构已加入上文「批量验证（推荐）」模板。该方式消除了手工逐条验证时 `exit code 1 = 0 matches` 被误判为错误的噪音。

### P3 安全通过：atomic write 不影响 old_string

上游 `e5b4cf7be` 改写了 `cron/jobs.py` 的 `json.dump` 上下文——将直接写入改为 `tempfile.mkstemp` + `os.fsync` + `atomic_replace` 原子模式。`json.dump` 行后新增了 `os.fsync(f.fileno())`，但 P3 的 old_string 只匹配到 `f.flush()`（不含后续行），`old in content` 仍为 True——字符串包含关系不受后续内容影响。这是「跨进程写入安全重构」的典型案例，已纳入 SKILL.md §7 已知陷阱。

## 示例：2026-06-17 Mattermost Enhancer 插件验证

- **Hermes 版本**：v2026.6.5-1117-g17251e865（上次验证 v2026.6.5-838，+660 commits）
- **origin/main**：17251e865（== HEAD）
- **插件脚本**：`hermes-mattermost-enhancer.sh`（5 个 patch，全部修改 `gateway/run.py`）
- **结果**：
  - 4/5 old_string 仍存在 → P1-P4 保留
  - **P5 Part A 已合入**（`_resolve_progress_thread_id()` 函数内已包含 `"mattermost"`），Part B 仍需保留（`_status_thread_metadata` 未同步修复）
  - 插件 adapter 源码无需适配（bundled MM adapter 接口兼容）

### P5 重写详情：多部分 patch 的部分合入

P5 原为双部分 patch：Part A 修复 `_progress_thread_id`，Part B 修复 `_status_thread_metadata`。

**Part A → 委托函数已修复，可移除**：上游将原来的 if/else 代码块替换为 `_resolve_progress_thread_id()` 函数调用，old_string 断裂。但该函数内部已包含 `{"slack", "mattermost"}` 的 `event_message_id` 降级逻辑，与 Part A 修复完全等价。

**Part B → 仍需保留**：`_status_thread_metadata` 上游未同步修复（`_thread_metadata_for_source` 对 channel-root 返回 `None`），`or {"thread_id": _progress_thread_id}` 降级仍然必需。

**check_pattern 更新策略**：旧 check_pattern 对应 Part A 的代码（`source.platform == Platform.MATTERMOST and not source.thread_id`），Part A 移除后该 pattern 将永远检查失败。解决方案：在 Part B 的新代码中插入唯一注释（`# Fallback: use _progress_thread_id when thread_metadata returns None`），用注释字符串作为新 check_pattern。

**关键教训**：当多部分 patch 的某部分被上游合入且其余部分仍需保留时：
1. 移除已合入部分的 Python heredoc 代码
2. 更改 check_pattern 以匹配剩余部分的唯一代码（优先插入新注释）
3. 更新 Header 描述和验证标注
4. **不要**保持旧的 check_pattern 而去掉对应的 old_string——那会导致 check 永远失败

## 示例：2026-06-20 验证记录

- **Hermes 版本**：v2026.6.19-51-gb88d0007c9（上次验证 v2026.6.5-1117，+168 commits）
- **origin/main**：b88d0007c9
- **验证方式**：execute_code 批量脚本（9 个 patch 一次性双维度检查）
- **结果**：
  - 9/9 check_pattern 未命中 → 全部未合入
  - 8/9 old_string 仍存在 → 可 apply
  - **1 个需重写**：P1 `model_switch.py`（user providers 白名单）

### P1 重写详情：内联中间变量引入重构

**触发 commit**：`1039e90b5 fix(model-switch): probe /v1/models for providers without api_key`

上游将 user providers 区域的单行条件 `if api_url and api_key and discover:` 重构为带 `has_explicit_models` 中间变量的多行表达式。这是与「委托函数提取」「兄弟参数包装器」不同的第三种 old_string 断裂模式——上游在原地用新变量重写了条件逻辑。

**上游新代码**：
```python
            has_explicit_models = bool(models_list)
            should_probe = bool(api_url) and discover and (
                bool(api_key) or not has_explicit_models
            )
            if should_probe:
```

**关键风险**：上游的新逻辑 `bool(api_key) or not has_explicit_models` 意为「有 api_key 就总是探测」——这正是我们 patch 要修复的问题（ZenMux 聚合器有 api_key + 配了 `models:` 白名单子集，上游用 `/models` 完整目录覆盖了白名单）。上游注释明确写道 `With an api_key: always probe`，这是 aggregator-gateway 场景的设计意图，但与「尊重用户显式列表」的需求矛盾。

**重写方案**：利用上游引入的 `has_explicit_models` 变量重新表达修复逻辑：

新 old_string（匹配上游当前代码）：
```python
            has_explicit_models = bool(models_list)
            should_probe = bool(api_url) and discover and (
                bool(api_key) or not has_explicit_models
            )
            if should_probe:
```

新 new_string（有显式列表就不探测）：
```python
            has_explicit_models = bool(models_list)
            # Curated list takes priority — skip live /models discovery when
            # the user supplied an explicit models list, regardless of api_key.
            # Prevents aggregator endpoints from overwriting a curated subset
            # with their full catalog.
            should_probe = bool(api_url) and discover and not has_explicit_models
            if should_probe:
```

新 check_pattern：`skip live /models discovery when`（与 P2 的 `curated list takes priority over live discovery` 不冲突）。

**逻辑改进**：新逻辑 `not has_explicit_models` 比旧 patch 的 `api_key and not models_list` 更优——保留了裸端点（Ollama/llama.cpp，无 api_key）的探测能力。对比 P2（custom_providers）现有 patch 逻辑 `bool(api_key) and not grp["models"]`，两者目标相同但 P2 仍要求 api_key；后续可考虑将 P2 也改为 `not grp["models"]` 以保持两区域一致。

### 验证表格更新

P1 重写后 check_pattern 从 `and not models_list` 变更为 `skip live /models discovery when`，更新本文件顶部表格第 1 行。
