#!/bin/bash
# =============================================================================
# Hermes Agent 每周清理脚本
# =============================================================================
# 清理范围：
#   1. Chrome 调试配置文件缓存（~/.chrome-debug-profile 下子目录）
#   2. Python __pycache__ / .pytest_cache
#   3. 日志轮转（过期删除 + 超大截断 + /tmp/chrome_*.log）
#   4. 截图/媒体/模型缓存（cache/{screenshots,documents}、{audio,image}_cache、
#      images/、models_dev_cache.json、ollama_cloud_models_cache.json）
#   5. 旧会话（sessions/*.jsonl）、请求转储、WebUI 会话/附件
#   6. 旧备份（backups/*.zip）、状态快照
#   7. 定时任务旧输出（cron/output/）
#   8. 失效锁文件/PID 文件（gateway.lock、webui.pid、auth.lock）
#   9. SQLite VACUUM（state.db、kanban.db）
# 保留策略：统一 3 天过期，仅删除可自动重建的临时数据，绝不触碰核心配置
# 日志：详细日志写入 ~/.hermes/logs/cleanup.log，stdout 仅输出摘要报告
# 频率：建议每周日凌晨执行一次
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

# 统一保留天数（需要差异化时再拆分为独立变量）
RETENTION_DAYS=3
MAX_LOG_SIZE=$((50 * 1024 * 1024))  # 50 MB

# ── 日志函数（仅写文件，不输出到 stdout）───────────────────────────────────────
LOG_FILE="$LOG_DIR/cleanup.log"
mkdir -p "$LOG_DIR"

log() {
    local level="$1"; shift
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $*" >> "$LOG_FILE"
}

# ── 摘要追踪变量 ──────────────────────────────────────────────────────────────
freed_bytes=0
pycache_count=0
lock_count=0
vacuum_saved=0
cleaned_items=()    # 实际执行了清理的项目
skipped_items=()    # 跳过的项目及原因

add_freed() {
    local path="$1"
    if [ -e "$path" ]; then
        local size
        size=$(du -sk "$path" 2>/dev/null | cut -f1)
        freed_bytes=$((freed_bytes + size * 1024))
    fi
}

# 纯 bash 格式化，不依赖 bc
format_size() {
    local bytes=$1
    if [ "$bytes" -ge 1073741824 ]; then
        echo "$((bytes / 1073741824)).$(( (bytes % 1073741824) * 10 / 1073741824 )) GB"
    elif [ "$bytes" -ge 1048576 ]; then
        echo "$((bytes / 1048576)).$(( (bytes % 1048576) * 10 / 1048576 )) MB"
    elif [ "$bytes" -ge 1024 ]; then
        echo "$((bytes / 1024)).$(( (bytes % 1024) * 10 / 1024 )) KB"
    else
        echo "$bytes B"
    fi
}

# 通用：按 mtime 清理目录下匹配模式的文件
clean_dir_by_age() {
    local dir="$1" pattern="$2" days="$3"
    if [ -d "$dir" ]; then
        local count=0
        while IFS= read -r -d '' file; do
            add_freed "$file"
            rm -f "$file"
            count=$((count + 1))
        done < <(find "$dir" -name "$pattern" -mtime +"$days" -print0 2>/dev/null)
        return $count
    fi
    return 0
}

