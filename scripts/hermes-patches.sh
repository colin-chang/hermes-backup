#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════
# Hermes Patches — 手动修复脚本
# ═══════════════════════════════════════════════════════════════════════════
#
# 背景：
#   当 hermes-agent 上游版本更新后，本地修改会被覆盖，
#   此脚本用于一键还原以下 patch。
#
#   1.  hermes_cli/providers.py           — is_aggregator() 识别 custom:<name>
#   2.  hermes_cli/doctor.py              — 消除 vendor-prefix 假阳性警告
#   3.  hermes_cli/model_switch.py        — models: 白名单优先于线上拉取（2 处）
#   4.  gateway/config.py                 — gateway_restart_notification bridge 修复（2 处）
#   5.  cron/jobs.py                      — json.dump ensure_ascii=False（中文 \\uXXXX）
#   6.  gateway/platforms/mattermost.py   — _resolve_root_id()（方法定义 + send/_send_url/_send_local）
#   7.  gateway/platforms/mattermost.py   — DM 审批基础设施（4 处：init/callback/connect/disconnect + send_exec_approval）
#   8.  gateway/run.py                    — 审批 user_id（8a）+ 工具进度进 Thread（8b，Mattermost 不依赖 source.thread_id）
#   9.  utils.py                          — yaml.dump allow_unicode=True（中文 \\uXXXX）
#   10. MEDIA 正则收紧                    — 修复 Mattermost 频道 file not found 噪声（3 处）
#      a. gateway/run.py                  — 工具结果扫描：要求路径格式
#      b. gateway/platforms/base.py       — extract_media() 去掉 \\S+ 兜底
#      c. gateway/platforms/mattermost.py — 文件不存在时静默跳过
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
    "hermes_cli/model_switch.py|model_switch.py (Section 4)|if not grp\\[\"models\"\\]"
    "gateway/config.py|config.py (bridge loop)|\"gateway_restart_notification\" in platform_cfg"
    "gateway/config.py|config.py (from_dict fallback)|extra.*gateway_restart_notification"
    "cron/jobs.py|jobs.py (ensure_ascii=False)|ensure_ascii=False"
    "gateway/platforms/mattermost.py|mattermost.py (_resolve_root_id)|_resolve_root_id"
    "gateway/platforms/mattermost.py|mattermost.py (DM 审批基础设施)|_start_callback_server"
    "gateway/run.py|run.py (user_id 传入审批)|user_id=source.user_id"
    "gateway/run.py|run.py (progress reply 进 Thread)|or source.platform == Platform.MATTERMOST"
    "utils.py|utils.py (yaml allow_unicode)|allow_unicode=True"
    "gateway/run.py|run.py (MEDIA 工具结果扫描)|_TOOL_MEDIA_RE"
    "gateway/platforms/base.py|base.py (MEDIA 去兜底)|兜底分支"
    "gateway/platforms/mattermost.py|mattermost.py (MEDIA 静默跳过)|local file not found, skipping"
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

    # ── 6. gateway/platforms/mattermost.py — _resolve_root_id ──────────────
    _do_patch "gateway/platforms/mattermost.py" \
        "mattermost.py (_resolve_root_id)" \
        '_resolve_root_id' <<'PYEOF'
import sys
file_path = sys.argv[1]
with open(file_path, 'r') as f:
    content = f.read()

# 6a. 添加 _resolve_root_id 方法（在 send 方法之前插入）
if "_resolve_root_id" not in content:
    resolve_method = '''
    async def _resolve_root_id(self, post_id: str) -> str:
        """Resolve a post_id to the thread root_id for Mattermost.

        Mattermost requires root_id to be the *root* post of a thread.
        If the post is a reply (has its own root_id), we must use that
        root_id instead.  Using a reply's own ID as root_id causes
        "Invalid RootId parameter" errors.
        """
        if not post_id:
            return post_id
        # Check if this post has a root_id (meaning it's a reply)
        data = await self._api_get(f"posts/{post_id}")
        if data and data.get("root_id"):
            return data["root_id"]
        return post_id

'''
    # Insert before the send() method
    marker = "    async def send("
    if marker in content:
        content = content.replace(marker, resolve_method + marker)
        with open(file_path, 'w') as f:
            f.write(content)
        print("APPLIED")
    else:
        print("SKIP")
else:
    print("SKIP")
