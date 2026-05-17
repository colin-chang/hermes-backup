#!/bin/bash
# =============================================================================
# Hermes Agent 每周清理脚本
# =============================================================================
# 功能：安全清理 Hermes Agent 产生的临时文件、缓存、旧日志等
# 频率：每周执行一次（建议周日凌晨）
# 安全：仅删除可自动重建的临时数据，绝不触碰核心数据
# =============================================================================

set -euo pipefail

# ── 配置 ──────────────────────────────────────────────────────────────────────
HERMES_HOME="$HOME/.hermes"
CHROME_DEBUG_PROFILE="$HOME/.chrome-debug-profile"
LOG_DIR="$HERMES_HOME/logs"
SESSIONS_DIR="$HERMES_HOME/sessions"
WEBUI_SESSIONS_DIR="$HERMES_HOME/webui/sessions"
CACHE_DIR="$HERMES_HOME/cache"
CRON_OUTPUT_DIR="$HERMES_HOME/cron/output"
BACKUPS_DIR="$HERMES_HOME/backups"
SNAPSHOTS_DIR="$HERMES_HOME/state-snapshots"

# 保留天数（统一 3 天）
DAYS_LOGS=3          # 日志保留 3 天
DAYS_SCREENSHOTS=3   # 截图/剪贴板图片保留 3 天
DAYS_SESSIONS=3      # CLI 会话保留 3 天
DAYS_WEBUI_RUN=3     # WebUI 运行日志保留 3 天
DAYS_REQUEST_DUMP=3  # 请求转储保留 3 天
DAYS_BACKUPS=3       # 更新备份保留 3 天
DAYS_SNAPSHOTS=3     # 状态快照保留 3 天
DAYS_CRON_OUTPUT=3   # 定时任务输出保留 3 天
DAYS_ATTACHMENTS=3   # 上传附件保留 3 天

# ── 日志函数 ──────────────────────────────────────────────────────────────────
LOG_FILE="$LOG_DIR/cleanup.log"
mkdir -p "$LOG_DIR"

log() {
    local level="$1"
    shift
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $*" | tee -a "$LOG_FILE"
}

# ── 安全检查：核心目录保护 ────────────────────────────────────────────────────
PROTECTED_PATHS=(
    "$HERMES_HOME/config.yaml"
    "$HERMES_HOME/.env"
    "$HERMES_HOME/auth.json"
    "$HERMES_HOME/SOUL.md"
    "$HERMES_HOME/state.db"
    "$HERMES_HOME/kanban.db"
    "$HERMES_HOME/memories"
    "$HERMES_HOME/skills"
    "$HERMES_HOME/bin"
    "$HERMES_HOME/scripts"
)

for protected in "${PROTECTED_PATHS[@]}"; do
    if [ ! -e "$protected" ]; then
        log "WARN" "核心文件/目录缺失: $protected — 可能配置异常，中止清理"
        exit 1
    fi
done

# ── 统计回收空间 ──────────────────────────────────────────────────────────────
freed_bytes=0

add_freed() {
    local path="$1"
    if [ -e "$path" ]; then
        local size
        size=$(du -sk "$path" 2>/dev/null | cut -f1)
        freed_bytes=$((freed_bytes + size * 1024))
    fi
}

format_size() {
    local bytes=$1
    if [ "$bytes" -ge 1073741824 ]; then
        echo "$(echo "scale=1; $bytes / 1073741824" | bc) GB"
    elif [ "$bytes" -ge 1048576 ]; then
        echo "$(echo "scale=1; $bytes / 1048576" | bc) MB"
    elif [ "$bytes" -ge 1024 ]; then
        echo "$(echo "scale=1; $bytes / 1024" | bc) KB"
    else
        echo "$bytes B"
    fi
}

# ── 开始清理 ──────────────────────────────────────────────────────────────────
log "INFO" "========== Hermes 每周清理开始 =========="

