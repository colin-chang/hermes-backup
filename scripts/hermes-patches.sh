#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════
# Hermes Patches — 手动修复脚本
# ═══════════════════════════════════════════════════════════════════════════
#
# 背景：
#   当 hermes-agent 上游版本更新后，本地修改会被覆盖，
#   此脚本用于一键还原以下 patch。
#
#   1.  hermes_cli/providers.py           — 自定义 provider (custom:*) 聚合器识别
#   2.  hermes_cli/doctor.py              — 自定义 provider vendor-prefix 假阳性修复
#   3.  hermes_cli/model_switch.py        — config 白名单优先于线上拉取
#   4.  gateway/config.py                 — gateway_restart_notification 桥接修复
#   5.  cron/jobs.py                      — Cron job 中文存储修复
#   6.  gateway/platforms/mattermost.py   — ❌ _resolve_root_id（已迁移到 mattermost-enhancer 插件）
#   7.  gateway/platforms/mattermost.py   — ❌ DM 审批基础设施（已迁移到 mattermost-enhancer 插件）
#   8.  gateway/run.py                    — ❌ DM 审批 + 工具进度 Thread 路由（已迁移到 mattermost-enhancer 插件）
#   9.  gateway/run.py                    — ❌ Clarify Session 分裂修复（已迁移到 mattermost-enhancer 插件）
#  10.  gateway/run.py                    — ❌ Clarify 并发守护（已迁移到 mattermost-enhancer 插件）
#  11.  gateway/platforms/mattermost.py   — ❌ Thread root_id fallback（已迁移到 mattermost-enhancer 插件）
#  12.  utils.py                          — YAML 中文写入修复
#  13.  MEDIA 正则收紧                    — 防止误匹配非文件路径
#     a. gateway/run.py                  — 工具结果扫描：要求路径格式
#     b. gateway/platforms/base.py       — extract_media() 去掉 \\\\S+ 兜底
#     c. gateway/platforms/mattermost.py — ❌ MEDIA 静默跳过（已迁移到 mattermost-enhancer 插件）
#  P50. gateway/stream_consumer.py        — 评论→正文合并，防止消息碎片化
#  P53. gateway/platforms/base.py         — truncate_message 幽灵代码围栏修复
#  P55. gateway/stream_consumer.py        — stream fallback 发送丢失 reply_to，Thread 回复跑到频道根级别
#  P57. gateway/run.py                    — 工具进度消息不在 Thread 中：Mattermost 不应要求 source.thread_id
#  ❌ P54. WebSocket 心跳 30s→15s — 已迁移到 mattermost-enhancer 插件（覆写 _ws_connect_and_listen）
#  ❌ P56. _api_put 缺少 timeout — 已迁移到 mattermost-enhancer 插件（覆写 edit_message）
#
#  ❌ 6-10, 11, 13c. Mattermost 补丁（已迁移到 mattermost-enhancer 插件）
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
# ═══════════════════════════════════════════════════════════════════════════

_patch_registry=(
    "hermes_cli/providers.py|模型列表太乱：自定义 provider 显示了全部 100+ 模型而不是只显示你精选的几个|startswith.*\"custom:\""
    "hermes_cli/doctor.py|hermes doctor 误报：用了自定义 provider 就弹「模型不匹配」假警告|startswith.*\"custom:\""
    "hermes_cli/model_switch.py|模型白名单没生效：config 里设了 models 限制但切模型时全跑出来了|and not models_list"
    "hermes_cli/model_switch.py|同上：custom_providers 的 models 白名单也一样被无视了|not grp\[\"models\"\]"
    "gateway/config.py|Gateway 重启提醒关不掉：明明设了 false 重启时还是收到那条消息|\"gateway_restart_notification\" in platform_cfg"
    "gateway/config.py|同上：另一个读取路径也没读到你的配置|extra.*gateway_restart_notification"
    "cron/jobs.py|定时任务中文变乱码：描述里的汉字全变成 \\uXXXX 转义符|ensure_ascii=False"
    "utils.py|config.yaml 中文变乱码：配置文件里的中文注释被保存成 \\uXXXX|allow_unicode=True"
    "gateway/run.py|聊天里莫名出现 (file not found: ...) 垃圾消息|_TOOL_MEDIA_RE"
    "gateway/platforms/base.py|同上：另一个文件提取路径也抓到了假文件路径|\\$))"
    "gateway/stream_consumer.py|回复碎成很多条消息：Agent 评论文字和正文被拆成多条独立消息|Accumulate commentary"
    "gateway/platforms/base.py|长代码块跨chunk分片时出现幽灵代码围栏空块|reopening the fence would create"
    "gateway/stream_consumer.py|Thread回复丢失：stream fallback发消息时没传reply_to导致不在Thread里|reply_to=self._initial_reply_to_id"
    "gateway/run.py|工具进度消息不在Thread中：Mattermost不应要求source.thread_id|or source.platform == Platform.MATTERMOST"
    "gateway/run.py|Gateway重启后session串台：多条Thread同时auto-resume导致消息跑到错误的Thread|Deduplicate.*keep only the most recent"
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
        error "${1} 不存在，跳过"
        return 1
    fi
    if grep -q "$check" "$file" 2>/dev/null; then
        ok "$label — 已装好 ✅，跳过"
        return 0
    fi

    python3 - "$file"
    local rc=$?
    if [[ $rc -eq 0 ]]; then
        ok "$label — 安装成功 ✅"
    else
        error "$label — 安装失败 ❌"
    fi
    return $rc
}

