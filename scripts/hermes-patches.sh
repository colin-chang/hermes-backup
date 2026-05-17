#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════
# Hermes Patches — 手动修复脚本
# ═══════════════════════════════════════════════════════════════════════════
#
# 背景：
#   当 hermes-agent 上游版本更新后，本地修改会被覆盖，
#   此脚本用于一键还原以下 5 类 7 处 patch。
#
#   1. hermes_cli/providers.py   — is_aggregator() 识别 custom:<name>
#   2. hermes_cli/doctor.py      — 消除 vendor-prefix 假阳性警告
#   3. hermes_cli/model_switch.py — models: 白名单优先于线上拉取（2 处）
#   4. gateway/config.py          — gateway_restart_notification bridge 修复（2 处）
#   5. cron/jobs.py               — json.dump ensure_ascii=False，避免中文变 \uXXXX
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
    "hermes_cli/providers.py|providers.py (is_aggregator)|startswith.*\"custom:\""
    "hermes_cli/doctor.py|doctor.py (vendor-prefix)|startswith.*\"custom:\""
    "hermes_cli/model_switch.py|model_switch.py (Section 3)|and not models_list"
    "hermes_cli/model_switch.py|model_switch.py (Section 4)|if not grp\[\"models\"\]"
    "gateway/config.py|config.py (bridge loop)|\"gateway_restart_notification\" in platform_cfg"
    "gateway/config.py|config.py (from_dict fallback)|_grn = data.get.*gateway_restart_notification"
    "cron/jobs.py|jobs.py (ensure_ascii=False)|ensure_ascii=False"
)

# ═══════════════════════════════════════════════════════════════════════════
# 辅助函数
# ═══════════════════════════════════════════════════════════════════════════

# 执行一个 Python 替换 patch。
# 使用: _do_patch <file_rel> <label> <check_grep> <<'PYEOF' ... PYEOF
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
        ok "$label — 已应用，跳过"
        return 0
    fi

    python3 - "$file"
    local rc=$?
    if [[ $rc -eq 0 ]]; then
        ok "$label — 已应用"
    else
        error "$label — 应用失败"
    fi
    return $rc
}

# ═══════════════════════════════════════════════════════════════════════════
# apply_all — 应用所有 patch
# ═══════════════════════════════════════════════════════════════════════════

apply_all() {
    info "正在应用 hermes-agent patches..."

    # ── 1. providers.py ───────────────────────────────────────────────────
    _do_patch "hermes_cli/providers.py" \
        "providers.py (is_aggregator)" \
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
        "doctor.py (vendor-prefix)" \
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
            "model_switch.py (Section 3)" \
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
            "model_switch.py (Section 4)" \
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

        [[ $sw_ok -gt 0 ]] && ok "model_switch.py — 已应用"
    fi

    # ── 4. gateway/config.py (两处) ───────────────────────────────────────
    local cf_file="${AGENT_DIR}/gateway/config.py"
    if [[ ! -f "$cf_file" ]]; then
        error "gateway/config.py 不存在，跳过"
    else
        local cf_ok=0

        # 4a. bridging 循环中 bridge gateway_restart_notification
        _do_patch "gateway/config.py" \
            "config.py (bridge loop)" \
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
            "config.py (from_dict fallback)" \
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

        [[ $cf_ok -gt 0 ]] && ok "gateway/config.py — 已应用"
    fi

    # ── 5. cron/jobs.py ───────────────────────────────────────────────────
    _do_patch "cron/jobs.py" \
        "cron/jobs.py (ensure_ascii=False)" \
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
}

# ═══════════════════════════════════════════════════════════════════════════
# show_status — 检查所有 patch 状态（从注册表驱动，无一遗漏）
# ═══════════════════════════════════════════════════════════════════════════

show_status() {
    echo ""
    echo "═══════════════════════════════════════════════════"
    echo "  Hermes Patches 状态检查"
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
                echo -e "  ${GREEN}✓${NC} ${label}"
                applied=$((applied + 1))
            else
                echo -e "  ${RED}✗${NC} ${label} — 未应用"
            fi
        else
            echo -e "  ${YELLOW}?${NC} ${label} — 文件不存在"
        fi
    done

    echo ""
    echo "───────────────────────────────────────────────────"
    echo "  状态: ${applied}/${total} patches 已应用"
    echo "───────────────────────────────────────────────────"
    echo ""

    if [[ $applied -eq $total ]]; then
        ok "所有 patches 已应用，无需重新应用"
    elif [[ $applied -eq 0 ]]; then
        warn "所有 patches 未应用，建议执行: $0 apply"
    else
        warn "部分 patches 未应用，建议执行: $0 apply"
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
        echo "  应用 Hermes Patches"
        echo "═══════════════════════════════════════════════════"
        echo ""
        apply_all
        echo ""
        ok "应用完成！重启 Hermes / 刷新 WebUI 生效"
        echo ""
        show_status
        ;;
    check|status)
        show_status
        ;;
    *)
        echo "用法: $0 {apply|check|status}"
        echo ""
        echo "  check   — 检查 patches 状态（默认）"
        echo "  apply   — 应用所有 patches"
        echo "  status  — 同 check，显示状态"
        exit 1
        ;;
esac
