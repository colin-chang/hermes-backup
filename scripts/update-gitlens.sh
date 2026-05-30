#!/bin/bash
#
# update-gitlens.sh — GitLens Rebuild 版本自动更新与多端同步脚本 (V15)
#
# 用途：
#   自动检测并安装 Rebuild-gitlens (第三方 GitLens 重建版) 的最新版本，
#   安装到本地 VS Code，并通过 SCP 同步到远程 VS Code Server，
#   最后清理所有环境中旧版本残留。
#
# 触发方式：
#   由 Hermes Cron 定时任务 "Update GitLens" 每日 02:00 (Asia/Shanghai) 触发，
#   通过 no_agent=true 模式直接投递脚本 stdout 到 Mattermost 频道。
#
# 执行流程：
#   1. 从 GitHub Tags 页面抓取最新版本号（绕过 API rate limit）
#   2. 版本合法性校验（semver 格式 + 非空非 null）
#   3. 自动探测两种 VSIX 命名格式（纯版本号 vs 带 v 前缀）
#   4. 比对本地已安装版本 + 远程服务器状态，若均最新则跳过
#   5. 下载 VSIX 并本地安装到 VS Code
#   6. SCP 同步扩展目录到远程服务器 (orb) 的 2 个目标路径：
#      - 本地: ~/.vscode/extensions
#      - 远程: ~/.vscode-server/extensions
#   7. 用 jq 更新远程 extensions.json 中的 GitLens 版本和路径
#   8. 清理本地+远程共 2 个目录中的旧版本扩展
#
# 关键设计：
#   - set -euo pipefail 严格错误处理
#   - trap 确保临时文件清理
#   - url_exists 探测含超时和重定向限制，防止挂起
#   - 清理步骤加 || true 容错，避免权限问题导致整体失败
#   - 输出格式化适配 no_agent=true（stdout 直投递，无需 LLM 润色）
#
# 依赖：
#   curl, ssh, scp, jq, find, /usr/local/bin/code
#   SSH 免密登录远程主机 "orb"
#

set -euo pipefail

# ── 目录定义 ──────────────────────────────────────────────────────────────────
LOCAL_VSCODE_DIR="$HOME/.vscode/extensions"
REMOTE_HOST="orb"
REMOTE_VSCODE_DIR="/home/colin/.vscode-server/extensions"

TAGS_URL="https://github.com/AliverAnme/Rebuild-gitlens/tags"
REPO_DOWNLOAD_BASE="https://github.com/AliverAnme/Rebuild-gitlens/releases/download"

# ── 工具函数 ──────────────────────────────────────────────────────────────────

# 格式化输出（适配 no_agent 直投递）
report() {
    local version="${1:-未知}"
    local status="$2"
    local note="${3:-无}"
    echo "📦 GitLens 更新检查"
    echo "版本：$version"
    echo "状态：$status"
    echo "备注：$note"
}

is_valid_version() {
    local v="$1"
    # 非空且非 null
    [ -n "$v" ] || return 1
    [ "$v" != "null" ] || return 1
    # 版本格式：1.2.3 / v1.2.3 / 1.2.3-beta.1 / v1.2.3-rc1 等
    echo "$v" | grep -Eq '^v?[0-9]+(\.[0-9]+){1,3}([.-][0-9A-Za-z._-]+)?$'
}

# HEAD 检测 URL 是否存在；加超时和重定向次数限制
url_exists() {
    local url="$1"
    curl -fsIL --max-time 15 --max-redirs 5 "$url" >/dev/null 2>&1
}

# ── 1. 获取最新版本 ──────────────────────────────────────────────────────────
RAW_LATEST_TAG=$(
    curl -fsSL "$TAGS_URL" \
    | sed -n 's#.*href="/AliverAnme/Rebuild-gitlens/releases/tag/\([^"]*\)".*#\1#p' \
    | head -n 1 \
    | tr -d '[:space:]'
)

# ── 2. 版本合法性检查 ────────────────────────────────────────────────────────
if ! is_valid_version "${RAW_LATEST_TAG:-}"; then
    report "未知" "检查失败" "从 tags 页面获取到非法版本: '${RAW_LATEST_TAG:-<empty>}'"
    exit 1
fi

# 保留两种形式
LATEST_VERSION="${RAW_LATEST_TAG#v}"   # 去掉前缀 v（用于目录名）
TAG_WITH_V="$RAW_LATEST_TAG"           # 保留原始 tag（用于 release 路径）

# ── 3. 自动探测 VSIX 命名 ───────────────────────────────────────────────────
FILE_NAME_A="gitlens-$LATEST_VERSION.vsix"
FILE_NAME_B="gitlens-$TAG_WITH_V.vsix"

DOWNLOAD_URL_A="$REPO_DOWNLOAD_BASE/$TAG_WITH_V/$FILE_NAME_A"
DOWNLOAD_URL_B="$REPO_DOWNLOAD_BASE/$TAG_WITH_V/$FILE_NAME_B"

