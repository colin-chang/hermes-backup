#!/bin/bash
# =============================================================================
# Hermes 浏览器方案配置入口
# =============================================================================
#
# 【脚本作用】
#   验证和配置 Hermes 浏览器工具的后端。当前两种方案：
#
#   ┌─────────────────────┬───────────────────────┬──────────────────────┐
#   │       方案           │  opencli（★默认推荐★） │  isolation（应急备用） │
#   ├─────────────────────┼───────────────────────┼──────────────────────┤
#   │ 实现原理              │ 通过 Browser Bridge    │ 独立 Chrome + CDP    │
#   │                     │ 扩展复用主 Chrome       │ 手动启动             │
#   │ Chrome 实例          │ 主 Chrome（共享）       │ 独立（隔离）          │
#   │ 登录态来源            │ 实时共享               │ 主 profile 拷贝       │
#   │ 每次连接是否弹授权     │ ✅ 无                  │ ✅ 无                │
#   │ 资源占用              │ 低（复用主 Chrome）     │ 中（独立进程）        │
#   └─────────────────────┴───────────────────────┴──────────────────────┘
#
# 【何时执行】
#   1. 首次配置时（验证 OpenCLI 连接）
#   2. 需要使用独立 Chrome 隔离环境时
#
# 【使用】
#   ~/.hermes/scripts/browser-configure.sh                    # 默认 opencli
#   ~/.hermes/scripts/browser-configure.sh opencli            # 显式验证
#   ~/.hermes/scripts/browser-configure.sh isolation          # 独立 Chrome
#   ~/.hermes/scripts/browser-configure.sh --help             # 帮助
#
# =============================================================================

set -euo pipefail

HERMES_ENV="$HOME/.hermes/.env"
CHROME_ROOT="$HOME/Library/Application Support/Google/Chrome"
CHROME_APP="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
ISOLATION_DIR="$HOME/.hermes/chrome-debug"
ISOLATION_PORT="9222"
SOURCE_PROFILE="${CHROME_PROFILE:-Default}"

PROFILE_FILES=(
    "Cookies" "Login Data" "Login Data For Account"
    "Web Data" "Preferences" "Secure Preferences"
)

_color() {
    case "$1" in
        red)    printf "\033[31m%s\033[0m" "$2" ;;
        green)  printf "\033[32m%s\033[0m" "$2" ;;
        yellow) printf "\033[33m%s\033[0m" "$2" ;;
        blue)   printf "\033[34m%s\033[0m" "$2" ;;
        dim)    printf "\033[2m%s\033[0m" "$2" ;;
        *)      printf "%s" "$2" ;;
    esac
}

_section() {
    echo ""
    echo "╔══════════════════════════════════════════════════╗"
    printf "║   %-48s ║\n" "$1"
    echo "╚══════════════════════════════════════════════════╝"
}

_human_size() {
    local bytes=$1
    if [ "$bytes" -ge 1048576 ]; then
        awk "BEGIN{printf \"%.1fMB\", $bytes/1048576}"
    elif [ "$bytes" -ge 1024 ]; then
        awk "BEGIN{printf \"%.1fKB\", $bytes/1024}"
    else
        echo "${bytes}B"
    fi
}

_update_env() {
    local url="$1"
    local comment="${2:-Hermes Browser CDP}"
    if [ ! -f "$HERMES_ENV" ]; then
        mkdir -p "$(dirname "$HERMES_ENV")"
        touch "$HERMES_ENV"
    fi
    if grep -q "^BROWSER_CDP_URL=" "$HERMES_ENV"; then
        sed -i '' "s|^BROWSER_CDP_URL=.*|BROWSER_CDP_URL=$url|" "$HERMES_ENV"
    else
        echo "" >> "$HERMES_ENV"
        echo "# --- $comment ---" >> "$HERMES_ENV"
        echo "BROWSER_CDP_URL=$url" >> "$HERMES_ENV"
    fi
}

_show_help() {
    awk '
        NR == 1 { next }
        /^#/ { sub(/^# ?/, "", $0); print; next }
        /^[[:space:]]*$/ { print; next }
        { exit }
    ' "$0"
}

_resolve_ws_url() {
    local port="$1"
    local url
    url=$(curl -s --max-time 3 "http://127.0.0.1:${port}/json/version" 2>/dev/null \
        | grep -oE '"webSocketDebuggerUrl":[[:space:]]*"[^"]+"' \
        | sed 's/.*"\\(ws[^"]*\\)"/\\1/' || true)
    [ -z "$url" ] && return 1
    echo "$url"
}

# =============================================================================
# 方案 1: opencli（默认推荐）
# =============================================================================

