# Models Whitelist Fix — Cross-Project Pattern

## Problem

Aggregator gateways (ZenMux, Bifrost, etc.) expose hundreds of models via
`/v1/models`. When a user configures a curated `models:` list in `config.yaml`
under `custom_providers`, the picker should show ONLY those models — not the
full online catalog.

This bug exists in **two independent codebases** that must be fixed separately:

## Fix 1: hermes-agent (`model_switch.py`)

**File:** `~/.hermes/hermes-agent/hermes_cli/model_switch.py`  
**Function:** `list_authenticated_providers()`  
**Section:** Section 4 (custom_providers groups processing)

**Fix:** Add `not grp["models"]` guard before live discovery:

```python
# OLD (bad — unconditional live fetch):
if api_url and api_key:
    live_models = fetch_api_models(api_key, api_url)
    if live_models:
        grp["models"] = live_models

# NEW (good — skip fetch if user already configured models):
if not grp["models"] and api_url and api_key:
    live_models = fetch_api_models(api_key, api_url)
    if live_models:
        grp["models"] = live_models
```

**Patch:** `hermes-patches.sh` Section 3 (#3)

## Fix 2: hermes-webui (`api/config.py`)

**File:** `~/.hermes/hermes-webui/api/config.py`  
**Function:** `_build_available_models_uncached()` (inner `_named_custom_groups` block)  
**Line:** ~3333 (near `_live_models = auto_detected_models_by_provider.get(...)`)

**Fix:** Check if `_cp.get("models")` has configured entries before live fetch:

```python
# OLD (bad — unconditional live fetch):
_live_models = auto_detected_models_by_provider.get(_slug) or _read_custom_endpoint_models(
    _cp_base_url, _slug, api_key=_cp_api_key, trusted_base_urls=(_cp_base_url,),
)

# NEW (good — skip fetch if user already configured models):
_cp_configured_models = _cp.get("models")
_cp_has_configured_models = (
    isinstance(_cp_configured_models, (dict, list))
    and len(_cp_configured_models) > 0
)
if _cp_has_configured_models:
    _live_models = auto_detected_models_by_provider.get(_slug) or []
else:
    _live_models = auto_detected_models_by_provider.get(_slug) or _read_custom_endpoint_models(
        _cp_base_url, _slug, api_key=_cp_api_key, trusted_base_urls=(_cp_base_url,),
    )
```

**Patch:** `hermes-patches.sh` Section 11 (#11, WEBUI: prefix)

## Post-Fix Cleanup

After fixing hermes-webui code, delete the disk cache or it will keep serving
stale data:

```bash
rm ~/.hermes/webui/models_cache.json
```

The cache rebuilds on next WebUI restart with the corrected logic.

## hermes-patches.sh WEBUI Support

The patches script now supports `WEBUI:` prefix in the registry for paths
outside `AGENT_DIR`:

```bash
# Registry entry format:
"WEBUI:api/config.py|webui config.py (label)|check_grep_pattern"

# show_status resolves:
if [[ "$file_rel" == WEBUI:* ]]; then
    file="${WEBUI_DIR}/${file_rel#WEBUI:}"
else
    file="${AGENT_DIR}/${file_rel}"
fi
```

A `_do_patch_webui()` function mirrors `_do_patch()` but uses `WEBUI_DIR`.