if url_exists "$DOWNLOAD_URL_A"; then
    FILE_NAME="$FILE_NAME_A"
    DOWNLOAD_URL="$DOWNLOAD_URL_A"
elif [ "$FILE_NAME_A" != "$FILE_NAME_B" ] && url_exists "$DOWNLOAD_URL_B"; then
    FILE_NAME="$FILE_NAME_B"
    DOWNLOAD_URL="$DOWNLOAD_URL_B"
else
    report "$LATEST_VERSION" "检查失败" "未找到可下载的 VSIX (尝试过 $DOWNLOAD_URL_A)"
    exit 1
fi

# ── 4. 检查本地安装情况 ─────────────────────────────────────────────────────
CURRENT_DIR=$(find "$LOCAL_VSCODE_DIR" -maxdepth 1 -name "eamodio.gitlens-*" -type d 2>/dev/null | sort | tail -n 1 || true)
CURRENT_VERSION=$(echo "$CURRENT_DIR" | sed 's/.*gitlens-//')

# ── 5. 检查远程状态 ─────────────────────────────────────────────────────────
REMOTE_CHECK=$(ssh "$REMOTE_HOST" "[ -d $REMOTE_VSCODE_DIR/eamodio.gitlens-$LATEST_VERSION ] && echo 'yes' || echo 'no'" 2>/dev/null || echo "no")

# ── 6. 判断是否需要更新 ─────────────────────────────────────────────────────
if [ "${CURRENT_VERSION:-}" == "$LATEST_VERSION" ] && [ "$REMOTE_CHECK" == "yes" ]; then
    report "$LATEST_VERSION" "已是最新" "无"
    exit 0
fi

# ── 7. 下载 VSIX ─────────────────────────────────────────────────────────────
TMP_FILE="/tmp/$FILE_NAME"
trap 'rm -f "$TMP_FILE"' EXIT

if ! curl -fL -s "$DOWNLOAD_URL" -o "$TMP_FILE"; then
    report "$LATEST_VERSION" "更新失败" "下载失败: $DOWNLOAD_URL"
    exit 1
fi

# ── 8. 本地安装（IDE CLI 自动维护 extensions.json）───────────────────────────
if ! /usr/local/bin/code --install-extension "$TMP_FILE" --force; then
    report "$LATEST_VERSION" "更新失败" "VS Code 本地安装失败"
    exit 1
fi

# ── 9. 同步到远程 ────────────────────────────────────────────────────────────
sync_to_remote() {
    local LOCAL_SRC=$1
    local REMOTE_DEST=$2
    local VERSION_DIR="eamodio.gitlens-$LATEST_VERSION"
    local LOCAL_VERSION_DIR="$LOCAL_SRC/$VERSION_DIR"

    if [ ! -d "$LOCAL_VERSION_DIR" ]; then
        report "$LATEST_VERSION" "更新失败" "本地扩展目录不存在，无法同步: $LOCAL_VERSION_DIR"
        exit 1
    fi

    # 删除远程同名版本目录并确保目标目录存在
    ssh "$REMOTE_HOST" "rm -rf $REMOTE_DEST/$VERSION_DIR && mkdir -p $REMOTE_DEST"

    # 递归拷贝
    scp -r "$LOCAL_VERSION_DIR" "$REMOTE_HOST:$REMOTE_DEST/"

    # 更新远程 extensions.json 中 GitLens 项
    local JSON_PATH="$REMOTE_DEST/extensions.json"
    local NEW_PATH="$REMOTE_DEST/$VERSION_DIR"
    ssh "$REMOTE_HOST" "jq 'map(if .identifier.id == \"eamodio.gitlens\" then .version = \"$LATEST_VERSION\" | .location.path = \"$NEW_PATH\" | .relativeLocation = \"$VERSION_DIR\" else . end)' $JSON_PATH > $JSON_PATH.tmp && mv $JSON_PATH.tmp $JSON_PATH"
}

sync_to_remote "$LOCAL_VSCODE_DIR" "$REMOTE_VSCODE_DIR"

# ── 10. 清理旧版本（本地 + 远程 2 个目录）───────────────────────────────────
find "$LOCAL_VSCODE_DIR" -maxdepth 1 -name "eamodio.gitlens-*" ! -name "eamodio.gitlens-$LATEST_VERSION" -exec rm -rf {} + || true
ssh "$REMOTE_HOST" "find $REMOTE_VSCODE_DIR -maxdepth 1 -name 'eamodio.gitlens-*' ! -name 'eamodio.gitlens-$LATEST_VERSION' -exec rm -rf {} +" || true

report "$LATEST_VERSION" "已更新至新版本" "已同步 2 个环境 (VS Code 本地 + 远程)"