# ═══════════════════════════════════════════════════════════════════════════
# apply_all — 应用所有 patch
# ═══════════════════════════════════════════════════════════════════════════

apply_all() {
    info "正在安装 hermes-agent 修复补丁..."

    # ── 1. providers.py ───────────────────────────────────────────────────
    _do_patch "hermes_cli/providers.py" \
        "模型列表太乱：自定义 provider 显示了全部 100+ 模型而不是只显示你精选的几个" \
        'startswith.*"custom:"' <<'PYEOF'
import sys
file_path = sys.argv[1]
with open(file_path, 'r') as f:
    content = f.read()

old = '''def is_aggregator(provider: str) -> bool:
    """Return True when the provider is a multi-model aggregator."""
    pdef = get_provider(provider)'''

new = '''def is_aggregator(provider: str) -> bool:
    """Return True when the provider is a multi-model aggregator."""
    # Custom-named providers (e.g. "custom:zenmux") are always aggregators —
    # they are user-defined endpoints that typically proxy multiple vendors.
    if provider and provider.startswith("custom:"):
        return True
    pdef = get_provider(provider)'''

if old in content:
    content = content.replace(old, new)
    with open(file_path, 'w') as f:
        f.write(content)
    print("APPLIED")
else:
    print("SKIP")
PYEOF

    # ── 2. doctor.py ──────────────────────────────────────────────────────
    _do_patch "hermes_cli/doctor.py" \
        "hermes doctor 误报：用了自定义 provider 就弹「模型不匹配」假警告" \
        'startswith.*"custom:"' <<'PYEOF'
import sys
file_path = sys.argv[1]
with open(file_path, 'r') as f:
    content = f.read()

old = '''                and provider_for_policy not in providers_accepting_vendor_slugs
            ):'''

new = '''                # Custom-named providers (e.g. "custom:zenmux") are aggregators
                # that accept vendor-prefixed model slugs, just like "custom".
                and provider_for_policy not in providers_accepting_vendor_slugs
                and not provider_for_policy.startswith("custom:")
            ):'''

if old in content:
    content = content.replace(old, new)
    with open(file_path, 'w') as f:
        f.write(content)
    print("APPLIED")
else:
    print("SKIP")
PYEOF

    # ── 3. model_switch.py (两处) ─────────────────────────────────────────
    local sw_file="${AGENT_DIR}/hermes_cli/model_switch.py"
    if [[ ! -f "$sw_file" ]]; then
        error "hermes_cli/model_switch.py 不存在，跳过"
    else
        local sw_ok=0

        # 3a. Section 3: user providers
        _do_patch "hermes_cli/model_switch.py" \
            "模型白名单没生效：config 里设了 models 限制但切模型时全跑出来了" \
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

        # 3b. Section 4: custom_providers
        _do_patch "hermes_cli/model_switch.py" \
            "同上：custom_providers 的 models 白名单也一样被无视了" \
            'if not grp\["models"\]' <<'PYEOF'
import sys
file_path = sys.argv[1]
with open(file_path, 'r') as f:
    content = f.read()

old = '''            should_probe = bool(api_url) and (bool(api_key) or not grp["models"])
            if should_probe:'''

new = '''            # Only run live discovery when the user has NOT supplied
            # a curated model list AND has credentials. A non-empty
            # curated list takes priority over live discovery.
            should_probe = bool(api_url) and bool(api_key) and not grp["models"]
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

        [[ $sw_ok -gt 0 ]] && ok "model_switch.py — 已装好 ✅"
    fi

    # ── 4. gateway/config.py (两处) ───────────────────────────────────────
    local cf_file="${AGENT_DIR}/gateway/config.py"
    if [[ ! -f "$cf_file" ]]; then
        error "gateway/config.py 不存在，跳过"
    else
        local cf_ok=0

        # 4a. bridging 循环中 bridge gateway_restart_notification
        _do_patch "gateway/config.py" \
            "Gateway 重启提醒关不掉：明明设了 false 重启时还是收到那条消息" \
            '"gateway_restart_notification" in platform_cfg' <<'PYEOF'
import sys
file_path = sys.argv[1]
with open(file_path, 'r') as f:
    content = f.read()

old = '''                if "channel_prompts" in platform_cfg:
                    channel_prompts = platform_cfg["channel_prompts"]
                    if isinstance(channel_prompts, dict):
                        bridged["channel_prompts"] = {str(k): v for k, v in channel_prompts.items()}
                    else:
                        bridged["channel_prompts"] = channel_prompts
                enabled_was_explicit = "enabled" in platform_cfg'''

new = '''                if "channel_prompts" in platform_cfg:
                    channel_prompts = platform_cfg["channel_prompts"]
                    if isinstance(channel_prompts, dict):
                        bridged["channel_prompts"] = {str(k): v for k, v in channel_prompts.items()}
                    else:
                        bridged["channel_prompts"] = channel_prompts
                if "gateway_restart_notification" in platform_cfg:
                    bridged["gateway_restart_notification"] = platform_cfg["gateway_restart_notification"]
                enabled_was_explicit = "enabled" in platform_cfg'''

if old in content:
    content = content.replace(old, new)
    with open(file_path, 'w') as f:
        f.write(content)
    print("APPLIED")
else:
    print("SKIP")
PYEOF
        [[ $? -eq 0 ]] && cf_ok=$((cf_ok + 1))

        # 4b. from_dict() 从 extra fallback 读取
        _do_patch "gateway/config.py" \
            "同上：另一个读取路径也没读到你的配置" \
            '_grn = data.get.*gateway_restart_notification' <<'PYEOF'
import sys
file_path = sys.argv[1]
with open(file_path, 'r') as f:
    content = f.read()

old = '''        return cls(
            enabled=_coerce_bool(data.get("enabled"), False),
            token=data.get("token"),
            api_key=data.get("api_key"),
            home_channel=home_channel,
            reply_to_mode=data.get("reply_to_mode", "first"),
            gateway_restart_notification=_coerce_bool(
                data.get("gateway_restart_notification"), True
            ),
            extra=data.get("extra", {}),
        )'''

new = '''        # gateway_restart_notification may be bridged into extra via the
        # shared-key loop in load_gateway_config(); check both top-level
        # and extra so YAML ``discord: gateway_restart_notification: false``
        # works without needing a separate platforms: block.
        _grn = data.get("gateway_restart_notification")
        if _grn is None:
            _grn = data.get("extra", {}).get("gateway_restart_notification")

        return cls(
            enabled=_coerce_bool(data.get("enabled"), False),
            token=data.get("token"),
            api_key=data.get("api_key"),
            home_channel=home_channel,
            reply_to_mode=data.get("reply_to_mode", "first"),
            gateway_restart_notification=_coerce_bool(_grn, True),
            extra=data.get("extra", {}),
        )'''

if old in content:
    content = content.replace(old, new)
    with open(file_path, 'w') as f:
        f.write(content)
    print("APPLIED")
else:
    print("SKIP")
PYEOF
        [[ $? -eq 0 ]] && cf_ok=$((cf_ok + 1))

        [[ $cf_ok -gt 0 ]] && ok "gateway/config.py — 已装好 ✅"
    fi

    # ── 5. cron/jobs.py ───────────────────────────────────────────────────
    _do_patch "cron/jobs.py" \
        "定时任务中文变乱码：描述里的汉字全变成 \\uXXXX 转义符" \
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


    # ── 9. utils.py ───────────────────────────────────────────────────────
    _do_patch "utils.py" \
        "config.yaml 中文变乱码：配置文件里的中文注释被保存成 \\uXXXX" \
        'allow_unicode=True' <<'PYEOF'
import sys
file_path = sys.argv[1]
with open(file_path, 'r') as f:
    content = f.read()

old = '''            yaml.dump(data, f, default_flow_style=default_flow_style, sort_keys=sort_keys)
            if extra_content:'''

new = '''            yaml.dump(data, f, default_flow_style=default_flow_style, sort_keys=sort_keys,
                      allow_unicode=True)
            if extra_content:'''

if old in content:
    content = content.replace(old, new)
    with open(file_path, 'w') as f:
        f.write(content)
    print("APPLIED")
else:
    print("SKIP")
PYEOF

    # ── 10. MEDIA 正则收紧 ──────────────────────────────────────────────────
    local media_ok=0

    # 10a. run.py — 工具结果扫描
    _do_patch "gateway/run.py" \
        "聊天里莫名出现 (file not found: ...) 垃圾消息" \
        '_TOOL_MEDIA_RE' <<'PYEOF'
import sys
file_path = sys.argv[1]
with open(file_path, 'r') as f:
    content = f.read()

old = '''                            for match in re.finditer(r'MEDIA:(\\S+)', content):'''

new = '''                            # 收紧正则：要求路径以 / 或 ~/ 开头 + 已知扩展名
                            _TOOL_MEDIA_RE = re.compile(
                                r'MEDIA:((?:~/|/)\\S+\\.(?:png|jpe?g|gif|webp|'
                                r'mp4|mov|avi|mkv|webm|ogg|opus|mp3|wav|m4a|'
                                r'flac|epub|pdf|zip|rar|7z|docx?|xlsx?|pptx?|'
                                r'txt|csv|apk|ipa))',
                                re.IGNORECASE
                            )
                            for match in _TOOL_MEDIA_RE.finditer(content):'''

if old in content:
    content = content.replace(old, new)
    with open(file_path, 'w') as f:
        f.write(content)
    print("APPLIED")
else:
    print("SKIP")
PYEOF
    [[ $? -eq 0 ]] && media_ok=$((media_ok + 1))

    # 10b. base.py — 去掉 |\S+ 兜底
    _do_patch "gateway/platforms/base.py" \
        "同上：另一个文件提取路径也抓到了假文件路径" \
        '|\\$))' <<'PYEOF'
import sys
file_path = sys.argv[1]
with open(file_path, 'r') as f:
    content = f.read()

# Remove |\S+ fallback from extract_media() regex that captures non-path tokens
old = "|$)|\\S+)[`\"']?'''"
new = "|$))[`\"']?'''"

if old in content:
    content = content.replace(old, new)
    with open(file_path, 'w') as f:
        f.write(content)
    print("APPLIED")
else:
    print("SKIP")
PYEOF

    [[ $media_ok -gt 0 ]] && ok "MEDIA 正则收紧 — 已装好 ✅"

    # ── P50: 评论→正文合并 ────────────────────────────────────────────────
    _do_patch "gateway/stream_consumer.py" \
        "回复碎成很多条消息：Agent 评论文字和正文被拆成多条独立消息" \
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

    # ── P53: truncate_message 幽灵代码围栏 ─────────────────────────────────
    _do_patch "gateway/platforms/base.py" \
        "长代码块跨chunk分片时出现幽灵代码围栏空块" \
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

    # ── P55: stream_consumer fallback 丢失 reply_to ──────────────────────
    _do_patch "gateway/stream_consumer.py" \
        "Thread回复丢失：stream fallback发消息时没传reply_to导致不在Thread里" \
        'reply_to=self._initial_reply_to_id' <<'PYEOF'
import sys
file_path = sys.argv[1]
with open(file_path, "r") as f:
    content = f.read()

old = """                result = await self.adapter.send(
                    chat_id=self.chat_id,
                    content=chunk,
                    metadata=self.metadata,
                )"""

new = """                result = await self.adapter.send(
                    chat_id=self.chat_id,
                    content=chunk,
                    reply_to=self._initial_reply_to_id,
                    metadata=self.metadata,
                )"""

if old in content:
    content = content.replace(old, new)
    with open(file_path, "w") as f:
        f.write(content)
    print("APPLIED")
else:
    print("SKIP")
PYEOF

    # ── P57: 工具进度消息进 Thread ───────────────────────────────────────
    _do_patch "gateway/run.py" \
        "工具进度消息不在Thread中：Mattermost不应要求source.thread_id" \
        'or source.platform == Platform.MATTERMOST' <<'PYEOF'
import sys
file_path = sys.argv[1]
with open(file_path, "r") as f:
    content = f.read()

old = """        _progress_reply_to = (
            event_message_id
            if source.platform in (Platform.FEISHU, Platform.MATTERMOST) and source.thread_id and event_message_id
            else None
        )"""

new = """        _progress_reply_to = (
            event_message_id
            if (
                (source.platform == Platform.FEISHU and source.thread_id)
                or source.platform == Platform.MATTERMOST
            ) and event_message_id
            else None
        )"""

if old in content:
    content = content.replace(old, new)
    with open(file_path, "w") as f:
        f.write(content)
    print("APPLIED")
else:
    print("SKIP")
PYEOF

    # ── P58: Session 串台修复 — 同 channel 多 thread auto-resume 去重 ──────
    _do_patch "gateway/run.py" \
        "Gateway重启后session串台：多条Thread同时auto-resume导致消息跑到错误的Thread" \
        'Deduplicate.*keep only the most recent' <<'PYEOF'
import sys
file_path = sys.argv[1]
with open(file_path, "r") as f:
    content = f.read()

old = """        except Exception as exc:
            logger.warning("Failed to enumerate resume-pending sessions: %s", exc)
            return 0

        now = datetime.now()"""

new = """        except Exception as exc:
            logger.warning("Failed to enumerate resume-pending sessions: %s", exc)
            return 0

        # Deduplicate: keep only the most recent session per (platform, chat_id).
        # When multiple threads in the same channel are auto-resumed
        # simultaneously (e.g. after a gateway crash), responses from one
        # thread can leak into another — the user sees a message about
        # an unrelated topic appearing in their current thread.
        _per_chat: dict = {}
        for entry in candidates:
            key = (entry.origin.platform, entry.origin.chat_id)
            existing = _per_chat.get(key)
            if (
                existing is None
                or (
                    entry.updated_at
                    and existing.updated_at
                    and entry.updated_at > existing.updated_at
                )
            ):
                _per_chat[key] = entry
        candidates = list(_per_chat.values())

        now = datetime.now()"""

if old in content:
    content = content.replace(old, new)
    with open(file_path, "w") as f:
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
    echo "  🔍 检查 Hermes 是否已打上所有修复补丁..."
    echo "═══════════════════════════════════════════════════"
    echo ""

    local total=0 applied=0

    for entry in "${_patch_registry[@]}"; do
        local file_rel="${entry%%|*}" rest="${entry#*|}"
        local label="${rest%%|*}"  check="${rest#*|}"
        local file="${AGENT_DIR}/${file_rel}"

        total=$((total + 1))
        if [[ -f "$file" ]]; then
            if grep -q "$check" "$file" 2>/dev/null; then
                echo -e "  ${GREEN}✓${NC} $label"
                applied=$((applied + 1))
            else
                echo -e "  ${RED}✗${NC} $label —— 还没装"
            fi
        else
            echo -e "  ${YELLOW}?${NC} $label —— 文件不存在"
        fi
    done

    echo ""
    echo "───────────────────────────────────────────────────"
    echo "  结果：${applied}/${total} 项已修复"
    echo "───────────────────────────────────────────────────"
    echo ""

    if [[ $applied -eq $total ]]; then
        ok "全部修好了，不需要再做什么 ✨"
    elif [[ $applied -eq 0 ]]; then
        warn "一项都没装，建议运行：$0 apply"
    else
        warn "还有没装完的，建议运行：$0 apply"
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
        echo "  🔧 安装 Hermes 修复补丁"
        echo "═══════════════════════════════════════════════════"
        echo ""
        apply_all
        echo ""
        ok "安装完成！重启 Hermes 或刷新 WebUI 即可生效 ✨"
        echo ""
        show_status
        ;;
    check|status)
        show_status
        ;;
    *)
        echo "用法: $0 {apply|check|status}"
        echo ""
        echo "  check   — 检查哪些修复已装好（默认）"
        echo "  apply   — 安装所有修复补丁"
        echo "  status  — 同 check"
        exit 1
        ;;
esac
