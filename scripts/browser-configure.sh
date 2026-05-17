#!/bin/bash
# =============================================================================
# Hermes 浏览器自动化方案配置入口（统一调度三种 CDP 接入方式）
# =============================================================================
#
# 【脚本作用】
#   Hermes 通过 CDP（Chrome DevTools Protocol）或 MCP 协议操作 Chrome 浏览器。
#   本脚本是三种浏览器接入方案的统一入口，负责：
#     1. 根据用户参数选择具体方案
#     2. 执行该方案所需的预置逻辑（profile 拷贝、daemon 启动、端口发现等）
#     3. 将最终的 CDP URL 写入 ~/.hermes/.env 的 BROWSER_CDP_URL 变量
#        （仅 buildin-isolation / buildin-inspect 方案需要，bb-browser 通过 MCP 直连）
#        Hermes Gateway 每个 turn 自动重载 .env，下一轮对话即生效，无需重启
#
# 【三种方案对比】
#
#   ┌─────────────────────┬──────────────────┬───────────────────┬──────────────────┐
#   │       方案           │  bb-browser      │ buildin-isolation │  buildin-inspect │
#   │                     │ （★默认推荐★）     │                   │                  │
#   ├─────────────────────┼──────────────────┼───────────────────┼──────────────────┤
#   │ 实现原理              │ 独立 user-data-  │ 独立 user-data-    │ 主 Chrome 默认    │
#   │                     │ dir + 最小拷贝    │ dir + 最小拷贝      │ profile + inspect│
#   │ Chrome 实例          │ 独立（隔离）      │ 独立（隔离）         │ 主 Chrome（共享）  │
#   │ 生命周期管理          │ daemon 自动      │ 手动启动/关闭        │ 用户手动开启选项    │
#   │ 登录态来源            │ 主 profile 拷贝  │ 主 profile 拷贝     │ 实时共享          │
#   │ 每次连接是否弹授权     │ ✅ 无            │ ✅ 无               │ ❌ 有（每次弹窗）  │
#   │ 适合批量/密集操作      │ ✅ 是            │ ✅ 是              │ ❌ 否             │
#   │ 影响日常浏览          │ ❌ 不影响         │ ❌ 不影响           │ ✅ 共享同一窗口     │
#   │ 启动复杂度            │ 一键 daemon      │ 手动起 Chrome       │ Chrome 内点选项    │
#   │ 资源占用              │ 中（独立进程）     │ 中（独立进程）       │ 低（复用主 Chrome) │
#   └─────────────────────┴──────────────────┴────────────────────┴──────────────────┘
#
#   buildin-isolation 与 bb-browser 原理一致（独立 Chrome + 最小化 profile 拷贝），
#   差别仅在生命周期管理：bb-browser 有 daemon 自动管理，buildin-isolation 需手动启动 Chrome。
#   因此选择 buildin-isolation 时本脚本会主动提示并推荐切换到 bb-browser。
#
# 【应用场景】
#
#   bb-browser（默认推荐）:
#     - 日常 Hermes Browser 工具使用的首选
#     - 需要批量/密集操作（爬数据、自动化测试、批量发帖等）
#     - 希望与日常浏览完全隔离，不互相干扰
#     - 不想自己管理 Chrome 进程生命周期
#
#   buildin-isolation:
#     - 不想/无法安装 bb-browser，但又需要无弹窗的密集操作
#     - 需要完全自定义 Chrome 启动参数
#     - 临时一次性调试
#
#   buildin-inspect:
#     - 偶尔轻量操作，能接受每次弹授权窗
#     - 需要直接复用主 Chrome 的实时登录态（如刚登录的网站）
#     - 不想启动额外 Chrome 实例
#
# 【何时执行本脚本】
#
#   1. 首次配置 Hermes 浏览器自动化时（必须执行一次）
#   2. 切换不同方案时
#   3. 主 Chrome 登录态变更后（仅 bb-browser / buildin-isolation 需要重新同步）
#   4. Chrome 重启后（仅 buildin-inspect 需要重新发现端口）
#
# 【如何执行】
#
#   ~/.hermes/scripts/browser-configure.sh                      # 默认 bb-browser
#   ~/.hermes/scripts/browser-configure.sh bb-browser           # 显式指定
#   ~/.hermes/scripts/browser-configure.sh buildin-isolation    # buildin-isolation
#   ~/.hermes/scripts/browser-configure.sh buildin-inspect      # buildin-inspect
#   ~/.hermes/scripts/browser-configure.sh --help               # 显示帮助
#
# 【macOS Cookie v10 加密机制 — 为什么拷贝后仍能解密】
#   Chrome 在 macOS 上使用 Keychain 存储的 v10 加密密钥来加密 Cookies 等数据。
#   关键：v10 密钥绑定的是 **macOS 用户账户**，而非 user-data-dir 路径。
#   因此，同一 macOS 用户下的任何 Chrome 实例（无论使用哪个 user-data-dir）
#   都能从 Keychain 取出密钥并解密 Cookie。
#   这与 Windows 的 App-Bound Encryption 不同（Windows 绑定安装路径）。
#
# 【最小化拷贝的文件清单】
#
#   Root 级（1 个，位于 user-data-dir 根，仅 buildin-isolation 方案直接拷贝）:
#     Local State              — 加密密钥元数据、Profile 配置（~81 KB）
#     ⚠️ bb-browser 方案不直接覆盖此文件（会破坏 daemon 的单 profile 配置），
#       而是单独"精简"：保留 bb-browser 单 profile 结构 + 从主 Chrome 同步 gaia 信息
#       （确保 Chrome 启动时 Local State 与 Preferences/Cookies 的 gaia_id 一致）
#
#   Profile 级（6 个，位于 user-data-dir/<profile>，所有方案都拷贝）:
#     Cookies                  — 所有网站的 Cookie（~1.3 MB，最关键）
#     Login Data               — 保存的账号密码（~96 KB）
#     Login Data For Account   — Google 账号登录数据（~96 KB）
#     Web Data                 — 自动填充、支付信息等（~224 KB）
#     Preferences              — 用户偏好设置（~325 KB）
#     Secure Preferences       — 安全相关的偏好设置（~78 KB）
#
#   不需要拷贝的：History（48MB）、Favicons（10MB）、Cache、Extensions 等。
#
# =============================================================================

