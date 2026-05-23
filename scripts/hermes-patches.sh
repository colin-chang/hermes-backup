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
#   8.  gateway/run.py                    — ✅ DM 审批 + 工具进度 Thread 路由（已迁移到 mattermost-enhancer 插件）
#   9.  utils.py                          — YAML 中文写入修复
#  10. MEDIA 正则收紧                    — 防止误匹配非文件路径
#     a. gateway/run.py                  — 工具结果扫描：要求路径格式
#     b. gateway/platforms/base.py       — extract_media() 去掉 \\S+ 兜底
#     c. gateway/platforms/mattermost.py — ❌ MEDIA 静默跳过（已迁移到 mattermost-enhancer 插件）
#
#  ❌ 6-8, 10c. Mattermost 补丁（已迁移到 mattermost-enhancer 插件）
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
    "hermes_cli/model_switch.py|同上：custom_providers 的 models 白名单也一样被无视了|if not grp\\[\"models\"\\]"
    "gateway/config.py|Gateway 重启提醒关不掉：明明设了 false 重启时还是收到那条消息|\"gateway_restart_notification\" in platform_cfg"
    "gateway/config.py|同上：另一个读取路径也没读到你的配置|extra.*gateway_restart_notification"
    "cron/jobs.py|定时任务中文变乱码：描述里的汉字全变成 \\uXXXX 转义符|ensure_ascii=False"
    "utils.py|config.yaml 中文变乱码：配置文件里的中文注释被保存成 \\uXXXX|allow_unicode=True"
    "gateway/run.py|聊天里莫名出现 (file not found: ...) 垃圾消息|_TOOL_MEDIA_RE"
    "gateway/platforms/base.py|同上：另一个文件提取路径也抓到了假文件路径|\\$))"
    "gateway/platforms/mattermost.py|Thread 里长时间任务的进度消息跑到频道去了|_raw_root = post.get"
    "gateway/run.py|Clarify 问题等待回复时用户回复被当成新会话（Session 分裂，Agent 答非所问）|_canonical_entry = self.session_store.get_or_create_session"
    "gateway/run.py|Clarify concurrency guard: 防止 clarify 阻塞期间新消息创建重复 Session|Gateway intercepted clarify at session guard"
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

old = '''            # Live model discovery from custom provider endpoints (matches
            # Section 3 behavior for user ``providers:`` entries).
            if api_url and api_key:'''

new = '''            # Live model discovery — only when the user has NOT supplied
            # a curated model list in config.yaml (models: field).
            # A non-empty curated list takes priority over live discovery.
            if not grp["models"] and api_url and api_key:'''

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

    # ── 11. mattermost.py Thread root_id fallback ────────────────────────────
    _do_patch "gateway/platforms/mattermost.py" \
        "Thread 里长时间任务的进度消息跑到频道去了" \
        '_raw_root = post.get' <<'PYEOF'
import sys
file_path = sys.argv[1]
with open(file_path, 'r') as f:
    content = f.read()

old = '''        # Thread support: if the post is in a thread, use root_id.
        thread_id = post.get("root_id") or None'''

new = '''        # Thread support: if the post is in a thread, use root_id.
        _raw_root = post.get("root_id")
        if _raw_root:
            thread_id = _raw_root
        elif self._reply_mode == "thread":
            # root_id="" can mean either a genuine thread-root post OR a
            # reply whose root_id was lost (Mattermost WebSocket anomaly).
            # Ask the REST API before blindly trusting the WebSocket event.
            try:
                post_data = await self._api_get(f"posts/{post_id}")
                api_root = post_data.get("root_id") if post_data else None
                if isinstance(api_root, str) and api_root:
                    thread_id = api_root
                else:
                    thread_id = post_id
            except Exception:
                thread_id = post_id
        else:
            thread_id = None'''

if old in content:
    content = content.replace(old, new)
    with open(file_path, 'w') as f:
        f.write(content)
    print("APPLIED")
else:
    print("SKIP")
PYEOF

    # ── P46: Clarify Session 分裂 ───────────────────────────────────────────
    _do_patch "gateway/run.py" \
        "Clarify 问题等待回复时用户回复被当成新会话（Session 分裂，Agent 答非所问）" \
'_canonical_entry = self.session_store.get_or_create_session' <<'PYEOF'
import sys
file_path = sys.argv[1]
with open(file_path, 'r') as f:
    content = f.read()

old = '''            _pending_clarify = _clarify_mod.get_pending_for_session(_quick_key)
        except Exception:
            _pending_clarify = None'''

new = '''            _pending_clarify = _clarify_mod.get_pending_for_session(_quick_key)
            # P46 fix: when _quick_key doesn't match (e.g. due to
            # thread_sessions_per_user config mismatch), fall back to the
            # canonical session key from get_or_create_session.  Without
            # this, the clarify is not found → message falls through
            # → a new Session is created → two Sessions run in parallel
            # in the same Thread (Session split).
            # Guard: only in Thread contexts where session key mismatch
            # can actually occur.  Non-Thread paths (DM, channel root)
            # always have _quick_key == canonical key, and calling
            # get_or_create_session here breaks Telegram topic mode
            # lobby (which asserts it's never called).
            if _pending_clarify is None and source.thread_id:
                try:
                    _canonical_entry = self.session_store.get_or_create_session(source)
                    _canonical_key = _canonical_entry.session_key
                    if _canonical_key != _quick_key:
                        _pending_clarify = _clarify_mod.get_pending_for_session(_canonical_key)
                except Exception:
                    pass
        except Exception:
            _pending_clarify = None'''

if old in content:
    content = content.replace(old, new)
    with open(file_path, 'w') as f:
        f.write(content)
    print("APPLIED")
else:
    print("SKIP")
PYEOF


    # ── P46b: Clarify concurrency guard  ─────────────────────────────────
    _do_patch "gateway/run.py" \
        "Clarify concurrency guard: _handle_message_with_agent intercept" \
        'Gateway intercepted clarify at session guard' <<'PYEOF'
import sys
file_path = sys.argv[1]
with open(file_path, "r") as f:
    content = f.read()

old = "        session_key = session_entry.session_key\n        self._cache_session_source(session_key, source)"

new = "        session_key = session_entry.session_key\n"
new += "        # P46 concurrency guard: belt-and-suspenders clarify check using\n"
new += "        # the canonical session key.  The earlier check in _handle_message\n"
new += "        # uses _quick_key which may differ from session_key when\n"
new += "        # thread_sessions_per_user configs diverge.  When keys differ and\n"
new += "        # no agent is found in _running_agents under _quick_key, a new\n"
new += "        # Session is spawned before the clarify-blocked agent can respond.\n"
new += "        if session_key != _quick_key:\n"
new += "            try:\n"
new += '                from tools import clarify_gateway as _clarify_mod2\n'
new += "                _pc = _clarify_mod2.get_pending_for_session(session_key)\n"
new += "                if _pc is not None:\n"
new += '                    _raw = (event.text or "").strip()\n'
new += '                    if _raw and not _raw.startswith("/"):\n'
new += "                        _clarify_mod2.resolve_gateway_clarify(_pc.clarify_id, _raw)\n"
new += "                        logger.info(\n"
new += '                            "Gateway intercepted clarify at session guard "\n'
new += '                            "(session=%s, clarify_id=%s)",\n'
new += "                            session_key, _pc.clarify_id,\n"
new += "                        )\n"
new += "                        return None  # consumed by clarify -- no new turn\n"
new += "            except Exception:\n"
new += "                pass\n"
new += "        self._cache_session_source(session_key, source)"

if old in content:
    content = content.replace(old, new, 1)
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