# ── 1. Chrome 调试配置文件缓存 ────────────────────────────────────────────────
#    这是最大的空间消费者（当前约 9.2 GB）
#    安全条件：Chrome 调试进程未运行时才可删除
log "INFO" "[1/9] 清理 Chrome 调试配置文件缓存..."

if [ -d "$CHROME_DEBUG_PROFILE" ]; then
    if ! pgrep -f "remote-debugging-port" > /dev/null 2>&1; then
        # 仅删除缓存子目录，保留配置文件（Preferences 等）
        # 这样下次启动浏览器时不需要重新配置，但缓存会被清理
        for cache_subdir in \
            "Default/Service Worker/CacheStorage" \
            "Default/IndexedDB" \
            "Default/Cache" \
            "Default/Code Cache" \
            "Default/GPUCache" \
            "Default/Session Storage" \
            "Default/File System" \
            "Default/Local Storage/leveldb" \
            "ShaderCache" \
            "GrShaderCache" \
            "BrowserMetrics-spare.pma" \
            "Safe Browsing"; do
            target="$CHROME_DEBUG_PROFILE/$cache_subdir"
            if [ -e "$target" ]; then
                add_freed "$target"
                rm -rf "$target"
            fi
        done
        log "INFO" "  ✅ Chrome 缓存已清理（配置文件保留）"
    else
        log "WARN" "  ⏭️ Chrome 调试进程正在运行，跳过清理"
    fi
else
    log "INFO" "  ℹ️ Chrome 调试配置文件目录不存在，跳过"
fi

# ── 2. Python 字节码缓存 ────────────────────────────────────────────────────
log "INFO" "[2/9] 清理 Python 字节码缓存..."

pycache_count=0
while IFS= read -r -d '' dir; do
    add_freed "$dir"
    rm -rf "$dir"
    pycache_count=$((pycache_count + 1))
done < <(find "$HERMES_HOME" -type d -name "__pycache__" -print0 2>/dev/null)

while IFS= read -r -d '' dir; do
    add_freed "$dir"
    rm -rf "$dir"
done < <(find "$HERMES_HOME" -type d -name ".pytest_cache" -print0 2>/dev/null)

log "INFO" "  ✅ 清理了 $pycache_count 个 __pycache__ 目录"

# ── 3. 日志轮转 ──────────────────────────────────────────────────────────────
log "INFO" "[3/9] 日志轮转（保留 ${DAYS_LOGS} 天）..."

# 清理旧日志文件
if [ -d "$LOG_DIR" ]; then
    while IFS= read -r -d '' file; do
        add_freed "$file"
        rm -f "$file"
    done < <(find "$LOG_DIR" -name "*.log" -mtime +"$DAYS_LOGS" -print0 2>/dev/null)
fi