set -euo pipefail

# ── 配置 ──────────────────────────────────────────────────────────────────────

HERMES_ENV="$HOME/.hermes/.env"
CHROME_ROOT="$HOME/Library/Application Support/Google/Chrome"
CHROME_APP="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"

# buildin-isolation 方案：独立 Chrome 实例的 user-data-dir 与 CDP 端口
ISOLATION_DIR="$HOME/.hermes/chrome-debug"
ISOLATION_PORT="9222"

# bb-browser daemon 默认 user-data-dir（来源：bb-browser cdp-discovery.ts）
BB_USER_DATA="$HOME/.bb-browser/browser/user-data"

# Profile 最小化拷贝的核心文件
ROOT_FILES=("Local State")
PROFILE_FILES=(
    "Cookies"
    "Login Data"
    "Login Data For Account"
    "Web Data"
    "Preferences"
    "Secure Preferences"
)

# 默认源 Profile（可被环境变量 CHROME_PROFILE 覆盖）
SOURCE_PROFILE="${CHROME_PROFILE:-Default}"

# ── 通用工具函数 ──────────────────────────────────────────────────────────────

_color() {
    case "$1" in
        red)    printf "\033[31m%s\033[0m" "$2" ;;
        green)  printf "\033[32m%s\033[0m" "$2" ;;
        yellow) printf "\033[33m%s\033[0m" "$2" ;;
        blue)   printf "\033[34m%s\033[0m" "$2" ;;
        cyan)   printf "\033[36m%s\033[0m" "$2" ;;
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
    # macOS 没有 numfmt，用 awk 实现
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
    # 将 BROWSER_CDP_URL 写入 ~/.hermes/.env（保留其他变量）
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
    # 打印脚本顶部的连续注释块（直到第一行非注释非空白行为止）
    awk '
        NR == 1 { next }                              # 跳过 shebang
        /^#/ { sub(/^# ?/, "", $0); print; next }
        /^[[:space:]]*$/ { print; next }
        { exit }
    ' "$0"
}