PYEOF

    # 6b. send() 中使用 _resolve_root_id
    _do_patch "gateway/platforms/mattermost.py" \
        "mattermost.py (send root_id)" \
        'resolved_root = await self._resolve_root_id' <<'PYEOF'
import sys
file_path = sys.argv[1]
with open(file_path, 'r') as f:
    content = f.read()

old = '''            # Thread support: reply_to is the root post ID.
            if reply_to and self._reply_mode == "thread":
                payload["root_id"] = reply_to'''

new = '''            # Thread support: reply_to is the root post ID.
            if reply_to and self._reply_mode == "thread":
                # Ensure root_id points to the thread root, not a reply.
                # Mattermost rejects non-root post IDs as root_id.
                resolved_root = await self._resolve_root_id(reply_to)
                payload["root_id"] = resolved_root'''

if old in content:
    content = content.replace(old, new)
    with open(file_path, 'w') as f:
        f.write(content)
    print("APPLIED")
else:
    print("SKIP")
PYEOF

    # 6c. _send_url_as_file() 中使用 _resolve_root_id
    _do_patch "gateway/platforms/mattermost.py" \
        "mattermost.py (_send_url root_id)" \
        'resolve_root_id\(reply_to\)' <<'PYEOF'
import sys
file_path = sys.argv[1]
with open(file_path, 'r') as f:
    content = f.read()

old = '''        if reply_to and self._reply_mode == "thread":
            payload["root_id"] = reply_to

        data = await self._api_post("posts", payload)
        if not data or "id" not in data:
            return SendResult(success=False, error="Failed to post with file")
        return SendResult(success=True, message_id=data["id"])

    async def _send_local_file('''

new = '''        if reply_to and self._reply_mode == "thread":
            payload["root_id"] = await self._resolve_root_id(reply_to)

        data = await self._api_post("posts", payload)
        if not data or "id" not in data:
            return SendResult(success=False, error="Failed to post with file")
        return SendResult(success=True, message_id=data["id"])

    async def _send_local_file('''

if old in content:
    content = content.replace(old, new)
    with open(file_path, 'w') as f:
        f.write(content)
    print("APPLIED")
else:
    print("SKIP")
PYEOF

    # 6d. _send_local_file() 中使用 _resolve_root_id
    _do_patch "gateway/platforms/mattermost.py" \
        "mattermost.py (_send_local root_id)" \
        'resolve_root_id\(reply_to\)' <<'PYEOF'
import sys
file_path = sys.argv[1]
with open(file_path, 'r') as f:
    content = f.read()

# Find the second occurrence of root_id = reply_to (in _send_local_file)
# which is after _send_url_as_file was already patched
old = '''        if reply_to and self._reply_mode == "thread":
            payload["root_id"] = reply_to

        data = await self._api_post("posts", payload)
        if not data or "id" not in data:
            return SendResult(success=False, error="Failed to post with file")
        return SendResult(success=True, message_id=data["id"])'''

new = '''        if reply_to and self._reply_mode == "thread":
            payload["root_id"] = await self._resolve_root_id(reply_to)

        data = await self._api_post("posts", payload)
        if not data or "id" not in data:
            return SendResult(success=False, error="Failed to post with file")
        return SendResult(success=True, message_id=data["id"])'''

# Replace only the last occurrence (in _send_local_file)
if old in content:
    # Find last occurrence
    last_idx = content.rfind(old)
    if last_idx >= 0:
        content = content[:last_idx] + new + content[last_idx + len(old):]
        with open(file_path, 'w') as f:
            f.write(content)
        print("APPLIED")
    else:
        print("SKIP")
else:
    print("SKIP")
PYEOF

    # ── 7. gateway/platforms/mattermost.py — DM 审批基础设施 ─────────────
    _do_patch "gateway/platforms/mattermost.py" \
        "mattermost.py (DM 审批基础设施)" \
        '_start_callback_server' <<'PYEOF'
import sys
file_path = sys.argv[1]
with open(file_path, 'r') as f:
    content = f.read()

