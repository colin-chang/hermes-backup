#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════
# Hermes Patches — 手动修复脚本
# ═══════════════════════════════════════════════════════════════════════════
#
# 背景：
#   当 hermes-agent 上游版本更新后，本地修改会被覆盖，
#   此脚本用于一键还原以下 patch。
#
#   活跃 patch（当前 9 个）：
#     1.  hermes_cli/model_switch.py        — config 白名单优先于线上拉取（user providers）
#     2.  hermes_cli/model_switch.py        — 同上（custom_providers）
#     3.  cron/jobs.py                      — Cron job 中文存储修复
#     4.  gateway/stream_consumer.py        — P50: 评论→正文合并，防止消息碎片化
#     5.  gateway/platforms/base.py         — P53: truncate_message 幽灵代码围栏修复
#     6.  gateway/stream_consumer.py        — P55: fallback send 保留 Thread 路由
#     7.  utils.py                          — P59: MiniMax max_completion_tokens 修复
#     8.  gateway/run.py                    — P60a: 中断跨线程 session source 覆盖修复
#     9.  gateway/run.py                    — P60b: 中断跨线程 thread metadata 丢失修复
#
#   已消除（上游已合入或不再需要）：
#     ✅ gateway/config.py             — 上游已合入（gateway_restart_notification）
#     ✅ utils.py                      — 上游已合入（yaml_rt.allow_unicode = True）
#     ✅ MEDIA 正则收紧                 — 上游代码重构，不再需要单独 patch
#     ✅ providers.py (is_aggregator)  — 上游已合入（normalize_provider + startswith("custom:")）
#     ✅ doctor.py (vendor-prefix)     — 上游已合入（provider_accepts_vendor_slug 白名单）
#     ⚠️  Mattermost 专属修复           — 已迁移至 mattermost-enhancer 插件脚本
#
#   版本感知：
#     最后验证: 2026-06-17
#     Hermes 版本: v2026.6.5-1117-g17251e865 (origin/main)
#     验证方式: 双重验证（check_pattern + old_string match）
#
#   已验证（v2026.6.5-1117 / origin:main=17251e865）：
#     providers.py                          — ✅ 上游已合入，移除
#     doctor.py                             — ✅ 上游已合入，移除
#     model_switch.py (user providers)      — ❌ 未合入，old_string ✅ 仍匹配
#     model_switch.py (custom_providers)    — ❌ 未合入，old_string ✅ 仍匹配
#     cron/jobs.py                          — ❌ 未合入，old_string ✅ 仍匹配
#     stream_consumer.py (commentary)       — ❌ 未合入，old_string ✅ 仍匹配
#     base.py (ghost fence)                 — ❌ 未合入，old_string ✅ 仍匹配
#     stream_consumer.py (fallback thread)  — ❌ 未合入，old_string ✅ 已重写（上游改为 _metadata_for_send 包装）
#     utils.py (minimax tokens)             — ❌ 未合入，old_string ✅ 仍匹配
#     run.py (P60a session source)          — ❌ 未合入，old_string ✅ 仍匹配
#     run.py (P60b thread metadata)         — ❌ 未合入，old_string ✅ 仍匹配
#
# 使用方法：
#   ./hermes-patches.sh check   # 检查当前状态（默认）
#   ./hermes-patches.sh apply   # 应用所有 patch
#   ./hermes-patches.sh status  # 同 check
#
# ═══════════════════════════════════════════════════════════════════════════

set -euo pipefail

AGENT_DIR="${HOME}/.hermes/hermes-agent"

# ── 颜色 ──────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

info()   { echo -e "${CYAN}[INFO]${NC}  $1"; }
ok()     { echo -e "${GREEN}[OK]${NC}    $1"; }
warn()   { echo -e "${YELLOW}[WARN]${NC}  $1"; }
error()  { echo -e "${RED}[ERROR]${NC} $1"; }

# ═══════════════════════════════════════════════════════════════════════════
# Patch 注册表 — 单一数据源，apply 和 status 共用
# 格式: "file_rel_path | label | check_grep_pattern"
#   ML: 前缀 → 跨行匹配（python3 re.search）
# ═══════════════════════════════════════════════════════════════════════════