# ── 核心函数：最小化拷贝 Chrome Profile ───────────────────────────────────────
#
# 用法: _sync_profile <source_profile> <target_user_data_dir> <target_profile_name> [skip_root]
#   source_profile        — 主 Chrome 下的源 profile 目录名（如 "Default"、"Profile 2"）
#   target_user_data_dir  — 目标 user-data-dir 根（不含 profile 子目录）
#   target_profile_name   — 目标 profile 子目录名（bb-browser 必须为 "Default"）
#   skip_root             — 可选，任意非空值则跳过 Root 级文件（Local State）
#
# 行为:
#   - 拷贝 Local State 到 target_user_data_dir 根（除非 skip_root 参数存在）
#   - 拷贝 6 个 profile 级文件到 target_user_data_dir/target_profile_name
#   - 已存在的目标文件先备份为 .bak（如果 .bak 不存在）
#   - 退出码 0 = 成功，非 0 = 失败
#
# 【为什么 bb-browser 方案需要 skip_root？】
#   bb-browser 的 Local State 只有单 profile（"Default: bb-browser"），
#   而主 Chrome 的 Local State 包含多 profile（一只游民/Colin/YiNan）。
#   直接覆盖会导致 daemon 无法正确加载 Default profile。
#   bb-browser 方案在 _sync_profile 后单独精简 Local State：
#   保留单 profile 结构 + 从主 Chrome 同步 gaia_name/user_name/gaia_id，
#   确保 Chrome 启动时校验一致性（否则会清除 account_info）。
#
_sync_profile() {
    local src_profile="$1"
    local target_root="$2"
    local target_profile="$3"
    local skip_root="${4:-}"    # 非空 = 跳过 Root 级文件
    local src_root="$CHROME_ROOT"
    local target_profile_dir="$target_root/$target_profile"

    # 前置检查：源目录
    if [ ! -d "$src_root" ]; then
        echo "$(_color red '❌') Chrome 目录不存在: $src_root" >&2
        return 1
    fi
    if [ ! -d "$src_root/$src_profile" ]; then
        echo "$(_color red '❌') 源 Profile 不存在: $src_profile" >&2
        echo "   可用的 Profile:" >&2
        for d in "$src_root"/Default "$src_root"/Profile*; do
            [ -d "$d" ] && echo "     $(basename "$d")" >&2
        done
        return 1
    fi

    # Chrome 进程检测（文件锁风险）
    if pgrep -f "Google Chrome" >/dev/null 2>&1; then
        echo "$(_color yellow '⚠️') 检测到主 Chrome 正在运行，可能因文件锁导致同步不完整"
        echo "   建议先关闭主 Chrome（Cmd+Q）再继续"
        if [ -t 0 ]; then
            read -rp "   仍然继续？[y/N] " -n 1 -r; echo
            [[ ! $REPLY =~ ^[Yy]$ ]] && return 2
        else
            echo "   $(_color dim '（非交互终端，自动继续）')"
        fi
    fi

    mkdir -p "$target_root" "$target_profile_dir"

    local total=0 synced=0 skipped=0 size human

    # Root 级（skip_root 时跳过，用于 bb-browser 方案）
    if [ -n "$skip_root" ]; then
        echo "── 跳过 Root 级文件（保留目标 Local State）──"
    else
        echo "── 同步 Root 级文件 → $target_root ──"
        for f in "${ROOT_FILES[@]}"; do
            local src="$src_root/$f"
            local dst="$target_root/$f"
            if [ ! -f "$src" ]; then
                echo "  $(_color dim '⏭️  跳过') $f（源不存在）"
                skipped=$((skipped + 1))
                continue
            fi
            # 备份原文件（仅首次）
            [ -f "$dst" ] && [ ! -f "$dst.bak" ] && cp -f "$dst" "$dst.bak" 2>/dev/null || true
            size=$(stat -f '%z' "$src")
            cp -f "$src" "$dst"
            chmod 600 "$dst" 2>/dev/null || true
            human=$(_human_size "$size")
            echo "  $(_color green '✅') $f ($human)"
            total=$((total + size))
            synced=$((synced + 1))
        done
    fi

    # Profile 级
    echo ""
    echo "── 同步 Profile 级文件 → $target_profile_dir ──"
    for f in "${PROFILE_FILES[@]}"; do
        local src="$src_root/$src_profile/$f"
        local dst="$target_profile_dir/$f"
        if [ ! -f "$src" ]; then
            echo "  $(_color dim '⏭️  跳过') $f（源不存在）"
            skipped=$((skipped + 1))
            continue
        fi
        [ -f "$dst" ] && [ ! -f "$dst.bak" ] && cp -f "$dst" "$dst.bak" 2>/dev/null || true
        size=$(stat -f '%z' "$src")
        cp -f "$src" "$dst"
        chmod 600 "$dst" 2>/dev/null || true
        human=$(_human_size "$size")
        echo "  $(_color green '✅') $f ($human)"
        total=$((total + size))
        synced=$((synced + 1))
    done

    echo ""
    echo "  同步: $synced 个 / 跳过: $skipped 个 / 总大小: $(_human_size "$total")"
    return 0
}

