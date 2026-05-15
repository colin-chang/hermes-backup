#!/bin/bash
#
# update-gitlens.sh — GitLens Rebuild 版本自动更新与多端同步脚本 (V12)
#
# 用途：
#   自动检测并安装 Rebuild-gitlens (第三方 GitLens 重建版) 的最新版本，
#   实现本地 VS Code / Antigravity 双 IDE 安装，并通过 SCP 同步到远程服务器，
#   最后清理所有环境中旧版本残留。
#
# 触发方式：
#   由 OpenClaw Cron 定时任务 "Update GitLens (Smart Report)" 每日 02:00
#   (Asia/Shanghai) 触发，执行结果通过 Discord #任务通知 频道播报。
#
# 执行流程：
#   1. 从 GitHub Tags 页面抓取最新版本号（绕过 API rate limit）
#   2. 版本合法性校验（semver 格式 + 非空非 null）
#   3. 自动探测两种 VSIX 命名格式（纯版本号 vs 带 v 前缀）
#   4. 比对本地已安装版本 + 远程服务器状态，若均最新则跳过
#   5. 下载 VSIX 并本地安装到 VS Code 和 Antigravity
#   6. SCP 同步扩展目录到远程服务器 (orb) 的 4 个目标路径：
#      - 本地: ~/.antigravity/extensions + ~/.vscode/extensions
#      - 远程: ~/.antigravity-server/extensions + ~/.vscode-server/extensions
#   7. 用 jq 更新远程 extensions.json 中的 GitLens 版本和路径
#   8. 清理本地+远程共 4 个目录中的旧版本扩展
#
# 关键设计：
#   - set -euo pipefail 严格错误处理
#   - trap 确保临时文件清理
#   - url_exists 探测含超时和重定向限制，防止挂起
#   - 清理步骤加 || true 容错，避免权限问题导致整体失败
#
# 依赖：
#   curl, ssh, scp, jq, find, /usr/local/bin/code, $ANTIGRAVITY_BIN
#   SSH 免密登录远程主机 "orb"
#
# 相关配置：
#   openclaw.json → cron/jobs.json (id: 0248c552-...)
#

# 自动更新 GitLens 脚本 - 本地同步+双端清理+自愈版 (V12)

set -euo pipefail

# 目录定义
LOCAL_ANTIGRAVITY_DIR="$HOME/.antigravity/extensions"
LOCAL_VSCODE_DIR="$HOME/.vscode/extensions"
REMOTE_HOST="orb"
REMOTE_ANTIGRAVITY_DIR="/home/colin/.antigravity-server/extensions"
REMOTE_VSCODE_DIR="/home/colin/.vscode-server/extensions"
# 修复：统一使用 $HOME，避免硬编码路径
ANTIGRAVITY_BIN="$HOME/.antigravity/antigravity/bin/antigravity"

TAGS_URL="https://github.com/AliverAnme/Rebuild-gitlens/tags"
REPO_DOWNLOAD_BASE="https://github.com/AliverAnme/Rebuild-gitlens/releases/download"

log_error() {
    echo "[ERROR] $*" >&2
}

is_valid_version() {
    local v="$1"
    # 非空且非 null
    [ -n "$v" ] || return 1
    [ "$v" != "null" ] || return 1
    # 版本格式：1.2.3 / v1.2.3 / 1.2.3-beta.1 / v1.2.3-rc1 等
    echo "$v" | grep -Eq '^v?[0-9]+(\.[0-9]+){1,3}([.-][0-9A-Za-z._-]+)?$'
}

# HEAD 检测 URL 是否存在；修复：加上超时和重定向次数限制
url_exists() {
    local url="$1"
    curl -fsIL --max-time 15 --max-redirs 5 "$url" >/dev/null 2>&1
}

# 1) 从 tags 页面获取最新版本（避免 GitHub API rate limit）
RAW_LATEST_TAG=$(
    curl -fsSL "$TAGS_URL" \
    | sed -n 's#.*href="/AliverAnme/Rebuild-gitlens/releases/tag/\([^"]*\)".*#\1#p' \
    | head -n 1 \
    | tr -d '[:space:]'
)

# 2) 版本合法性检查：不合法则中止后续执行
if ! is_valid_version "${RAW_LATEST_TAG:-}"; then
    log_error "从 tags 页面获取到非法 LATEST_VERSION: '${RAW_LATEST_TAG:-<empty>}'，已中止后续执行。"
    exit 1
fi

# 保留两种形式
LATEST_VERSION="${RAW_LATEST_TAG#v}"   # 去掉前缀 v（用于目录名）
TAG_WITH_V="$RAW_LATEST_TAG"           # 保留原始 tag（用于 release 路径）

# 3) V12：自动探测两种 VSIX 命名
# 优先：gitlens-<纯版本>.vsix
# 备选：gitlens-<原tag>.vsix（仅在两者不同时才额外探测）
FILE_NAME_A="gitlens-$LATEST_VERSION.vsix"
FILE_NAME_B="gitlens-$TAG_WITH_V.vsix"

DOWNLOAD_URL_A="$REPO_DOWNLOAD_BASE/$TAG_WITH_V/$FILE_NAME_A"
DOWNLOAD_URL_B="$REPO_DOWNLOAD_BASE/$TAG_WITH_V/$FILE_NAME_B"