_patch_registry=(
    "hermes_cli/model_switch.py|Fix: model whitelist ignored — user providers（修复「模型白名单没生效」的问题）|and not models_list"
    "hermes_cli/model_switch.py|Fix: model whitelist ignored — custom_providers（同上 — custom_providers 白名单）|curated list takes priority over live discovery"
    "cron/jobs.py|Fix: Chinese text garbled in cron jobs（修复「定时任务中文变乱码」的问题）|ensure_ascii=False"
    "gateway/stream_consumer.py|Fix: commentary fragmentation（修复「回复碎成很多条消息」的问题）|Accumulate commentary"
    "gateway/platforms/base.py|Fix: ghost fence in long code blocks（修复「长代码块出现幽灵空围栏」的问题）|reopening the fence would create"
    "gateway/stream_consumer.py|Fix: fallback send loses thread routing（修复「fallback 发送时 Thread 路由丢失」的问题）|ML:content=chunk,\\n.*reply_to=self._initial_reply_to_id"
    "utils.py|Fix: MiniMax max_completion_tokens（修复「MiniMax 模型参数错误」的问题）|m.startswith.*minimax"
    "gateway/run.py|Fix: session source clobbered by cross-thread interrupt（修复「中断时 session source 被跨线程覆盖」的问题）|cross-thread routing"
    "gateway/run.py|Fix: thread metadata lost after cross-thread interrupt（修复「中断后 thread metadata 丢失」的问题）|cross-thread interrupt"
)

# ═══════════════════════════════════════════════════════════════════════════
# 辅助函数
# ═══════════════════════════════════════════════════════════════════════════

#   heredoc 必须是完整的 Python 脚本，用 sys.argv[1] 获取文件路径，
#   输出 "APPLIED" 或 "SKIP"。
#   返回 0 = 已应用或成功；返回 1 = 文件不存在或失败
_do_patch() {
    local file="${AGENT_DIR}/$1"
    local label="$2"
    local check="$3"

    if [[ ! -f "$file" ]]; then
        error "$1 not found, skipped（文件不存在，已跳过）"
        return 1
    fi

    # ML: prefix → multiline check via python3
    if [[ "$check" == ML:* ]]; then
        local ml_pattern="${check#ML:}"
        if python3 -c "
import sys, re
with open('$file') as f:
    content = f.read()
sys.exit(0 if re.search('$ml_pattern', content) else 1)
" 2>/dev/null; then
            ok "$label — already applied, skipping（已经好了，跳过）"
            return 0
        fi
    elif grep -q "$check" "$file" 2>/dev/null; then
        ok "$label — already applied, skipping（已经好了，跳过）"
        return 0
    fi

    python3 - "$file"
    local rc=$?
    if [[ $rc -eq 0 ]]; then
        ok "$label — applied successfully（修复成功）"
    else
        error "$label — failed, check if Hermes is properly installed（修复失败，请检查 Hermes 是否正常安装）"
    fi
    return $rc
}

# ═══════════════════════════════════════════════════════════════════════════
# apply_all — 应用所有 patch
# ═══════════════════════════════════════════════════════════════════════════