# ── 核心函数：从 DevToolsActivePort 读取主 Chrome inspect 端口 ────────────────
#
# 来源: chrome-cdp-sync.sh 的核心逻辑（已验证可用）
# 文件格式（Chromium 约定）:
#   第 1 行: 端口号
#   第 2 行: WebSocket 路径（含 UUID，如 /devtools/browser/<uuid>）
#
_read_devtools_port() {
    local devtools_file="$CHROME_ROOT/DevToolsActivePort"
    if [ ! -f "$devtools_file" ]; then
        echo "$(_color red '❌') DevToolsActivePort 文件不存在: $devtools_file" >&2
        echo "" >&2
        echo "请先在主 Chrome 完成以下操作:" >&2
        echo "   1. 打开 chrome://inspect/#remote-debugging" >&2
        echo "   2. 勾选 \"Allow remote debugging for this browser instance\"" >&2
        echo "   3. 重新执行本脚本" >&2
        return 1
    fi

    local port ws_path
    port=$(sed -n '1p' "$devtools_file" | tr -d '[:space:]')
    ws_path=$(sed -n '2p' "$devtools_file" | tr -d '[:space:]')

    if [ -z "$port" ] || [ -z "$ws_path" ]; then
        echo "$(_color red '❌') DevToolsActivePort 格式无效:" >&2
        cat "$devtools_file" >&2
        return 1
    fi

    echo "ws://127.0.0.1:${port}${ws_path}"
}

# ── 核心函数：从 /json/version 拿 webSocketDebuggerUrl ────────────────────────
#
# 用法: _resolve_ws_url <port>
# 用于 buildin-isolation 与 bb-browser daemon
#
_resolve_ws_url() {
    local port="$1"
    local url
    url=$(curl -s --max-time 3 "http://127.0.0.1:${port}/json/version" 2>/dev/null \
        | grep -oE '"webSocketDebuggerUrl":[[:space:]]*"[^"]+"' \
        | sed 's/.*"\(ws[^"]*\)"/\1/' || true)
    if [ -z "$url" ]; then
        return 1
    fi
    echo "$url"
}

# ── 核心函数：等待 Chrome CDP 就绪并获取 WS URL ────────────────────────────────
#
# 用法: _wait_for_cdp <port> <max_wait_sec>
#   port          — Chrome remote-debugging-port
#   max_wait_sec  — 最大等待秒数（默认 10）
#
# 行为:
#   - 以 2 秒间隔轮询 http://127.0.0.1:<port>/json/version
#   - 拿到 webSocketDebuggerUrl 后立即返回（stdout + exit 0）
#   - 超时后返回 exit 1（stderr 输出错误信息）
#
_wait_for_cdp() {
    local port="$1"
    local max_wait="${2:-10}"
    local waited=0
    local ws_url

    while [ "$waited" -lt "$max_wait" ]; do
        ws_url=$(_resolve_ws_url "$port" || true)
        if [ -n "$ws_url" ]; then
            echo "$ws_url"
            return 0
        fi
        sleep 2
        waited=$((waited + 2))
    done

    echo "$(_color red '❌') Chrome CDP 服务在 ${max_wait}s 内未就绪（端口 $port）" >&2
    return 1
}

# =============================================================================
# 方案 1: bb-browser
# =============================================================================