# ── 摘要输出函数 ──────────────────────────────────────────────────────────────
report() {
    echo "🧹 Hermes 每周清理报告"
    echo "━━━━━━━━━━━━━━━━━━━━━━"
    echo "📊 总回收空间: $(format_size "$freed_bytes")"
    echo "📋 清理明细:"
    for item in "${cleaned_items[@]}"; do
        echo "   ✅ $item"
    done
    if [ ${#skipped_items[@]} -gt 0 ]; then
        echo "⏭️  跳过:"
        for item in "${skipped_items[@]}"; do
            echo "   ⏭️  $item"
        done
    fi
    echo "━━━━━━━━━━━━━━━━━━━━━━"
    echo "📝 详细日志: $LOG_FILE"
}

# ── 安全检查：核心目录保护 ────────────────────────────────────────────────────
PROTECTED_PATHS=(
    "$HERMES_HOME/config.yaml"
    "$HERMES_HOME/.env"
    "$HERMES_HOME/SOUL.md"
    "$HERMES_HOME/state.db"
    "$HERMES_HOME/memories"
    "$HERMES_HOME/skills"
    "$HERMES_HOME/bin"
    "$HERMES_HOME/scripts"
)

for protected in "${PROTECTED_PATHS[@]}"; do
    if [ ! -e "$protected" ]; then
        log "WARN" "核心文件/目录缺失: $protected — 可能配置异常，中止清理"
        echo "❌ 清理中止：核心文件缺失 ($protected)"
        exit 1
    fi
done

# ── 开始清理 ──────────────────────────────────────────────────────────────────
log "INFO" "========== Hermes 每周清理开始 =========="

# ── 1. Chrome 调试配置文件缓存 ────────────────────────────────────────────────
log "INFO" "[1/9] 清理 Chrome 调试配置文件缓存..."

if [ -d "$CHROME_DEBUG_PROFILE" ]; then
    if ! pgrep -f "remote-debugging-port" > /dev/null 2>&1; then
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
        cleaned_items+=("Chrome 调试缓存")
        log "INFO" "  ✅ Chrome 缓存已清理（配置文件保留）"
    else
        skipped_items+=("Chrome缓存(进程运行中)")
        log "WARN" "  ⏭️ Chrome 调试进程正在运行，跳过清理"
    fi
else
    skipped_items+=("Chrome缓存(目录不存在)")
    log "INFO" "  ℹ️ Chrome 调试配置文件目录不存在，跳过"
fi

# ── 2. Python 字节码缓存 ────────────────────────────────────────────────────
log "INFO" "[2/9] 清理 Python 字节码缓存..."

while IFS= read -r -d '' dir; do
    add_freed "$dir"
    rm -rf "$dir"
    pycache_count=$((pycache_count + 1))
done < <(find "$HERMES_HOME" -type d \( -name "__pycache__" -o -name ".pytest_cache" \) -print0 2>/dev/null)

if [ "$pycache_count" -gt 0 ]; then
    cleaned_items+=("Python 字节码 (${pycache_count} 个目录)")
fi
log "INFO" "  ✅ 清理了 $pycache_count 个缓存目录"

# ── 3. 日志轮转 ──────────────────────────────────────────────────────────────
log "INFO" "[3/9] 日志轮转（保留 ${RETENTION_DAYS} 天）..."

if [ -d "$LOG_DIR" ]; then
    while IFS= read -r -d '' file; do
        add_freed "$file"
        rm -f "$file"
    done < <(find "$LOG_DIR" -name "*.log" -mtime +"$RETENTION_DAYS" -print0 2>/dev/null)
fi

# 超大日志截断
for log_file in "$LOG_DIR"/*.log "$HERMES_HOME/webui.log"; do
    if [ -f "$log_file" ]; then
        file_size=$(stat -f%z "$log_file" 2>/dev/null || echo 0)
        if [ "$file_size" -gt "$MAX_LOG_SIZE" ]; then
            tmp_file="${log_file}.tmp"
            tail -1000 "$log_file" > "$tmp_file"
            mv "$tmp_file" "$log_file"
            log "INFO" "  ✂️ 截断 $(basename "$log_file") ($(( file_size / 1024 / 1024 )) MB → 保留最近 1000 行)"
        fi
    fi
done

rm -f /tmp/chrome_*.log 2>/dev/null
cleaned_items+=("日志轮转")
log "INFO" "  ✅ 日志轮转完成"

# ── 4. 截图和媒体缓存 ────────────────────────────────────────────────────────
log "INFO" "[4/9] 清理截图和媒体缓存..."

# 按过期时间清理的目录
for cache_dir in \
    "$CACHE_DIR/screenshots" \
    "$CACHE_DIR/documents" \
    "$HERMES_HOME/audio_cache" \
    "$HERMES_HOME/image_cache" \
    "$HERMES_HOME/images"; do
    if [ -d "$cache_dir" ]; then
        while IFS= read -r -d '' file; do
            add_freed "$file"
            rm -f "$file"
        done < <(find "$cache_dir" -type f -mtime +"$RETENTION_DAYS" -print0 2>/dev/null)
    fi
done

# 模型缓存文件：无条件删除（自动重建，不受 mtime 限制）
for cache_file in \
    "$HERMES_HOME/models_dev_cache.json" \
    "$HERMES_HOME/ollama_cloud_models_cache.json" \
    "$CACHE_DIR/model_catalog.json"; do
    if [ -f "$cache_file" ]; then
        add_freed "$cache_file"
        rm -f "$cache_file"
    fi
done

cleaned_items+=("截图/媒体/模型缓存")
log "INFO" "  ✅ 缓存清理完成"

# ── 5. 旧会话和请求转储 ──────────────────────────────────────────────────────
log "INFO" "[5/9] 清理旧会话和请求转储..."

if [ -d "$SESSIONS_DIR" ]; then
    # 实际文件格式为 *.jsonl（非 session_*.json）
    while IFS= read -r -d '' file; do
        add_freed "$file"
        rm -f "$file"
    done < <(find "$SESSIONS_DIR" -name "*.jsonl" -mtime +"$RETENTION_DAYS" -print0 2>/dev/null)

    while IFS= read -r -d '' file; do
        add_freed "$file"
        rm -f "$file"
    done < <(find "$SESSIONS_DIR" -name "request_dump_*.json" -mtime +"$RETENTION_DAYS" -print0 2>/dev/null)
fi

if [ -d "$WEBUI_SESSIONS_DIR" ]; then
    for journal_dir in "_run_journal" "_turn_journal"; do
        target="$WEBUI_SESSIONS_DIR/$journal_dir"
        if [ -d "$target" ]; then
            while IFS= read -r -d '' file; do
                add_freed "$file"
                rm -f "$file"
            done < <(find "$target" -type f -mtime +"$RETENTION_DAYS" -print0 2>/dev/null)
        fi
    done

    # WebUI 会话 JSON，保留 _index.json
    while IFS= read -r -d '' file; do
        if [[ "$(basename "$file")" != "_index.json" ]]; then
            add_freed "$file"
            rm -f "$file"
        fi
    done < <(find "$WEBUI_SESSIONS_DIR" -maxdepth 1 -name "*.json" -mtime +"$RETENTION_DAYS" -print0 2>/dev/null)
fi

if [ -d "$HERMES_HOME/webui/attachments" ]; then
    while IFS= read -r -d '' file; do
        add_freed "$file"
        rm -f "$file"
    done < <(find "$HERMES_HOME/webui/attachments" -type f -mtime +"$RETENTION_DAYS" -print0 2>/dev/null)
fi

cleaned_items+=("旧会话/请求转储")
log "INFO" "  ✅ 旧会话清理完成"

# ── 6. 旧备份和状态快照 ─────────────────────────────────────────────────────
log "INFO" "[6/9] 清理旧备份和快照..."

if [ -d "$BACKUPS_DIR" ]; then
    while IFS= read -r -d '' file; do
        add_freed "$file"
        rm -f "$file"
    done < <(find "$BACKUPS_DIR" -name "*.zip" -mtime +"$RETENTION_DAYS" -print0 2>/dev/null)
fi

if [ -d "$SNAPSHOTS_DIR" ]; then
    while IFS= read -r -d '' dir; do
        add_freed "$dir"
        rm -rf "$dir"
    done < <(find "$SNAPSHOTS_DIR" -maxdepth 1 -type d -mtime +"$RETENTION_DAYS" -print0 2>/dev/null)
fi

cleaned_items+=("旧备份/快照")
log "INFO" "  ✅ 备份/快照清理完成"

# ── 7. 定时任务旧输出 ────────────────────────────────────────────────────────
log "INFO" "[7/9] 清理旧定时任务输出..."

if [ -d "$CRON_OUTPUT_DIR" ]; then
    while IFS= read -r -d '' file; do
        add_freed "$file"
        rm -f "$file"
    done < <(find "$CRON_OUTPUT_DIR" -type f -mtime +"$RETENTION_DAYS" -print0 2>/dev/null)
fi

cleaned_items+=("定时任务输出")
log "INFO" "  ✅ 定时任务输出清理完成"

# ── 8. 失效的锁文件和 PID 文件 ───────────────────────────────────────────────
log "INFO" "[8/9] 清理失效锁文件和 PID 文件..."

# 检查指定锁文件：仅当对应进程不在运行时才清理
declare -A lock_process_map=(
    ["gateway.lock"]="hermes.*gateway"
    ["webui.pid"]="hermes.*webui"
    ["auth.lock"]="hermes.*gateway"
    ["processes.json"]="hermes.*gateway"
)

for lockfile in \
    "$HERMES_HOME/gateway.lock" \
    "$HERMES_HOME/webui.pid" \
    "$HERMES_HOME/auth.lock" \
    "$HERMES_HOME/processes.json"; do
    if [ -f "$lockfile" ]; then
        basename_lock=$(basename "$lockfile")
        pattern="${lock_process_map[$basename_lock]:-hermes}"
        if ! pgrep -f "$pattern" > /dev/null 2>&1; then
            rm -f "$lockfile"
            lock_count=$((lock_count + 1))
            log "INFO" "  🧹 清理失效文件: $basename_lock (进程 $pattern 未运行)"
        else
            log "INFO" "  ℹ️ 保留 $basename_lock (进程 $pattern 仍在运行)"
        fi
    fi
done

if [ "$lock_count" -gt 0 ]; then
    cleaned_items+=("失效锁文件 (${lock_count} 个)")
else
    skipped_items+=("锁文件(无需清理)")
fi
log "INFO" "  ✅ 锁文件清理完成"

# ── 9. SQLite 数据库维护 ─────────────────────────────────────────────────────
log "INFO" "[9/9] SQLite 数据库维护..."

# VACUUM 仅需确认 gateway 不在运行（它独占 state.db/kanban.db）
if ! pgrep -f "hermes.*gateway" > /dev/null 2>&1; then
    for db_file in "$HERMES_HOME/state.db" "$HERMES_HOME/kanban.db"; do
        if [ -f "$db_file" ]; then
            db_size_before=$(stat -f%z "$db_file" 2>/dev/null || echo 0)
            if sqlite3 "$db_file" "VACUUM;" 2>/dev/null; then
                db_size_after=$(stat -f%z "$db_file" 2>/dev/null || echo 0)
                local_saved=$((db_size_before - db_size_after))
                vacuum_saved=$((vacuum_saved + local_saved))
                if [ "$local_saved" -gt 0 ]; then
                    log "INFO" "  ✅ $(basename "$db_file") VACUUM 回收 $(format_size "$local_saved")"
                else
                    log "INFO" "  ℹ️  $(basename "$db_file") VACUUM 无碎片回收"
                fi
            else
                log "WARN" "  ⏭️ $(basename "$db_file") VACUUM 失败（可能被锁定），跳过"
            fi
        fi
    done
else
    skipped_items+=("SQLite VACUUM(Gateway运行中)")
    log "INFO" "  ℹ️ Gateway 正在运行，跳过 VACUUM"
fi

if [ "$vacuum_saved" -gt 0 ]; then
    cleaned_items+=("SQLite VACUUM (回收 $(format_size "$vacuum_saved"))")
fi

# ── 输出摘要报告 ──────────────────────────────────────────────────────────────
log "INFO" "========== 清理完成！总回收: $(format_size "$freed_bytes") =========="
report

# ── 清理脚本自身日志（>1MB 截断） ──────────────────────────────────────────────
find "$LOG_DIR" -name "cleanup.log" -size +1M -exec sh -c 'tail -500 "$1" > "$1.tmp" && mv "$1.tmp" "$1"' _ {} \;

exit 0
