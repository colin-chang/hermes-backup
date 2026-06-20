# Mattermost Enhancer Audit — 2026-06-20

Full dual-verification + plugin compatibility audit performed against
hermes-agent `v2026.6.19-51 (origin:main=b88d0007c9)`.
Previous verification: `v2026.6.5-1117 (origin:main=17251e865)`.

## Patch Script: `scripts/hermes-mattermost-enhancer.sh`

All 5 patches passed dual verification (Dim A=0, Dim B=FOUND). No changes
needed to patch logic — only Header version annotation requires updating.

| Patch | Target | Dim A | Dim B | Action |
|:---:|---|:---:|:---:|---|
| P1 | `_progress_reply_to` thread routing | ❌ 0 | ✅ | Keep |
| P2 | Clarify session split (`_canonical_entry`) | ❌ 0 | ✅ | Keep |
| P3 | Clarify concurrency guard | ❌ 0 | ✅ | Keep |
| P4 | Auto-resume session dedup | ❌ 0 | ✅ | Keep |
| P5 | `_status_thread_metadata` fallback | ❌ 0 | ✅ | Keep |

## Plugin Compatibility Findings

### Breaking (latent — dead code, not runtime)

- **`_update_bot_post()` (adapter.py:362)**: calls
  `self._api_post(f"posts/{post_id}", payload, method="PUT")` — upstream
  `_api_post(self, path, payload)` no longer accepts `method=`.
  Upstream added `_api_put(self, path, payload)` in commit `af973e4071`.
  Fix: `self._api_put(f"posts/{post_id}/patch", payload)`.
  This method is defined but never called — latent bug.

### Signature drift (safe today, diverges from upstream)

- **`_send_local_file()`**: plugin lacks `metadata=None` param.
  Upstream added it; plugin does its own thread routing via
  `_get_thread_root_id(reply_to)`. Functionally equivalent.
- **`_send_url_as_file()`**: same — plugin lacks `metadata=None`.
- **`_resolve_root_id()`**: plugin returns `Optional[str]` (with 5min
  cache + LRU cleanup); upstream returns `str` (no cache). Both define
  this method. If upstream's `_thread_root_for_send()` is called on the
  plugin's adapter instance, a `None` return could break downstream.
  Currently safe because plugin overrides `send()` (the only caller).

### Missed upstream enhancements (feature gaps, not bugs)

- **`_post_preserving_thread()`**: upstream's `send()` now uses this to
  fall back to flat channel delivery when `root_id` causes 400/404 on
  `notify=True` messages. Plugin's `send()` calls `_api_post` directly.
- **`_thread_root_for_send()`**: upstream unified reply_to + metadata →
  root_id resolution into this helper. Plugin has ~70 lines of manual
  logic doing the same thing.
- **`send_multiple_images()`**: upstream now uses
  `_thread_root_for_send(None, metadata)` + `_post_preserving_thread()`.
  Plugin's version resolves root_id manually.

### Positive: automatic benefit from upstream changes

- **`_ws_loop()` reconnection wrapper**: upstream added this in
  `_ws_loop()` which calls `_ws_connect_and_listen()` in a loop with
  exponential backoff + jitter. Plugin's `connect()` calls
  `super().connect()` → `_ws_loop()` → plugin's overridden
  `_ws_connect_and_listen()` (heartbeat=15s). Plugin gets reconnection
  for free — no action needed.

### Internal API dependencies — all verified OK

| Category | Items | Status |
|---|---|:---:|
| Gateway runner | `_gateway_runner_ref`, `_session_model_overrides`, `_evict_cached_agent`, `_set_session_reasoning_override`, `_clear_session_boundary_security_state`, `_pending_model_notes` | ✅ |
| Session store | `session_store.reset_session()` (in `gateway/session.py:1219`) | ✅ |
| Bundled exports | `_apply_yaml_config`, `_is_connected`, `_standalone_send`, `interactive_setup`, `MAX_POST_LENGTH` | ✅ |
| Tools | `resolve_gateway_approval`, `resolve_gateway_clarify`, `get_pending_for_session`, `mark_awaiting_text` | ✅ |
| Config | `load_config`, `get_compatible_custom_providers`, `switch_model` | ✅ |
| Method signatures | `send()`, `send_typing()`, `send_clarify()`, `send_image*()`, `send_document()`, `send_video()`, `send_voice()` | ✅ |
| Gateway calls | `send_exec_approval(chat_id=, command=, session_key=, description=, metadata=)` | ✅ |

### Still-needed overrides (upstream hasn't fixed)

- `edit_message()` — upstream `_api_put()` still lacks timeout (plugin's
  self-implemented HTTP PUT with 30s timeout still needed)
- `_ws_connect_and_listen()` — upstream still uses `heartbeat=30.0`
  (plugin's 15s override still needed)

### Dead code

- `send_model_picker()` — gateway no longer calls this method (grep
  `send_model_picker` in `gateway/run.py` returns 0 results). Retained
  as forward-compat stub, returns `SendResult(success=False)`.

## Recommended Actions (priority order)

| Priority | Action | Effort |
|:---:|---|---|
| P0 | Update patch script Header version to `b88d0007c9` | trivial |
| P1 | Fix `_update_bot_post()`: `_api_post(method="PUT")` → `_api_put()` | 1 line |
| P2 | Add `metadata=None` to `_send_local_file()` / `_send_url_as_file()` | 2 lines |
| P3 | Consider adopting `_post_preserving_thread()` in `send()` | optional |