run_bb_browser() {
    _section "方案: bb-browser（默认推荐）"
    echo ""
    echo "原理: bb-browser daemon 管理独立 Chrome 实例，"
    echo "      通过最小化拷贝主 Chrome profile 共享登录态。"
    echo ""

    # 1. 检查 bb-browser CLI
    if ! command -v bb-browser >/dev/null 2>&1; then
        echo "$(_color red '❌') 未检测到 bb-browser CLI"
        echo ""
        echo "请先安装 bb-browser:"
        echo "   npm install -g @epiral/bb-browser"
        echo "   或参考: https://github.com/epiral/bb-browser"
        exit 1
    fi
    echo "$(_color green '✅') bb-browser CLI: $(command -v bb-browser)"

    # 2. 修补 bb-browser cli.js：删除 --use-mock-keychain
    #    根因：该参数让 Chrome 使用假 Keychain 密钥，无法解密真实 cookie，
    #    导致所有网站登录态丢失。bb-browser 更新后需重新删除。
    local cli_js
    cli_js="$(dirname "$(command -v bb-browser)")/../lib/node_modules/bb-browser/dist/cli.js" 2>/dev/null || true
    if [ -f "$cli_js" ] && grep -q '"--use-mock-keychain"' "$cli_js"; then
        echo "$(_color yellow '🔧') 删除 --use-mock-keychain（假 Keychain，会破坏 cookie 解密）"
        sed -i '' '/"--use-mock-keychain",/d' "$cli_js"
        if grep -q '"--use-mock-keychain"' "$cli_js"; then
            echo "$(_color red '❌') 删除失败，请手动编辑: $cli_js"
            exit 1
        fi
        echo "  $(_color green '✅') 已删除"
    else
        echo "$(_color green '✅') --use-mock-keychain 已不存在（无需修补）"
    fi

    # 3. 完全停止 daemon + Chrome 进程
    echo ""
    echo "── 步骤 1/4: 停止 bb-browser daemon + Chrome 进程 ──"
    bb-browser daemon stop >/dev/null 2>&1 || true
    sleep 2
    # 强制杀掉带 --use-mock-keychain 的旧 Chrome 进程（可能还活着）
    local chrome_pid
    chrome_pid=$(pgrep -f "Google Chrome.*bb-browser" 2>/dev/null || true)
    if [ -n "$chrome_pid" ]; then
        echo "  杀掉残留 Chrome 进程: $chrome_pid"
        kill -9 $chrome_pid 2>/dev/null || true
        sleep 2
    fi

    # 4. 初始化 bb-browser user-data-dir（如未初始化则让 daemon 创建空白 profile）
    if [ ! -d "$BB_USER_DATA/Default" ]; then
        echo "$(_color yellow '⚠️') bb-browser user-data-dir 未初始化，先启动一次 daemon..."
        bb-browser daemon start >/dev/null 2>&1 || true
        sleep 5
        bb-browser daemon stop >/dev/null 2>&1 || true
        sleep 2
        # 再次杀 Chrome（daemon stop 可能没杀干净）
        pkill -9 -f "Google Chrome.*bb-browser" 2>/dev/null || true
        sleep 1
    fi

    # 5. 同步 profile 文件（skip_root = 不覆盖 Local State，后面单独精简）
    echo ""
    echo "── 步骤 2/4: 同步主 Chrome profile 登录态 ──"
    if ! _sync_profile "$SOURCE_PROFILE" "$BB_USER_DATA" "Default" "skip_root"; then
        echo "$(_color red '❌') Profile 同步失败"
        exit 1
    fi

    # 6. 精简 Local State：保留 bb-browser 单 profile 结构，从主 Chrome 同步 gaia 信息
    #    根因：Chrome 启动时校验 Local State 与 Preferences/Cookies 的一致性，
    #    如果 Local State 的 gaia_id 与 Preferences 不匹配，Chrome 会清除 account_info。
    echo ""
    echo "── 步骤 3/4: 精简 Local State（同步 gaia 信息）──"
    local bb_ls="$BB_USER_DATA/Local State"
    local chrome_ls="$CHROME_ROOT/Local State"
    if [ -f "$bb_ls" ] && [ -f "$chrome_ls" ]; then
        python3 << 'PYEOF'
import json, sys

bb_ls = "/Users/Colin/.bb-browser/browser/user-data/Local State"
chrome_ls = "/Users/Colin/Library/Application Support/Google/Chrome/Local State"

try:
    with open(chrome_ls, "r") as f:
        chrome_data = json.load(f)
    with open(bb_ls, "r") as f:
        bb_data = json.load(f)
except Exception as e:
    print(f"  ❌ 读取 Local State 失败: {e}", file=sys.stderr)
    sys.exit(1)

# 从主 Chrome Local State 获取 Default profile 的 gaia 信息
src_info = chrome_data.get("profile", {}).get("info_cache", {}).get("Default", {})
# 只保留 Default profile，删除不存在的其他 profile
info_cache = bb_data.get("profile", {}).get("info_cache", {})
removed = []
for k in list(info_cache.keys()):
    if k != "Default":
        del info_cache[k]
        removed.append(k)

# 同步关键 gaia 字段（确保与 Preferences/Cookies 中的 account_info 一致）
synced_fields = []
for key in ["gaia_name", "user_name", "gaia_id", "name"]:
    if key in src_info:
        info_cache.setdefault("Default", {})[key] = src_info[key]
        synced_fields.append(key)

# 设置单 profile 配置
bb_data.setdefault("profile", {})["profiles_order"] = ["Default"]
bb_data["profile"]["last_active_profiles"] = ["Default"]
bb_data["profile"]["last_used"] = "Default"

with open(bb_ls, "w") as f:
    json.dump(bb_data, f, indent=2)

print(f"  ✅ 精简完成: 删除 {len(removed)} 个多余 profile, 同步字段: {', '.join(synced_fields)}")
if removed:
    print(f"     已删除: {', '.join(removed)}")
PYEOF
    else
        echo "$(_color yellow '⚠️') Local State 文件不存在，跳过精简"
    fi

    # 7. 启动 daemon
    echo ""
    echo "── 步骤 4/4: 启动 bb-browser daemon ──"
    bb-browser daemon start >/dev/null 2>&1
    sleep 5

    # 验证 Chrome 启动参数不含 --use-mock-keychain
    local chrome_args
    chrome_args=$(ps aux | grep "Google Chrome.*bb-browser" | grep -v Helper | grep -v grep || true)
    if echo "$chrome_args" | grep -q "use-mock-keychain"; then
        echo "$(_color red '❌') Chrome 仍带 --use-mock-keychain！可能需要杀掉旧进程后重试"
        echo "  执行: pkill -9 -f 'Google Chrome.*bb-browser'; 然后重新运行本脚本"
    else
        echo "$(_color green '✅') Chrome 启动参数正确（无 --use-mock-keychain）"
    fi

    # bb-browser 通过 MCP 协议直连 daemon，不需要写入 .env
    echo "$(_color green '✅') bb-browser daemon 已启动"

    echo ""
    echo "$(_color green '🎉 bb-browser 方案配置完成！')"
    echo ""
    echo "$(_color dim '提示：')"
    echo "  - 查看 daemon 状态: bb-browser daemon status"
    echo "  - 主 Chrome 登录态变更后，重新运行本脚本即可"
    echo "  - bb-browser 更新后需重新运行本脚本（自动修补 --use-mock-keychain）"
}