# 7a. __init__ 末尾添加审批基础设施属性
init_marker = '        # Dedup cache (prevent reprocessing)\n        self._dedup = MessageDeduplicator()'
if "_callback_server" not in content and init_marker in content:
    init_patch = '''

        # ── Hermes Patch: DM 审批回调基础设施 ──
        # Callback server: 接收 Mattermost Interactive Message 按钮回调
        self._callback_server = None  # type: ignore
        self._callback_port: int = int(
            os.getenv("MATTERMOST_CALLBACK_PORT", "18065")
        )
        self._callback_bind: str = os.getenv(
            "MATTERMOST_CALLBACK_BIND", "127.0.0.1"
        )
        # 回调 URL（Mattermost 服务端 → callback server）
        self._callback_url: str = os.getenv(
            "MATTERMOST_CALLBACK_URL", ""
        )
        # HMAC secret — 在 Mattermost System Console → Integrations → Secret 设置
        self._callback_secret: str = os.getenv(
            "MATTERMOST_CALLBACK_SECRET", ""
        )
        # DM channel 缓存: user_id → dm_channel_id
        self._dm_cache: Dict[str, str] = {}
        # ── End Patch ──
'''
    content = content.replace(init_marker, init_marker + init_patch)
    with open(file_path, 'w') as f:
        f.write(content)
    print("APPLIED")
else:
    print("SKIP")
PYEOF

    # 7b. 添加 DM 审批方法（在 HTTP helpers 之后、Required overrides 之前）
    _do_patch "gateway/platforms/mattermost.py" \
        "mattermost.py (DM 审批方法)" \
        '_handle_callback' <<'PYEOF'
import sys
file_path = sys.argv[1]
with open(file_path, 'r') as f:
    content = f.read()