apply_all() {
    info "Applying Hermes core patches...（正在安装 Hermes 核心补丁）"

    # ── 1. model_switch.py (两处) ─────────────────────────────────────────
    local sw_file="${AGENT_DIR}/hermes_cli/model_switch.py"
    if [[ ! -f "$sw_file" ]]; then
        error "hermes_cli/model_switch.py 不存在，跳过"
    else
        local sw_ok=0

        # 1a. user providers
        _do_patch "hermes_cli/model_switch.py" \
            "Fix: model whitelist ignored — user providers（修复「模型白名单没生效」的问题）" \
            'and not models_list' <<'PYEOF'
import sys
file_path = sys.argv[1]
with open(file_path, 'r') as f:
    content = f.read()

old = '''            # Prefer the endpoint's live /models list when credentials are
            # available, unless the provider explicitly opts out via
            # discover_models: false (e.g. dedicated endpoints that expose
            # the entire aggregator catalog via /models).
            api_key = str(ep_cfg.get("api_key", "") or "").strip()
            if not api_key:
                key_env = str(ep_cfg.get("key_env", "") or "").strip()
                api_key = os.environ.get(key_env, "").strip() if key_env else ""
            discover = ep_cfg.get("discover_models", True)
            if isinstance(discover, str):
                discover = discover.lower() not in {"false", "no", "0"}
            if api_url and api_key and discover:'''

new = '''            # Prefer the curated list when available; only fall back to
            # live discovery if the user hasn't supplied an explicit list
            # (via ``discover_models: false`` to suppress discovery on
            # aggregator endpoints that expose their whole catalog via /models).
            api_key = str(ep_cfg.get("api_key", "") or "").strip()
            if not api_key:
                key_env = str(ep_cfg.get("key_env", "") or "").strip()
                api_key = os.environ.get(key_env, "").strip() if key_env else ""
            discover = ep_cfg.get("discover_models", True)
            if isinstance(discover, str):
                discover = discover.lower() not in {"false", "no", "0"}
            # Only run live discovery when there is no curated model list from config
            if api_url and api_key and discover and not models_list:'''

if old in content:
    content = content.replace(old, new)
    with open(file_path, 'w') as f:
        f.write(content)
    print("APPLIED")
else:
    print("SKIP")
PYEOF
        [[ $? -eq 0 ]] && sw_ok=$((sw_ok + 1))

        # 1b. custom_providers
        _do_patch "hermes_cli/model_switch.py" \
            "Fix: model whitelist ignored — custom_providers（同上 — custom_providers 白名单）" \
            'curated list takes priority over live discovery' <<'PYEOF'
import sys
file_path = sys.argv[1]
with open(file_path, 'r') as f:
    content = f.read()

old = '''            should_probe = (
                bool(api_url)
                and (bool(api_key) or not grp["models"])
                and grp.get("discover_models", True)
            )
            if should_probe:'''

new = '''            # Only run live discovery when the user has NOT supplied
            # a curated model list AND has credentials. A non-empty
            # curated list takes priority over live discovery.
            should_probe = (
                bool(api_url)
                and bool(api_key)
                and not grp["models"]
                and grp.get("discover_models", True)
            )
            if should_probe:'''

if old in content:
    content = content.replace(old, new)
    with open(file_path, 'w') as f:
        f.write(content)
    print("APPLIED")
else:
    print("SKIP")
PYEOF
        [[ $? -eq 0 ]] && sw_ok=$((sw_ok + 1))

        [[ $sw_ok -gt 0 ]] && ok "model_switch.py — both sections applied（两处均已修复）"
    fi

    # ── 2. cron/jobs.py ───────────────────────────────────────────────────
    _do_patch "cron/jobs.py" \
        "Fix: Chinese text garbled in cron jobs（修复「定时任务中文变乱码」的问题）" \
        'ensure_ascii=False' <<'PYEOF'
import sys
file_path = sys.argv[1]
with open(file_path, 'r') as f:
    content = f.read()

old = '''            json.dump({"jobs": jobs, "updated_at": _hermes_now().isoformat()}, f, indent=2)
            f.flush()'''

new = '''            json.dump({"jobs": jobs, "updated_at": _hermes_now().isoformat()}, f, indent=2, ensure_ascii=False)
            f.flush()'''

if old in content:
    content = content.replace(old, new)
    with open(file_path, 'w') as f:
        f.write(content)
    print("APPLIED")
else:
    print("SKIP")
PYEOF

    # ── 3. P50: 评论→正文合并 ────────────────────────────────────────────────
    _do_patch "gateway/stream_consumer.py" \
        "Fix: commentary fragmentation（修复「回复碎成很多条消息」的问题）" \
        'Accumulate commentary' <<'PYEOF'
import sys
file_path = sys.argv[1]
with open(file_path, "r") as f:
    content = f.read()

old = """                if commentary_text is not None:
                    self._reset_segment_state()
                    await self._send_commentary(commentary_text)
                    self._last_edit_time = time.monotonic()
                    self._reset_segment_state()"""

new = """                if commentary_text is not None:
                    # Accumulate commentary into the stream buffer instead of
                    # sending as a separate message.  Prevents response fragmentation
                    # across multiple messages on platforms like Mattermost.
                    if self._accumulated:
                        self._accumulated += "\\n\\n"
                    self._accumulated += commentary_text"""

if old in content:
    content = content.replace(old, new)
    with open(file_path, "w") as f:
        f.write(content)
    print("APPLIED")
else:
    print("SKIP")
PYEOF

    # ── 4. P53: truncate_message 幽灵代码围栏 ─────────────────────────────────
    _do_patch "gateway/platforms/base.py" \
        "Fix: ghost fence in long code blocks（修复「长代码块出现幽灵空围栏」的问题）" \
        'reopening the fence would create' <<'PYEOF'
import sys
file_path = sys.argv[1]
with open(file_path, "r") as f:
    content = f.read()

old = """        while remaining:
            # If we're continuing a code block from the previous chunk,
            # prepend a new opening fence with the same language tag.
            prefix = f\"```{carry_lang}\\n\" if carry_lang is not None else \"\""""

new = """        while remaining:
            # When the previous chunk's closing fence is immediately followed
            # by the original content's own closing `` ``` `` (because the
            # split cut right before it), reopening the fence would create a
            # ghost empty block::
            #
            #     ```python
            #     ```
            #
            # Detect this and consume the original closing fence without
            # reopening, so the code block ends cleanly at the chunk boundary.
            if carry_lang is not None:
                stripped_line = remaining.lstrip().split("\\n", 1)[0].rstrip()
                if stripped_line.startswith("```") and not stripped_line[3:].strip():
                    # The first meaningful line is a bare `` ``` `` — the
                    # original closing fence.  Consume it and clear the
                    # carry so we don't reopen.
                    idx = remaining.index("```")
                    remaining = remaining[idx + 3:]
                    if remaining.startswith("\\n"):
                        remaining = remaining[1:]
                    remaining = remaining.lstrip()
                    carry_lang = None
                    continue

            # If we're continuing a code block from the previous chunk,
            # prepend a new opening fence with the same language tag.
            prefix = f\"```{carry_lang}\\n\" if carry_lang is not None else \"\""""

if old in content:
    content = content.replace(old, new)
    with open(file_path, "w") as f:
        f.write(content)
    print("APPLIED")
else:
    print("SKIP")
PYEOF

    # ── 5. P55: fallback send 保留 Thread 路由 ────────────────────────────
    _do_patch "gateway/stream_consumer.py" \
        "Fix: fallback send loses thread routing（修复「fallback 发送时 Thread 路由丢失」的问题）" \
        'ML:content=chunk,\n.*reply_to=self._initial_reply_to_id' <<'PYEOF'
import sys
file_path = sys.argv[1]
with open(file_path, 'r') as f:
    content = f.read()

# The fallback send path in _send_fallback_final sends chunks without
# reply_to, so messages can land in the main channel instead of the Thread.
old = '''                result = await self.adapter.send(
                    chat_id=self.chat_id,
                    content=chunk,
                    metadata=self._metadata_for_send(final=True),
                )
                if result.success:
                    break
                if attempt == 0 and self._is_flood_error(result):'''

new = '''                result = await self.adapter.send(
                    chat_id=self.chat_id,
                    content=chunk,
                    reply_to=self._initial_reply_to_id,
                    metadata=self._metadata_for_send(final=True),
                )
                if result.success:
                    break
                if attempt == 0 and self._is_flood_error(result):'''

if old in content:
    content = content.replace(old, new)
    with open(file_path, 'w') as f:
        f.write(content)
    print("APPLIED")
else:
    print("SKIP")
PYEOF

    # ── 6. P59: MiniMax max_completion_tokens ────────────────────────────
    _do_patch "utils.py" \
        "Fix: MiniMax max_completion_tokens（修复「MiniMax 模型参数错误」的问题）" \
        'm.startswith.*minimax' <<'PYEOF'
import sys
file_path = sys.argv[1]
with open(file_path, 'r') as f:
    content = f.read()

old = '''    return (
        m.startswith("gpt-4o")
        or m.startswith("gpt-4.1")
        or m.startswith("gpt-5")
        or m.startswith("o1")
        or m.startswith("o3")
        or m.startswith("o4")
    )'''

new = '''    return (
        m.startswith("gpt-4o")
        or m.startswith("gpt-4.1")
        or m.startswith("gpt-5")
        or m.startswith("minimax")
        or m.startswith("o1")
        or m.startswith("o3")
        or m.startswith("o4")
    )'''

if old in content:
    content = content.replace(old, new)
    with open(file_path, 'w') as f:
        f.write(content)
    print("APPLIED")
else:
    print("SKIP")
PYEOF

    # ── 7. P60a: Session source clobbered by cross-thread interrupt ───────
    _do_patch "gateway/run.py" \
        "Fix: session source clobbered by cross-thread interrupt（修复「中断时 session source 被跨线程覆盖」的问题）" \
        'cross-thread routing' <<'PYEOF'
import sys
file_path = sys.argv[1]
with open(file_path, 'r') as f:
    content = f.read()

old = '''        session_entry = self.session_store.get_or_create_session(source)
        session_key = session_entry.session_key
        self._cache_session_source(session_key, source)
        if self._is_telegram_topic_lane(source):'''

new = '''        session_entry = self.session_store.get_or_create_session(source)
        session_key = session_entry.session_key
        # Preserve original session source on resume — don't overwrite with
        # interrupting event's metadata.  This prevents cross-thread routing
        # when an inbound message from a different thread interrupts a running
        # agent and causes the session to restart with wrong thread_id/message_id.
        if not self._get_cached_session_source(session_key):
            self._cache_session_source(session_key, source)
        if self._is_telegram_topic_lane(source):'''

if old in content:
    content = content.replace(old, new)
    with open(file_path, 'w') as f:
        f.write(content)
    print("APPLIED")
else:
    print("SKIP")
PYEOF

    # ── 8. P60b: Thread metadata lost after cross-thread interrupt ────────
    _do_patch "gateway/run.py" \
        "Fix: thread metadata lost after cross-thread interrupt（修复「中断后 thread metadata 丢失」的问题）" \
        'cross-thread interrupt' <<'PYEOF'
import sys
file_path = sys.argv[1]
with open(file_path, 'r') as f:
    content = f.read()

old = '''        _thread_metadata: Optional[Dict[str, Any]] = self._thread_metadata_for_source(source, event_message_id)

        if _streaming_enabled:'''

new = '''        _thread_metadata: Optional[Dict[str, Any]] = self._thread_metadata_for_source(source, event_message_id)

        # On session resume after cross-thread interrupt, the current source
        # may carry the interrupting message's metadata (thread_id=None on
        # channel-level posts).  Fall back to the cached original session
        # source so streamed responses route to the correct thread.
        if _thread_metadata is None:
            _cached_meta_source = self._get_cached_session_source(session_key)
            if _cached_meta_source is not None:
                _thread_metadata = self._thread_metadata_for_source(
                    _cached_meta_source,
                    event_message_id,
                )

        if _streaming_enabled:'''

if old in content:
    content = content.replace(old, new)
    with open(file_path, 'w') as f:
        f.write(content)
    print("APPLIED")
else:
    print("SKIP")
PYEOF

}