# =============================================================================
# 方案 2: buildin-isolation
# =============================================================================

run_buildin_isolation() {
    _section "方案: 内建 Isolation（独立 Chrome + profile 拷贝）"
    echo ""

    local ws_url

    # 推荐切换到 bb-browser
    echo "$(_color yellow '💡 提示：') 此方案与 bb-browser 实现原理一致——"
    echo "   都是 \"独立 Chrome 实例 + 最小化拷贝主 profile\"，"
    echo "   差异仅在 Chrome 进程生命周期管理："
    echo ""
    echo "   $(_color cyan 'bb-browser')          $(_color dim '←') daemon 自动启停 Chrome、自动发现 CDP"
    echo "   $(_color cyan 'Isolation 方案')      $(_color dim '←') 需要你手动启动/关闭 Chrome 进程"
    echo ""
    echo "   $(_color green '推荐切换到 bb-browser 方案，更省心。')"
    echo ""

    if [ -t 0 ]; then
        read -rp "是否切换到 bb-browser 方案？[Y/n] " -n 1 -r; echo
        if [[ ! $REPLY =~ ^[Nn]$ ]]; then
            echo "→ 切换到 bb-browser 方案..."
            run_bb_browser
            return
        fi
        echo "→ 继续使用 buildin-isolation 方案"
    else
        echo "$(_color dim '（非交互终端，跳过推荐确认，继续执行 isolation 方案）')"
    fi

    # 1. 同步 profile
    echo ""
    echo "── 步骤 1/3: 同步主 Chrome profile → ${ISOLATION_DIR} ──"
    if ! _sync_profile "$SOURCE_PROFILE" "${ISOLATION_DIR}" "$SOURCE_PROFILE"; then
        echo "$(_color red '❌') Profile 同步失败"
        exit 1
    fi

    # 2. 启动调试 Chrome + 等待 CDP 就绪
    echo ""
    echo "── 步骤 2/3: 启动调试 Chrome（端口 ${ISOLATION_PORT}）──"
    if lsof -iTCP:${ISOLATION_PORT} -sTCP:LISTEN -P -n >/dev/null 2>&1; then
        echo "$(_color yellow '⚠️') 端口 ${ISOLATION_PORT} 已监听，复用现有 Chrome 实例"
    else
        if [ ! -x "$CHROME_APP" ]; then
            echo "$(_color red '❌') Chrome 未找到: $CHROME_APP"
            exit 1
        fi
        nohup "$CHROME_APP" \
            --remote-debugging-port=${ISOLATION_PORT} \
            --user-data-dir="${ISOLATION_DIR}" \
            --no-first-run \
            --no-default-browser-check \
            --variations-override-country=us \
            >/dev/null 2>&1 &
        echo "$(_color green '✅') 调试 Chrome 已启动 (PID $!)"
    fi

    # 3. 等待 CDP 就绪并写入 .env
    echo ""
    echo "── 步骤 3/3: 等待 CDP 就绪 + 写入 BROWSER_CDP_URL ──"
    echo "   等待 Chrome CDP 服务就绪（最多 10s）..."
    if ws_url=$(_wait_for_cdp "${ISOLATION_PORT}" 10); then
        echo "   $(_color green '✅') CDP 就绪"
        _update_env "$ws_url" "Hermes Buildin Isolation Chrome (端口 ${ISOLATION_PORT})"
        echo "   $(_color green '✅') BROWSER_CDP_URL 已写入 ~/.hermes/.env"
        echo "   $(_color dim \"$ws_url\")"
    else
        echo "$(_color red '❌') CDP 服务未就绪，请手动检查:"
        echo "   1. Chrome 进程是否存活: pgrep -f \"user-data-dir=${ISOLATION_DIR}\""
        echo "   2. 端口是否监听: lsof -iTCP:${ISOLATION_PORT}"
        echo "   3. 端口被占用则杀进程后重试: pkill -f \"user-data-dir=${ISOLATION_DIR}\""
        exit 1
    fi

    echo ""
    echo "$(_color green '🎉 Buildin Isolation 方案配置完成！') Hermes 下一轮对话自动生效。"
    echo ""
    echo "$(_color dim '提示：')"
    echo "  - 关闭调试 Chrome: pkill -f \"user-data-dir=${ISOLATION_DIR}\""
    echo "  - 主 Chrome 登录态变更后，重新运行本脚本即可"
}