# 截断超大日志文件（> 50MB）为最近部分
MAX_LOG_SIZE=$((50 * 1024 * 1024))  # 50MB
for log_file in "$LOG_DIR"/*.log "$HERMES_HOME/webui.log"; do
    if [ -f "$log_file" ]; then
        file_size=$(stat -f%z "$log_file" 2>/dev/null || echo 0)
        if [ "$file_size" -gt "$MAX_LOG_SIZE" ]; then
            # 保留最后 1000 行
            tmp_file="${log_file}.tmp"
            tail -1000 "$log_file" > "$tmp_file"
            mv "$tmp_file" "$log_file"
            log "INFO" "  ✂️ 截断 $(basename "$log_file") ($(( file_size / 1024 / 1024 )) MB → 保留最近 1000 行)"
        fi
    fi
done

# 清理 /tmp 下的 Chrome 临时日志
rm -f /tmp/chrome_*.log 2>/dev/null || true

log "INFO" "  ✅ 日志轮转完成"

# ── 4. 截图和媒体缓存 ────────────────────────────────────────────────────────
log "INFO" "[4/9] 清理截图和媒体缓存..."

for cache_type in "screenshots" "documents"; do
    target="$CACHE_DIR/$cache_type"
    if [ -d "$target" ]; then
        while IFS= read -r -d '' file; do
            add_freed "$file"
            rm -f "$file"
        done < <(find "$target" -type f -mtime +"$DAYS_SCREENSHOTS" -print0 2>/dev/null)
    fi
done

# 音频和图片缓存（全部清理，均为临时性）
for cache_dir in \
    "$HERMES_HOME/audio_cache" \
    "$HERMES_HOME/image_cache" \
    "$HERMES_HOME/images"; do
    if [ -d "$cache_dir" ]; then
        while IFS= read -r -d '' file; do
            add_freed "$file"
            rm -f "$file"
        done < <(find "$cache_dir" -type f -mtime +"$DAYS_SCREENSHOTS" -print0 2>/dev/null)
    fi
done

# 模型目录缓存（自动重建）
for cache_file in \
    "$HERMES_HOME/models_dev_cache.json" \
    "$HERMES_HOME/ollama_cloud_models_cache.json" \
    "$CACHE_DIR/model_catalog.json"; do
    if [ -f "$cache_file" ]; then
        add_freed "$cache_file"
        rm -f "$cache_file"
    fi
done

log "INFO" "  ✅ 缓存清理完成"

# ── 5. 旧会话和请求转储 ──────────────────────────────────────────────────────
log "INFO" "[5/9] 清理旧会话和请求转储..."

# 请求转储（纯调试用途，7 天后可删）
if [ -d "$SESSIONS_DIR" ]; then
    while IFS= read -r -d '' file; do
        add_freed "$file"
        rm -f "$file"
    done < <(find "$SESSIONS_DIR" -name "request_dump_*.json" -mtime +"$DAYS_REQUEST_DUMP" -print0 2>/dev/null)

    # 旧 CLI 会话（30 天后可删）
    while IFS= read -r -d '' file; do
        add_freed "$file"
        rm -f "$file"
    done < <(find "$SESSIONS_DIR" -name "session_*.json" -mtime +"$DAYS_SESSIONS" -print0 2>/dev/null)
fi

# WebUI 运行日志和轮次日志
if [ -d "$WEBUI_SESSIONS_DIR" ]; then
    for journal_dir in "_run_journal" "_turn_journal"; do
        target="$WEBUI_SESSIONS_DIR/$journal_dir"
        if [ -d "$target" ]; then
            while IFS= read -r -d '' file; do
                add_freed "$file"
                rm -f "$file"
            done < <(find "$target" -type f -mtime +"$DAYS_WEBUI_RUN" -print0 2>/dev/null)
        fi
    done

    # 旧 WebUI 会话
    while IFS= read -r -d '' file; do
        # 不删除 _index.json 和活跃会话
        if [[ "$(basename "$file")" != "_index.json" ]]; then
            add_freed "$file"
            rm -f "$file"
        fi
    done < <(find "$WEBUI_SESSIONS_DIR" -maxdepth 1 -name "*.json" -mtime +"$DAYS_SESSIONS" -print0 2>/dev/null)
fi

# 上传附件
if [ -d "$HERMES_HOME/webui/attachments" ]; then
    while IFS= read -r -d '' file; do
        add_freed "$file"
        rm -f "$file"
    done < <(find "$HERMES_HOME/webui/attachments" -type f -mtime +"$DAYS_ATTACHMENTS" -print0 2>/dev/null)
fi

log "INFO" "  ✅ 旧会话清理完成"

# ── 6. 更新备份和状态快照 ─────────────────────────────────────────────────────
log "INFO" "[6/9] 清理旧备份和快照..."

if [ -d "$BACKUPS_DIR" ]; then
    while IFS= read -r -d '' file; do
        add_freed "$file"
        rm -f "$file"
    done < <(find "$BACKUPS_DIR" -name "*.zip" -mtime +"$DAYS_BACKUPS" -print0 2>/dev/null)
fi

if [ -d "$SNAPSHOTS_DIR" ]; then
    while IFS= read -r -d '' dir; do
        add_freed "$dir"
        rm -rf "$dir"
    done < <(find "$SNAPSHOTS_DIR" -maxdepth 1 -type d -mtime +"$DAYS_SNAPSHOTS" -print0 2>/dev/null)
fi

log "INFO" "  ✅ 备份/快照清理完成"

# ── 7. 定时任务旧输出 ────────────────────────────────────────────────────────
log "INFO" "[7/9] 清理旧定时任务输出..."

if [ -d "$CRON_OUTPUT_DIR" ]; then
    while IFS= read -r -d '' file; do
        add_freed "$file"
        rm -f "$file"
    done < <(find "$CRON_OUTPUT_DIR" -type f -mtime +"$DAYS_CRON_OUTPUT" -print0 2>/dev/null)
fi

log "INFO" "  ✅ 定时任务输出清理完成"

# ── 8. 失效的锁文件和 PID 文件 ───────────────────────────────────────────────
log "INFO" "[8/9] 清理失效锁文件和 PID 文件..."

for lockfile in \
    "$HERMES_HOME/gateway.lock" \
    "$HERMES_HOME/webui.pid" \
    "$HERMES_HOME/auth.lock" \
    "$HERMES_HOME/processes.json"; do
    if [ -f "$lockfile" ]; then
        # 检查对应进程是否还在运行
        case "$(basename "$lockfile")" in
            gateway.lock|gateway.pid)
                if ! pgrep -f "hermes.*gateway" > /dev/null 2>&1; then
                    rm -f "$lockfile"
                    log "INFO" "  🧹 清理失效锁文件: $(basename "$lockfile")"
                fi
                ;;
            webui.pid)
                if ! pgrep -f "hermes.*webui" > /dev/null 2>&1; then
                    rm -f "$lockfile"
                    log "INFO" "  🧹 清理失效 PID 文件: $(basename "$lockfile")"
                fi
                ;;
            auth.lock|processes.json)
                # 这些文件很小，只在无活跃进程时清理
                if ! pgrep -f "hermes" > /dev/null 2>&1; then
                    rm -f "$lockfile"
                    log "INFO" "  🧹 清理失效文件: $(basename "$lockfile")"
                fi
                ;;
        esac
    fi
done

log "INFO" "  ✅ 锁文件清理完成"

# ── 9. SQLite 数据库维护（可选，仅 VACUUM state.db） ──────────────────────────
log "INFO" "[9/9] SQLite 数据库维护..."

# 注意：不删除数据库，仅优化空间
# 只在 Hermes 未运行时执行 VACUUM
if [ -f "$HERMES_HOME/state.db" ]; then
    if ! pgrep -f "hermes" > /dev/null 2>&1; then
        # Hermes 未运行，安全执行 VACUUM
        db_size_before=$(stat -f%z "$HERMES_HOME/state.db" 2>/dev/null || echo 0)
        sqlite3 "$HERMES_HOME/state.db" "VACUUM;" 2>/dev/null || {
            log "WARN" "  ⏭️ state.db VACUUM 失败（可能被锁定），跳过"
        }
        db_size_after=$(stat -f%z "$HERMES_HOME/state.db" 2>/dev/null || echo 0)
        if [ "$db_size_before" -gt "$db_size_after" ]; then
            saved=$((db_size_before - db_size_after))
            log "INFO" "  ✅ state.db VACUUM 回收 $(format_size "$saved")"
        fi
    else
        log "INFO" "  ℹ️ Hermes 正在运行，跳过 VACUUM"
    fi
fi

# ── 清理完成 ──────────────────────────────────────────────────────────────────
log "INFO" "========== 清理完成！总回收空间: $(format_size "$freed_bytes") =========="

# 清理脚本自身日志（保留 90 天）
find "$LOG_DIR" -name "cleanup.log" -size +1M -exec sh -c 'tail -500 "$1" > "$1.tmp" && mv "$1.tmp" "$1"' _ {} \;

exit 0