# ═══════════════════════════════════════════════════════════════════════════
# show_status — 检查所有 patch 状态（从注册表驱动，无一遗漏）
# ═══════════════════════════════════════════════════════════════════════════

show_status() {
    echo ""
    echo "═══════════════════════════════════════════════════"
    echo "  🔍 Checking Hermes core patches..."
    echo "     （正在检查 Hermes 核心补丁）"
    echo "═══════════════════════════════════════════════════"
    echo ""

    local total=0 applied=0

    for entry in "${_patch_registry[@]}"; do
        local file_rel="${entry%%|*}" rest="${entry#*|}"
        local label="${rest%%|*}"  check="${rest#*|}"
        local file="${AGENT_DIR}/${file_rel}"

        total=$((total + 1))
        if [[ -f "$file" ]]; then
            local matched=false
            if [[ "$check" == ML:* ]]; then
                local ml_pattern="${check#ML:}"
                if python3 -c "
import sys, re
with open('$file') as f:
    content = f.read()
sys.exit(0 if re.search('$ml_pattern', content) else 1)
" 2>/dev/null; then
                    matched=true
                fi
            elif grep -q "$check" "$file" 2>/dev/null; then
                matched=true
            fi
            if $matched; then
                ok "$label"
                applied=$((applied + 1))
            else
                warn "$label"
            fi
        else
            warn "$label — file not found（文件不存在）"
        fi
    done

    echo ""
    echo "───────────────────────────────────────────────────"
    echo "  Shell patches: ${applied}/${total} required"
    echo "  （Shell 补丁：${applied}/${total} 必需）"
    echo "───────────────────────────────────────────────────"
    echo ""

    if [[ $applied -eq $total ]]; then
        ok "All required patches applied ✨（所有必需补丁已生效）"
    elif [[ $applied -eq 0 ]]; then
        warn "No patches applied yet, run: $0 apply（还没有安装任何补丁，建议运行：$0 apply）"
    else
        warn "Some required patches still missing (${applied}/${total}), run: $0 apply（还有必需补丁没装完，建议运行：$0 apply）"
    fi
}

# ═══════════════════════════════════════════════════════════════════════════
# 主命令分发
# ═══════════════════════════════════════════════════════════════════════════

CMD="${1:-check}"

case "$CMD" in
    apply)
        echo ""
        echo "═══════════════════════════════════════════════════"
        echo "  🔧 Applying Hermes core patches..."
        echo "     （正在安装 Hermes 核心补丁）"
        echo "═══════════════════════════════════════════════════"
        echo ""
        apply_all
        echo ""
        ok "Patches applied! Restart Gateway to take effect.（补丁完成！重启 Gateway 生效。）"
        echo ""
        show_status
        ;;
    check|status)
        show_status
        ;;
    *)
        echo "Usage: $0 {apply|check|status}（用法）"
        echo ""
        echo "  check   — Check if all patches are applied (default)（检查所有补丁是否生效，默认）"
        echo "  apply   — Apply all patches（安装所有补丁）"
        echo "  status  — Same as check（同 check）"
        ;;
esac