# =============================================================================
# 方案 3: buildin-inspect
# =============================================================================

run_buildin_inspect() {
    _section "方案: 内建 Inspect（主 Chrome chrome://inspect）"
    echo ""
    echo "原理: 主 Chrome 通过 chrome://inspect/#remote-debugging 暴露 CDP 端口。"
    echo "      每次新连接 Chrome 会弹出授权确认窗口。"
    echo ""

    local ws_url
    local chrome_running=false
    local devtools_file="$CHROME_ROOT/DevToolsActivePort"
    local waited max_wait=60
    local old_port_content new_content new_port final_content old_port

    # 1. 检测 Chrome 是否在运行
    echo "── 步骤 1/3: 检测 Chrome 运行状态 ──"
    if pgrep -f "Google Chrome" >/dev/null 2>&1; then
        echo "$(_color green '✅') Chrome 正在运行"
        chrome_running=true
    else
        echo "$(_color yellow '⚠️') Chrome 未运行，将主动启动..."
        chrome_running=false
    fi

    # 2. 未运行则主动启动 Chrome（Chrome 148+ 禁止 --remote-debugging-port 在默认 profile）
    #    改用 open 命令启动 Chrome 并直接导航到 chrome://inspect 页面，
    #    用户只需点一下 toggle，脚本自动轮询等待 DevToolsActivePort 更新
    if ! $chrome_running; then
        echo ""
        echo "── 步骤 2/3: 启动 Chrome + 等待启用 inspect ──"
        echo ""
        echo "   $(_color yellow '⚠️') Chrome 148+ 禁止在默认 user-data-dir 使用"
        echo "      --remote-debugging-port 参数，需手动启用 inspect。"
        echo ""

        # 记录当前 DevToolsActivePort 快照（用于检测用户是否已点 toggle）
        old_port_content=""
        if [ -f "$devtools_file" ]; then
            old_port_content=$(cat "$devtools_file" 2>/dev/null || true)
            echo "   当前 DevToolsActivePort 快照: $(echo "$old_port_content" | tr '\n' ' ')"
        else
            echo "   DevToolsActivePort 尚不存在，等待创建..."
        fi

        # 启动 Chrome 并打开 inspect 页面
        open -a "Google Chrome" "chrome://inspect/#remote-debugging" --args --variations-override-country=us 2>/dev/null || {
            echo "$(_color red '❌') 无法启动 Chrome"
            exit 1
        }
        echo "   $(_color green '✅') Chrome 已启动，inspect 页面已打开"

        echo ""
        echo "   $(_color cyan '👆 请在 Chrome 中勾选：')"
        echo "      \"Allow remote debugging for this browser instance\""
        echo ""

        # 轮询等待 DevToolsActivePort 创建或更新（用户点 toggle 后触发）
        waited=0
        echo "   等待你启用 inspect（最多 60s，可 Ctrl+C 跳过）..."
        while [ "$waited" -lt "$max_wait" ]; do
            if [ -f "$devtools_file" ] && [ -s "$devtools_file" ]; then
                new_content=$(cat "$devtools_file" 2>/dev/null || true)
                if [ "$new_content" != "$old_port_content" ]; then
                    # 内容变了（或从无到有），验证端口是否真的在监听
                    new_port=$(echo "$new_content" | sed -n '1p' | tr -d '[:space:]')
                    if [ -n "$new_port" ] && lsof -iTCP:"$new_port" -sTCP:LISTEN -P -n >/dev/null 2>&1; then
                        echo "   $(_color green '✅') DevToolsActivePort 已更新，端口 $new_port 正在监听 (${waited}s)"
                        break
                    fi
                fi
            fi
            sleep 2
            waited=$((waited + 2))
        done

        if [ ! -f "$devtools_file" ] || [ ! -s "$devtools_file" ]; then
            echo "$(_color red '❌') DevToolsActivePort 未在 ${max_wait}s 内出现"
            echo ""
            echo "请确认已在 Chrome 中勾选 Allow remote debugging，然后重新执行:"
            echo "  $0 buildin-inspect"
            exit 1
        fi

        # 二次确认：文件存在但内容没变（用户可能没点 toggle）
        final_content=$(cat "$devtools_file" 2>/dev/null || true)
        if [ "$final_content" = "$old_port_content" ] && [ -n "$old_port_content" ]; then
            old_port=$(echo "$old_port_content" | sed -n '1p' | tr -d '[:space:]')
            if ! lsof -iTCP:"$old_port" -sTCP:LISTEN -P -n >/dev/null 2>&1; then
                echo "$(_color red '❌') DevToolsActivePort 未更新（旧端口 $old_port 未监听）"
                echo ""
                echo "请确认已在 Chrome 中勾选 Allow remote debugging，然后重新执行:"
                echo "  $0 buildin-inspect"
                exit 1
            fi
            # 旧端口仍在监听 → 复用
            echo "   $(_color dim 'DevToolsActivePort 未变，但端口仍在监听，复用旧端口')"
        fi
    fi

    # 3. 读取端口 + 写入 .env
    echo ""
    echo "── 步骤 3/3: 读取 CDP 端口 + 写入 BROWSER_CDP_URL ──"
    ws_url=$(_read_devtools_port) || exit 1

    _update_env "$ws_url" "Chrome CDP (chrome://inspect, 重启Chrome后需重新同步)"
    echo "$(_color green '✅') BROWSER_CDP_URL 已写入 ~/.hermes/.env"
    echo "   $(_color dim \"$ws_url\")"

    echo ""
    echo "$(_color green '🎉 Buildin Inspect 方案配置完成！') Hermes 下一轮对话自动生效。"
    echo ""
    echo "$(_color dim '提示：')"
    echo "  - Chrome 重启后需重新执行本脚本（端口和 UUID 会变）"
    echo "  - 每次 Hermes 调用 Browser 工具时主 Chrome 会弹授权窗，请保持注意"
}

# =============================================================================
# 主入口
# =============================================================================

MODE="${1:-bb-browser}"

case "$MODE" in
    bb-browser|bb)
        run_bb_browser
        ;;
    buildin-isolation|isolation|a|A)
        run_buildin_isolation
        ;;
    buildin-inspect|inspect|b|B)
        run_buildin_inspect
        ;;
    --help|-h|help)
        _show_help
        exit 0
        ;;
    *)
        echo "$(_color red '❌') 未知方案: $MODE"
        echo ""
        echo "用法:"
        echo "   $0 [bb-browser|buildin-isolation|buildin-inspect|--help]"
        echo ""
        echo "可选方案:"
        echo "   bb-browser           bb-browser daemon（★默认推荐★）"
        echo "   buildin-isolation    独立 Chrome + profile 拷贝（手动管理生命周期）"
        echo "   buildin-inspect      主 Chrome chrome://inspect（每次弹授权窗）"
        echo "   --help               显示完整帮助"
        exit 1
        ;;
esac