if url_exists "$DOWNLOAD_URL_A"; then
    FILE_NAME="$FILE_NAME_A"
    DOWNLOAD_URL="$DOWNLOAD_URL_A"
# 修复：仅在两个文件名不同时才探测 B，避免对同一 URL 重复请求
elif [ "$FILE_NAME_A" != "$FILE_NAME_B" ] && url_exists "$DOWNLOAD_URL_B"; then
    FILE_NAME="$FILE_NAME_B"
    DOWNLOAD_URL="$DOWNLOAD_URL_B"
else
    log_error "未找到可下载的 VSIX。尝试过：$DOWNLOAD_URL_A${FILE_NAME_A:+ 和 $DOWNLOAD_URL_B}"
    exit 1
fi

# 4) 检查本地安装情况 (基准)
CURRENT_DIR=$(find "$LOCAL_ANTIGRAVITY_DIR" -maxdepth 1 -name "eamodio.gitlens-*" -type d 2>/dev/null | sort | tail -n 1 || true)
CURRENT_VERSION=$(echo "$CURRENT_DIR" | sed 's/.*gitlens-//')

# 5) 检查远程状态
REMOTE_CHECK=$(ssh "$REMOTE_HOST" "[ -d $REMOTE_ANTIGRAVITY_DIR/eamodio.gitlens-$LATEST_VERSION ] && [ -d $REMOTE_VSCODE_DIR/eamodio.gitlens-$LATEST_VERSION ] && echo 'yes' || echo 'no'")

if [ "${CURRENT_VERSION:-}" == "$LATEST_VERSION" ] && [ "$REMOTE_CHECK" == "yes" ]; then
    echo "GitLens 已是最新版本 ($LATEST_VERSION)，无需更新。"
    exit 0
fi

echo "开始执行 GitLens 全量更新 (V12)..."
echo "使用版本：$LATEST_VERSION"
echo "下载地址：$DOWNLOAD_URL"

# 修复：用 trap 确保临时文件在任何退出情况下都能被清理
TMP_FILE="/tmp/$FILE_NAME"
trap 'rm -f "$TMP_FILE"' EXIT

# 6) 本地安装 (由 IDE CLI 自动维护本地 extensions.json)
if ! curl -fL -s "$DOWNLOAD_URL" -o "$TMP_FILE"; then
    log_error "下载失败：$DOWNLOAD_URL"
    exit 1
fi

/usr/local/bin/code --install-extension "$TMP_FILE" --force
"$ANTIGRAVITY_BIN" --install-extension "$TMP_FILE" --force

# 7) 同步函数 (严格 1:1 映射，使用 SCP)
sync_to_remote() {
    local LOCAL_SRC=$1
    local REMOTE_DEST=$2

    local VERSION_DIR="eamodio.gitlens-$LATEST_VERSION"
    local LOCAL_VERSION_DIR="$LOCAL_SRC/$VERSION_DIR"

    # 修复：scp 前检查本地目录是否存在，给出明确错误信息
    if [ ! -d "$LOCAL_VERSION_DIR" ]; then
        log_error "本地扩展目录不存在，无法同步：$LOCAL_VERSION_DIR"
        exit 1
    fi

    # 删除远程同名版本目录并确保目标目录存在
    ssh "$REMOTE_HOST" "rm -rf $REMOTE_DEST/$VERSION_DIR && mkdir -p $REMOTE_DEST"

    # 递归拷贝
    scp -r "$LOCAL_VERSION_DIR" "$REMOTE_HOST:$REMOTE_DEST/"

    # 仅更新远程 extensions.json 中 GitLens 项
    local JSON_PATH="$REMOTE_DEST/extensions.json"
    local NEW_PATH="$REMOTE_DEST/$VERSION_DIR"
    ssh "$REMOTE_HOST" "jq 'map(if .identifier.id == \"eamodio.gitlens\" then .version = \"$LATEST_VERSION\" | .location.path = \"$NEW_PATH\" | .relativeLocation = \"$VERSION_DIR\" else . end)' $JSON_PATH > $JSON_PATH.tmp && mv $JSON_PATH.tmp $JSON_PATH"
}

# 8) 执行 1:1 同步
sync_to_remote "$LOCAL_ANTIGRAVITY_DIR" "$REMOTE_ANTIGRAVITY_DIR"
sync_to_remote "$LOCAL_VSCODE_DIR" "$REMOTE_VSCODE_DIR"

# 9) 全局清理 (本地 + 远程 4个目录)
# 修复：清理步骤加 || true，避免因权限等原因清理失败时中止整个脚本
find "$LOCAL_ANTIGRAVITY_DIR" "$LOCAL_VSCODE_DIR" -maxdepth 1 -name "eamodio.gitlens-*" ! -name "eamodio.gitlens-$LATEST_VERSION" -exec rm -rf {} + || true
ssh "$REMOTE_HOST" "find $REMOTE_ANTIGRAVITY_DIR $REMOTE_VSCODE_DIR -maxdepth 1 -name 'eamodio.gitlens-*' ! -name 'eamodio.gitlens-$LATEST_VERSION' -exec rm -rf {} +" || true

echo "✅ GitLens 更新完成：已同步 4 个环境 ($LATEST_VERSION)。"