if "_handle_callback" not in content:
    dm_methods = '''
    # ------------------------------------------------------------------
    # ── Hermes Patch: DM 审批方法 ──
    # ------------------------------------------------------------------

    def _get_allowed_users(self) -> set:
        """获取 MATTERMOST_ALLOWED_USERS 配置."""
        allowed_str = os.getenv("MATTERMOST_ALLOWED_USERS", "").strip()
        if not allowed_str:
            return set()
        return {u.strip() for u in allowed_str.split(",") if u.strip()}

    async def _get_or_create_dm(self, user_id: str) -> str:
        """获取或创建与指定用户的 DM channel（幂等，带缓存）."""
        if user_id in self._dm_cache:
            return self._dm_cache[user_id]

        payload = [self._bot_user_id, user_id]
        data = await self._api_post("channels/direct", payload)

        dm_id = data.get("id", "")
        if dm_id:
            self._dm_cache[user_id] = dm_id

        return dm_id

    async def _start_callback_server(self) -> None:
        """启动本地 HTTP callback server，接收 Mattermost 按钮回调."""
        import asyncio as _asyncio

        adapter_self = self  # 闭包引用

        async def _handler(
            reader: _asyncio.StreamReader, writer: _asyncio.StreamWriter
        ):
            try:
                request_data = await _asyncio.wait_for(
                    reader.read(65536), timeout=10.0
                )
                if not request_data:
                    writer.close()
                    return

                request_text = request_data.decode("utf-8", errors="replace")
                headers, _, body = request_text.partition("\\r\\n\\r\\n")

                request_line = headers.split("\\r\\n")[0]
                parts = request_line.split(" ", 2)
                if len(parts) < 2:
                    writer.close()
                    return
                method, path = parts[0], parts[1]

                if method != "POST" or path != "/mattermost/callback":
                    response = (
                        b"HTTP/1.1 404 Not Found\\r\\n"
                        b"Content-Length: 0\\r\\n\\r\\n"
                    )
                    writer.write(response)
                    await writer.drain()
                    writer.close()
                    return

                # 提取签名头
                signature = ""
                for line in headers.split("\\r\\n"):
                    if line.lower().startswith("x-mattermost-signature:"):
                        signature = line.split(":", 1)[1].strip()
                        break

                # 校验签名（如果配置了 secret）
                if adapter_self._callback_secret:
                    if not signature or not adapter_self._verify_signature(
                        body.encode("utf-8"), signature
                    ):
                        response = (
                            b"HTTP/1.1 401 Unauthorized\\r\\n"
                            b"Content-Length: 0\\r\\n\\r\\n"
                        )
                        writer.write(response)
                        await writer.drain()
                        writer.close()
                        return

                try:
                    payload = json.loads(body)
                except json.JSONDecodeError:
                    response = (
                        b"HTTP/1.1 400 Bad Request\\r\\n"
                        b"Content-Length: 0\\r\\n\\r\\n"
                    )
                    writer.write(response)
                    await writer.drain()
                    writer.close()
                    return

                logger.info(
                    "Mattermost callback: received POST action=%s user=%s",
                    payload.get("context", {}).get("action", ""),
                    payload.get("user_id", ""),
                )

                result = await adapter_self._handle_callback(payload)

                response_body = json.dumps(result).encode("utf-8")
                response = (
                    f"HTTP/1.1 200 OK\\r\\n"
                    f"Content-Type: application/json\\r\\n"
                    f"Content-Length: {len(response_body)}\\r\\n"
                    f"\\r\\n"
                ).encode("utf-8") + response_body
                writer.write(response)
                await writer.drain()
                writer.close()

            except Exception:
                writer.close()

        server = await _asyncio.start_server(
            _handler,
            host=adapter_self._callback_bind,
            port=adapter_self._callback_port,
        )
        adapter_self._callback_server = server
        logger.info(
            "Mattermost callback server listening on %s:%s",
            adapter_self._callback_bind,
            adapter_self._callback_port,
        )

    async def _stop_callback_server(self) -> None:
        """停止 callback server."""
        if self._callback_server:
            self._callback_server.close()
            await self._callback_server.wait_closed()
            self._callback_server = None
            logger.info("Mattermost callback server stopped")

    def _verify_signature(self, body: bytes, signature: str) -> bool:
        """HMAC-SHA256 校验 Mattermost 回调签名."""
        import hmac as _hmac
        import hashlib as _hashlib

        if not self._callback_secret:
            return True

        expected = _hmac.new(
            self._callback_secret.encode("utf-8"),
            body,
            _hashlib.sha256,
        ).hexdigest()

        return _hmac.compare_digest(expected, signature)

    async def _handle_callback(
        self, payload: Dict[str, Any]
    ) -> Dict[str, Any]:
        """处理 Mattermost Interactive Message 按钮回调."""
        context = payload.get("context", {})
        action = context.get("action", "")
        session_key = context.get("session_key", "")
        post_id = payload.get("post_id", "")

        if not action or not session_key:
            return {"ephemeral_text": "Invalid callback data"}

        # 校验用户权限
        user_id = payload.get("user_id", "")
        allowed_users = self._get_allowed_users()
        if allowed_users and user_id not in allowed_users:
            logger.warning(
                "Mattermost callback: unauthorized user %s for approval",
                user_id,
            )
            return {"ephemeral_text": "Unauthorized"}

        # 映射 action → approval choice
        choice_map = {
            "approve_once": "once",
            "approve_session": "session",
            "approve_always": "always",
            "deny": "deny",
        }
        choice = choice_map.get(action)
        if not choice:
            return {"ephemeral_text": f"Unknown action: {action}"}

        # 调用审批解决
        from tools.approval import resolve_gateway_approval

        count = resolve_gateway_approval(session_key, choice)

        if count == 0:
            return {
                "ephemeral_text": "No pending approval found for this session"
            }

        # 更新 DM 消息（按钮变灰，显示结果）
        label_map = {
            "once": "✅ Approved — Allow Once",
            "session": "✅ Approved — Allow Session",
            "always": "✅ Approved — Always Allow",
            "deny": "❌ Denied",
        }
        if post_id:
            cmd = context.get("command", "")
            cmd_display = f"\\n```\\n{cmd}\\n```" if cmd else ""
            _update_msg = f"{label_map.get(choice, choice)}{cmd_display}"
        else:
            _update_msg = label_map.get(choice, choice)

        logger.info(
            "Mattermost callback: %s → %s (session %s), %d resolved",
            action,
            choice,
            session_key[:40],
            count,
        )

        return {
            "update": {
                "message": _update_msg,
                "props": {},
            },
            "ephemeral_text": "审批完成",
        }

    async def send_exec_approval(
        self,
        chat_id: str,
        command: str,
        session_key: str,
        description: str = "dangerous command",
        metadata: Optional[Dict[str, Any]] = None,
        user_id: Optional[str] = None,
    ) -> SendResult:
        """发送按钮式审批提示到用户 DM.

        Bot API 创建的帖子 integration 字段虽被 API 响应剥离，
        但数据库中完整保留，MM 服务端处理按钮点击时从 DB 读取，
        因此 Bot API + DM 方式可正常触发回调。
        """
        if not user_id:
            return SendResult(
                success=False,
                error="Cannot send DM approval without user_id",
            )

        try:
            # 1. 获取/创建 DM channel
            dm_channel_id = await self._get_or_create_dm(user_id)
            if not dm_channel_id:
                return SendResult(
                    success=False,
                    error="Failed to create DM channel",
                )

            # 2. 构建 callback URL
            callback_url = self._callback_url or (
                f"http://{self._callback_bind}:{self._callback_port}"
                f"/mattermost/callback"
            )

            cmd_preview = (
                command[:3800] + "..." if len(command) > 3800 else command
            )

            # 3. 构建 Interactive Message
            attachment = {
                "fallback": f"⚠️ 危险命令需要审批: {command[:100]}",
                "color": "#ff9900",
                "text": (
                    f"```\\n{cmd_preview}\\n```\\n"
                    f"**Reason:** {description}\\n\\n"
                    f"请点击下方按钮审批或拒绝此操作。"
                ),
                "actions": [
                    {
                        "id": "approveonce",
                        "name": "Allow Once",
                        "type": "button",
                        "style": "primary",
                        "integration": {
                            "url": callback_url,
                            "context": {
                                "action": "approve_once",
                                "session_key": session_key,
                                "command": command,
                            },
                        },
                    },
                    {
                        "id": "approvesession",
                        "name": "Allow Session",
                        "type": "button",
                        "integration": {
                            "url": callback_url,
                            "context": {
                                "action": "approve_session",
                                "session_key": session_key,
                                "command": command,
                            },
                        },
                    },
                    {
                        "id": "approvealways",
                        "name": "Always Allow",
                        "type": "button",
                        "integration": {
                            "url": callback_url,
                            "context": {
                                "action": "approve_always",
                                "session_key": session_key,
                                "command": command,
                            },
                        },
                    },
                    {
                        "id": "deny",
                        "name": "Deny",
                        "type": "button",
                        "style": "danger",
                        "integration": {
                            "url": callback_url,
                            "context": {
                                "action": "deny",
                                "session_key": session_key,
                            },
                        },
                    },
                ],
            }

            # 4. 通过 Bot API 发送到 DM（props.attachments）
            payload = {
                "channel_id": dm_channel_id,
                "message": "⚠️ 危险命令需要审批",
                "props": {"attachments": [attachment]},
            }

            data = await self._api_post("posts", payload)
            if not data or "id" not in data:
                return SendResult(
                    success=False, error="Failed to send DM approval post"
                )

            # 5. 在原频道发送简短提示
            await self.send(
                chat_id,
                "⏳ 已向您发送私信，请在 DM 中审批危险命令。",
            )

            return SendResult(success=True, message_id=data.get("id"))

        except Exception as e:
            logger.error(
                "[Mattermost] send_exec_approval failed: %s",
                e,
                exc_info=True,
            )
            return SendResult(success=False, error=str(e))

    # ── End Patch: DM 审批方法 ──

'''
    marker = "    # ------------------------------------------------------------------\n    # Required overrides\n    # ------------------------------------------------------------------"
    if marker in content:
        content = content.replace(marker, dm_methods + marker)
        with open(file_path, 'w') as f:
            f.write(content)
        print("APPLIED")
    else:
        print("SKIP")