run_opencli() {
    _section "方案: opencli（默认推荐）"
    echo ""
    echo "原理: OpenCLI Browser Bridge 扩展直接复用主 Chrome 所有登录态，"
    echo "      无需独立 Chrome 实例、无需 profile 同步。"
    echo ""

    # 1. 检查 opencli CLI
    if ! command -v opencli >/dev/null 2>&1; then
        echo "$(_color red '❌') 未检测到 opencli CLI"
        echo ""
        echo "请先安装:"
        echo "   npm install -g @jackwener/opencli"
        echo "   参考: https://github.com/jackwener/opencli"
        exit 1
    fi
    echo "$(_color green '✅') opencli CLI: $(command -v opencli)"
    opencli --version 2>/dev/null || true

    # 2. 验证连接
    echo ""
    echo "── 验证 Browser Bridge 连接 ──"
    if opencli doctor 2>&1; then
        echo ""
        echo "$(_color green '✅') OpenCLI 连接正常，Hermes browser_* 工具可直接使用。"
        echo ""
        echo "提示:"
        echo "   • 站点适配器: opencli <site> <command> -f json"
        echo "   • 列出所有命令: opencli list"
        echo "   • 浏览器自动化: opencli browser work <command>"
    else
        echo ""
        echo "$(_color red '❌') 连接失败，请检查:"
        echo "   1. Chrome Web Store 扩展是否已安装: https://chromewebstore.google.com/detail/opencli/ildkmabpimmkaediidaifkhjpohdnifk"
        echo "   2. 扩展是否已启用（chrome://extensions）"
        echo "   3. 运行 opencli doctor 诊断"
        exit 1
    fi
}

# =============================================================================
# 方案 2: isolation（应急独立 Chrome）
# =============================================================================

run_isolation() {
    _section "方案: isolation（应急独立 Chrome）"
    echo ""
    echo "原理: 启动独立 Chrome 实例 + 最小化拷贝主 Chrome profile，"
    echo "      适用于 OpenCLI 不可用或需要完全隔离的场景。"
    echo ""

    # 停止旧实例
    local old_pid
    old_pid=$(pgrep -f "Google Chrome.*chrome-debug" 2>/dev/null || true)
    if [ -n "$old_pid" ]; then
        echo "  停止旧 Chrome 实例: $old_pid"
        kill -9 $old_pid 2>/dev/null || true
        sleep 2
    fi

    # 同步 profile
    echo ""
    echo "── 同步主 Chrome profile ──"
    local target_dir="$ISOLATION_DIR/Default"
    mkdir -p "$ISOLATION_DIR" "$target_dir"

    local synced=0 skipped=0 total=0
    for f in "${PROFILE_FILES[@]}"; do
        local src="$CHROME_ROOT/$SOURCE_PROFILE/$f"
        local dst="$target_dir/$f"
        if [ ! -f "$src" ]; then
            echo "  $(_color dim '⏭️  跳过') $f（源不存在）"
            skipped=$((skipped + 1))
            continue
        fi
        local size
        size=$(stat -f '%z' "$src")
        cp -f "$src" "$dst"
        chmod 600 "$dst" 2>/dev/null || true
        echo "  $(_color green '✅') $f ($(_human_size "$size"))"
        total=$((total + size))
        synced=$((synced + 1))
    done
    echo "  同步: $synced 个 / 跳过: $skipped 个 / 总: $(_human_size "$total")"

    # 启动 Chrome
    echo ""
    echo "── 启动独立 Chrome ──"
    "$CHROME_APP" \
        --remote-debugging-port="$ISOLATION_PORT" \
        --user-data-dir="$ISOLATION_DIR" \
        --no-first-run \
        --no-default-browser-check \
        &>/dev/null &
    
    local cdp_url
    cdp_url=$(_resolve_ws_url "$ISOLATION_PORT" || true)
    if [ -n "$cdp_url" ]; then
        _update_env "$cdp_url" "Hermes Browser CDP (isolation)"
        echo "$(_color green '✅') Chrome CDP 就绪: $cdp_url"
        echo "   BROWSER_CDP_URL 已写入 $HERMES_ENV"
    else
        echo "$(_color yellow '⚠️') Chrome 启动中，CDP 尚未就绪（可能需要 10-15 秒）"
        echo "   端口: $ISOLATION_PORT"
    fi
}

# =============================================================================
# 入口
# =============================================================================

case "${1:-opencli}" in
    --help|-h)
        _show_help
        ;;
    opencli|openCLI|OpenCLI)
        run_opencli
        ;;
    isolation|isolate|iso)
        run_isolation
        ;;
    *)
        echo "$(_color red '❌') 未知方案: $1"
        echo "   可用: opencli（默认）, isolation"
        exit 1
        ;;
esac
