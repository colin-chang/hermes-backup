#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════
# Hermes Patches — 手动修复兼容 custom:<name> 聚合器的 patch 管理脚本
# ═══════════════════════════════════════════════════════════════════════════
#
# 背景：
#   当 hermes-agent 上游版本更新后，本地修改会被覆盖，
#   此脚本用于一键还原以下 4 个文件的修改：
#
# hermes-agent (5 处):
#   1. hermes_cli/providers.py    — is_aggregator() 识别 custom:<name>
#   2. hermes_cli/doctor.py        — 消除 vendor-prefix 假阳性警告
#   3. hermes_cli/model_switch.py  — models: 白名单优先于线上拉取（2 处）
#   4. gateway/config.py           — gateway_restart_notification bridge 缺失修复（2 处）
#
# 使用方法：
#   ./hermes-patches.sh check    # 检查当前状态（是否需要重新应用）
#   ./hermes-patches.sh apply    # 应用 patch
#   ./hermes-patches.sh status   # 显示各文件修改状态
#
# ═══════════════════════════════════════════════════════════════════════════

set -euo pipefail

AGENT_DIR="${HOME}/.hermes/hermes-agent"

# ── 颜色 ────────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

info()    { echo -e "${CYAN}[INFO]${NC}  $1"; }
ok()      { echo -e "${GREEN}[OK]${NC}    $1"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $1"; }
error()   { echo -e "${RED}[ERROR]${NC} $1"; }

# ── patch 内容（内嵌，避免依赖外部文件）────────────────────────────────────

apply_hermes_agent() {
    info "正在应用 hermes-agent patches..."

    # 1. hermes_cli/providers.py — is_aggregator()
    local providers_file="${AGENT_DIR}/hermes_cli/providers.py"
    if [[ -f "$providers_file" ]]; then
        if grep -q 'startswith.*"custom:"' "$providers_file" 2>/dev/null; then
            ok "hermes_cli/providers.py — 已应用，跳过"
        else
            python3 - "$providers_file" <<'PYEOF'
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
            if [[ $? -eq 0 ]]; then
                ok "hermes_cli/providers.py — 已应用"
            else
                error "hermes_cli/providers.py — 应用失败"
            fi
        fi
    else
        error "hermes_cli/providers.py 不存在，跳过"
    fi

    # 2. hermes_cli/doctor.py — vendor-prefix check
    local doctor_file="${AGENT_DIR}/hermes_cli/doctor.py"
    if [[ -f "$doctor_file" ]]; then
        if grep -q 'startswith.*"custom:"' "$doctor_file" 2>/dev/null; then
            ok "hermes_cli/doctor.py — 已应用，跳过"
        else
            python3 - "$doctor_file" <<'PYEOF'
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
            if [[ $? -eq 0 ]]; then
                ok "hermes_cli/doctor.py — 已应用"
            else
                error "hermes_cli/doctor.py — 应用失败"
            fi
        fi
    else
        error "hermes_cli/doctor.py 不存在，跳过"
    fi

    # 3. hermes_cli/model_switch.py — 两处修改
    local switch_file="${AGENT_DIR}/hermes_cli/model_switch.py"
    if [[ -f "$switch_file" ]]; then
        local applied=0

        # 3a. Section 3: user providers (models_list 非空时跳过线上拉取)
        if ! grep -q 'and not models_list' "$switch_file" 2>/dev/null; then
            python3 - "$switch_file" <<'PYEOF'
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
    print("APPLIED_A")
else:
    print("SKIP_A")
PYEOF
            if [[ $? -eq 0 ]]; then
                applied=$((applied + 1))
            fi
        else
            ok "hermes_cli/model_switch.py (Section 3) — 已应用，跳过"
        fi

        # 3b. Section 4: custom_providers (grp["models"] 非空时跳过线上拉取)
        if ! grep -q 'if not grp\["models"\] and api_url and api_key' "$switch_file" 2>/dev/null; then
            python3 - "$switch_file" <<'PYEOF'
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
    print("APPLIED_B")
else:
    print("SKIP_B")
PYEOF
            if [[ $? -eq 0 ]]; then
                applied=$((applied + 1))
            fi
        else
            ok "hermes_cli/model_switch.py (Section 4) — 已应用，跳过"
        fi

        if [[ $applied -gt 0 ]]; then
            ok "hermes_cli/model_switch.py — 已应用"
        fi
    else
        error "hermes_cli/model_switch.py 不存在，跳过"
    fi

    # 4. gateway/config.py — gateway_restart_notification bridge 缺失修复
    #    Bug: config.yaml 中 discord:/telegram: 的 gateway_restart_notification 设置
    #    被静默忽略，因为：(a) bridging 循环遗漏了该 key；(b) from_dict() 不从 extra fallback。
    #    详见 PR: https://github.com/NousResearch/hermes-agent/pull/26896
    local config_file="${AGENT_DIR}/gateway/config.py"
    if [[ -f "$config_file" ]]; then
        local config_applied=0

        # 4a. bridging 循环：添加 gateway_restart_notification 到 bridge 列表
        if grep -q '"gateway_restart_notification" in platform_cfg' "$config_file" 2>/dev/null; then
            ok "gateway/config.py (bridge 循环) — 已应用，跳过"
        else
            python3 - "$config_file" <<'PYEOF'
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
    print("APPLIED_A")
else:
    print("SKIP_A")
PYEOF
            if [[ $? -eq 0 ]]; then
                config_applied=$((config_applied + 1))
            fi
        fi

        # 4b. PlatformConfig.from_dict(): 从 extra fallback 读取 gateway_restart_notification
        if grep -q '_grn = data.get.*gateway_restart_notification' "$config_file" 2>/dev/null; then
            ok "gateway/config.py (from_dict extra fallback) — 已应用，跳过"
        else
            python3 - "$config_file" <<'PYEOF'
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
    print("APPLIED_B")
else:
    print("SKIP_B")
PYEOF
            if [[ $? -eq 0 ]]; then
                config_applied=$((config_applied + 1))
            fi
        fi

        if [[ $config_applied -gt 0 ]]; then
            ok "gateway/config.py — 已应用"
        fi
    else
        error "gateway/config.py 不存在，跳过"
    fi
}

show_status() {
    echo ""
    echo "═══════════════════════════════════════════════════"
    echo "  Hermes Patches 状态检查"
    echo "═══════════════════════════════════════════════════"
    echo ""

    local total=0
    local applied=0

    check_patch() {
        local label="$1"
        local file="$2"
        local pattern="$3"
        total=$((total + 1))
        if [[ -f "$file" ]]; then
            if grep -q "$pattern" "$file" 2>/dev/null; then
                echo -e "  ${GREEN}✓${NC} ${label}"
                applied=$((applied + 1))
            else
                echo -e "  ${RED}✗${NC} ${label} — 未应用"
            fi
        else
            echo -e "  ${YELLOW}?${NC} ${label} — 文件不存在"
        fi
    }

    check_patch "hermes-agent: providers.py (is_aggregator)" \
        "${AGENT_DIR}/hermes_cli/providers.py" \
        'startswith.*"custom:"'

    check_patch "hermes-agent: doctor.py (vendor-prefix check)" \
        "${AGENT_DIR}/hermes_cli/doctor.py" \
        'startswith.*"custom:"'

    check_patch "hermes-agent: model_switch.py (Section 3: models 白名单)" \
        "${AGENT_DIR}/hermes_cli/model_switch.py" \
        'and not models_list'

    check_patch "hermes-agent: model_switch.py (Section 4: grp 白名单)" \
        "${AGENT_DIR}/hermes_cli/model_switch.py" \
        'if not grp\["models"\]'

    check_patch "hermes-agent: config.py (bridge: gateway_restart_notification)" \
        "${AGENT_DIR}/gateway/config.py" \
        '"gateway_restart_notification" in platform_cfg'

    check_patch "hermes-agent: config.py (from_dict: extra fallback)" \
        "${AGENT_DIR}/gateway/config.py" \
        '_grn = data.get.*gateway_restart_notification'

    echo ""
    echo "───────────────────────────────────────────────────"
    echo "  状态: ${applied}/${total} patches 已应用"
    echo "───────────────────────────────────────────────────"
    echo ""

    if [[ $applied -eq $total ]]; then
        ok "所有 patches 已应用，无需重新应用"
        return 0
    elif [[ $applied -eq 0 ]]; then
        warn "所有 patches 未应用，建议执行: $0 apply"
        return 1
    else
        warn "部分 patches 未应用，建议执行: $0 apply"
        return 1
    fi
}

# ── 主命令分发 ───────────────────────────────────────────────────────────────

CMD="${1:-check}"

case "$CMD" in
    apply)
        echo ""
        echo "═══════════════════════════════════════════════════"
        echo "  应用 Hermes Patches"
        echo "═══════════════════════════════════════════════════"
        echo ""
        apply_hermes_agent
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