else:
    print("SKIP")
PYEOF

    # 7c. connect() 末尾启动 callback server
    _do_patch "gateway/platforms/mattermost.py" \
        "mattermost.py (connect callback)" \
        'await self._start_callback_server' <<'PYEOF'
import sys
file_path = sys.argv[1]
with open(file_path, 'r') as f:
    content = f.read()

old = '''        self._ws_task = asyncio.create_task(self._ws_loop())
        self._mark_connected()

        return True'''

new = '''        self._ws_task = asyncio.create_task(self._ws_loop())
        self._mark_connected()

        # ── Hermes Patch: 启动审批回调服务器 ──
        await self._start_callback_server()
        # ── End Patch ──

        return True'''

if old in content and "_start_callback_server" not in content[content.find("self._ws_task = asyncio.create_task(self._ws_loop())"):
    content = content.replace(old, new)
    with open(file_path, 'w') as f:
        f.write(content)
    print("APPLIED")
else:
    print("SKIP")
PYEOF

    # 7d. disconnect() 开头停止 callback server
    _do_patch "gateway/platforms/mattermost.py" \
        "mattermost.py (disconnect callback)" \
        'await self._stop_callback_server' <<'PYEOF'
import sys
file_path = sys.argv[1]
with open(file_path, 'r') as f:
    content = f.read()

old = '''    async def disconnect(self) -> None:
        """Disconnect from Mattermost."""
        self._closing = True'''

new = '''    async def disconnect(self) -> None:
        """Disconnect from Mattermost."""
        self._closing = True

        # ── Hermes Patch: 停止审批回调服务器 ──
        await self._stop_callback_server()
        # ── End Patch ──'''

if old in content and "_stop_callback_server" not in content[content.find("async def disconnect"):content.find("async def disconnect")+500]:
    content = content.replace(old, new)
    with open(file_path, 'w') as f:
        f.write(content)
    print("APPLIED")
else:
    print("SKIP")
PYEOF

    # ── 8. gateway/run.py — 传入 user_id ─────────────────────────────────
    _do_patch "gateway/run.py" \
        "run.py (user_id 传入审批)" \
        'user_id=source.user_id' <<'PYEOF'
import sys
file_path = sys.argv[1]
with open(file_path, 'r') as f:
    content = f.read()

old = '''                            _status_adapter.send_exec_approval(
                                chat_id=_status_chat_id,
                                command=cmd,
                                session_key=_approval_session_key,
                                description=desc,
                                metadata=_status_thread_metadata,
                            ),'''

new = '''                            _status_adapter.send_exec_approval(
                                chat_id=_status_chat_id,
                                command=cmd,
                                session_key=_approval_session_key,
                                description=desc,
                                metadata=_status_thread_metadata,
                                user_id=source.user_id if hasattr(source, 'user_id') else None,  # Hermes Patch: MM DM 审批
                            ),'''

if old in content and "user_id=source.user_id" not in content:
    content = content.replace(old, new)
    with open(file_path, 'w') as f:
        f.write(content)
    print("APPLIED")
else:
    print("SKIP")
PYEOF

    # ── 8b. gateway/run.py — 工具进度进入 Mattermost Thread ──────────────
    _do_patch "gateway/run.py" \
        "run.py (progress reply 进 Thread)" \
        'Platform.MATTERMOST.*and source.thread_id' <<'PYEOF'
import sys
file_path = sys.argv[1]
with open(file_path, 'r') as f:
    content = f.read()

old = '''        _progress_reply_to = (
            event_message_id
            if source.platform == Platform.FEISHU and source.thread_id and event_message_id
            else None
        )'''

new = '''        _progress_reply_to = (
            event_message_id
            if (
                (source.platform == Platform.FEISHU and source.thread_id)
                or source.platform == Platform.MATTERMOST
            ) and event_message_id
            else None
        )'''

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
        "utils.py (yaml allow_unicode)" \
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
        "run.py (MEDIA 工具结果扫描)" \
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
    local base_file="${AGENT_DIR}/gateway/platforms/base.py"
    if [[ -f "$base_file" ]]; then
        python3 -c "
import sys
with open('$base_file', 'rb') as f:
    raw = f.read()
# 精确移除 extract_media() 中的 |\\\\S+ 兜底分支
old = b'|\\$)|\\\\\\\\S+)'
new = b'|\\$))'
if old in raw:
    raw = raw.replace(old, new)
    with open('$base_file', 'wb') as f:
        f.write(raw)
    print('APPLIED')
else:
    print('SKIP')
" 2>/dev/null && media_ok=$((media_ok + 1)) || true
    else
        error "gateway/platforms/base.py 不存在，跳过"
    fi

    # 10c. mattermost.py — 文件不存在时静默跳过
    _do_patch "gateway/platforms/mattermost.py" \
        "mattermost.py (MEDIA 静默跳过)" \
        'local file not found, skipping' <<'PYEOF'
import sys
file_path = sys.argv[1]
with open(file_path, 'r') as f:
    content = f.read()

old = '''        if not p.exists():
            return await self.send(
                chat_id, f"{caption or ''}\\\\n(file not found: {file_path})", reply_to
            )'''

new = '''        if not p.exists():
            logger.warning(
                "Mattermost: local file not found, skipping: %s", file_path
            )
            return SendResult(success=True, message_id=None)'''

if old in content:
    content = content.replace(old, new)
    with open(file_path, 'w') as f:
        f.write(content)
    print("APPLIED")
else:
    print("SKIP")
PYEOF
    [[ $? -eq 0 ]] && media_ok=$((media_ok + 1))

    [[ $media_ok -gt 0 ]] && ok "MEDIA 正则收紧 — 已应用"
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
