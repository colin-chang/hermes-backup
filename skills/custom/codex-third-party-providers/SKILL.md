---
name: codex-third-party-providers
description: "Configure and troubleshoot Codex with non-OpenAI model providers (ZenMux, relays, custom endpoints) and Chrome extension regional restrictions. Covers requires_openai_auth semantics, model discovery flow, model_catalog_json vs models_cache.json, CC Switch interaction, and common failure modes."
version: 1.1.0
author: Hermes Agent
platforms: [macos, linux]
metadata:
  hermes:
    tags: [codex, third-party, zenmux, cc-switch, model-config, troubleshooting]
---

# Codex Third-Party Provider Configuration

Configure Codex (CLI and Desktop) to use non-OpenAI model providers like ZenMux, API relays, or custom endpoints. Covers config file structure, model discovery, authentication, and CC Switch interaction.

## When to Use

- Setting up Codex with a third-party model provider
- Debugging "can't switch models" in Codex Desktop
- Understanding why Codex Desktop prompts for login despite custom API key
- CC Switch + Codex interaction issues
- Model catalog not showing expected models
- Chrome extension installation blocked by region ("此商品无法购买或下载")

## Config File (`~/.codex/config.toml`)

### Minimal Working Config (Direct Connection, No Proxy)

```toml
model_provider = "zenmux"
model = "deepseek/deepseek-v4-pro"

[model_providers.zenmux]
name = "ZenMux"
wire_api = "responses"
requires_openai_auth = false
base_url = "https://zenmux.ai/api/v1"
experimental_bearer_token = "sk-ss-v1-..."
```

### Key Config Fields

| Field | Purpose | Notes |
|-------|---------|-------|
| `model_provider` | Active provider ID | Must match the `[model_providers.<id>]` section key |
| `wire_api` | API protocol | `"responses"` for Codex-native, `"chat"` for OpenAI Chat Completions |
| `requires_openai_auth` | Require OpenAI OAuth | `true` = look for auth in `auth.json`; `false` = use bearer token directly |
| `base_url` | Provider API endpoint | Must include `/v1` path for OpenAI-compatible endpoints |
| `experimental_bearer_token` | API key for this provider | Injected as HTTP header; CC Switch uses `"PROXY_MANAGED"` placeholder |
| `model_catalog_json` | Path to static model catalog | Relative to `~/.codex/`; use **absolute path** to avoid resolution issues |

### `requires_openai_auth` Semantics (⚠️ Critical)

- **`true`**: Codex looks for authentication in `~/.codex/auth.json` (OAuth tokens from ChatGPT login). If `auth.json` doesn't exist or is expired → **Desktop App shows login prompt**. The CC Switch local proxy sets this to `true` because it intercepts the auth flow and injects the real API key.
- **`false`**: Codex uses `experimental_bearer_token` directly as the API key. No `auth.json` needed. **This is required when you don't have an OpenAI account.**

**Pitfall:** CC Switch Proxy takeover automatically sets `requires_openai_auth = true` even if your original config had `false`. This is the root cause of "worked before, login prompt after enabling proxy."

## Model Discovery Flow

Codex discovers available models through a priority chain. The Desktop App and CLI use **different code paths**.

### Desktop App Priority (via `codex app-server`)

```
① models_cache.json     → Cache from previous successful online fetch
② Online API fetch      → Calls provider's models endpoint
③ Fallback              → Only the single model from config.toml `model=` field
```

**`model_catalog_json` is NOT used by the Desktop App for model listing.** It's only used for model validation when making API calls. This means a static catalog file alone won't populate the model selector in the UI.

### CLI (`codex debug models`)

Uses `model_catalog_json` directly, so the CLI can show all models from the catalog even when the Desktop App shows only one.

### Why Online Fetch Often Fails

Third-party providers may return API responses in formats Codex doesn't recognize:

- **Tool type mismatch**: Provider returns `"type": "custom"` but Codex expects `"type": "function"` → `400 Failed to deserialize`
- **Model list format**: Provider's `/v1/models` response may not include fields Codex needs for caching

When online fetch fails, `models_cache.json` is never created, and the model list stays stuck at one model.

### Creating `models_cache.json` Manually

When online fetch fails, manually create `~/.codex/models_cache.json` to populate the model list:

```json
{
  "version": "0.142.0",
  "generated_at": 1781977600,
  "model_provider": "zenmux",
  "models": [
    {
      "slug": "deepseek/deepseek-v4-pro",
      "display_name": "DeepSeek V4 Pro",
      "description": "DeepSeek V4 Pro",
      "context_window": 1000000,
      "max_context_window": 1000000,
      "effective_context_window_percent": 95,
      "priority": 1000,
      "supported_in_api": true,
      "input_modalities": ["text"],
      "additional_speed_tiers": [],
      "service_tiers": [],
      "availability_nux": null,
      "upgrade": null,
      "base_instructions": "...",
      "model_messages": { "...": "..." },
      "supported_reasoning_levels": [
        {"effort": "low", "description": "Fast responses with lighter reasoning"},
        {"effort": "medium", "description": "Balanced"},
        {"effort": "high", "description": "Greater depth"},
        {"effort": "xhigh", "description": "Extra high depth"}
      ],
      "default_reasoning_level": "medium",
      "default_reasoning_summary": "none",
      "support_verbosity": true,
      "default_verbosity": "low",
      "apply_patch_tool_type": "freeform",
      "shell_type": "shell_command",
      "supports_reasoning_summaries": true,
      "supports_parallel_tool_calls": true,
      "supports_image_detail_original": true,
      "supports_search_tool": true,
      "use_responses_lite": false,
      "experimental_supported_tools": [],
      "truncation_policy": {"mode": "tokens", "limit": 10000},
      "web_search_tool_type": "text_and_image"
    }
  ]
}
```

Key rules:
- `version` must match the Codex CLI version (visible in logs as `expected_version="0.142.0"`)
- `base_instructions` and `model_messages` can be copied from the GPT-5.5 template in `cc-switch-model-catalog.json`
- After creating, **fully quit and restart** Codex Desktop (kill `codex app-server` process)
- Verify with `codex debug models` (CLI) or check logs for `models cache:` entries

See `references/models-cache-creation.py` for a script that generates this from a model list.

## CC Switch Interaction

### What CC Switch Manages

| File | Managed by CC Switch | Purpose |
|------|:---:|---------|
| `~/.codex/config.toml` | ✅ | Live config (provider, model, base_url, auth) |
| `~/.codex/auth.json` | ❌ (by design) | ChatGPT OAuth tokens; preserved across provider switches |
| `~/.codex/cc-switch-model-catalog.json` | ✅ | Static model catalog |
| `~/.codex/models_cache.json` | ❌ | Created by Codex itself on successful online fetch |

### Proxy Takeover Behavior

When CC Switch Proxy is enabled, it rewrites the live config:
- `requires_openai_auth`: `false` → `true` (proxy needs `auth.json` to intercept tokens)
- `base_url`: Direct provider URL → `http://127.0.0.1:15721/v1` (local proxy)
- `experimental_bearer_token`: Real key → `"PROXY_MANAGED"` (placeholder)
- `model_catalog_json`: Added if not present

The proxy intercepts `model/list` RPC calls and returns the static catalog. Without the proxy, model listing relies on Codex's own discovery flow (models_cache.json → online fetch).

### Restoring Pre-Proxy State

CC Switch stores the pre-proxy config in its database (`proxy_live_backup` table). Query with:
```python
import sqlite3, json
conn = sqlite3.connect('/Users/Colin/.cc-switch/cc-switch.db')
cur = conn.cursor()
cur.execute("SELECT original_config FROM proxy_live_backup WHERE app_type='codex'")
row = cur.fetchone()
# Contains the original config before proxy takeover
```

### Common Failure Modes

| Symptom | Root Cause | Fix |
|---------|-----------|-----|
| Login prompt after enabling proxy | `requires_openai_auth = true` + no `auth.json` | Disable proxy OR create minimal `auth.json` |
| Can't switch models after disabling proxy | `models_cache.json` missing + online fetch fails | Create `models_cache.json` manually; restart |
| Config changes not taking effect | `codex app-server` process caches config in memory | Kill `codex app-server` before restarting Desktop |
| `model_catalog_json` relative path fails | Path resolved relative to CWD, not `~/.codex/` | Use absolute path |
| Chrome extension "此商品无法购买或下载" | Regional availability gating by OpenAI on Chrome Web Store | Sideload CRX, direct download via `clients2.google.com`, or VPN + account region change → see `references/codex-chrome-extension-regional-restrictions.md` |

## Chrome Extension

Codex Desktop requires a Chrome extension for Computer Use / browser integration. The extension (ID `hehggadaopoacecdllhhajmbjkdcmjag`) is distributed via Chrome Web Store, but OpenAI has applied **regional availability gating** — users in mainland China, Hong Kong, EU, and Switzerland see "此商品无法购买或下载" (This item cannot be purchased or downloaded).

The restriction is bound to the Google account's registered country, not the network IP. VPN alone may not suffice if the Google account country is also restricted.

**Workarounds** (see `references/codex-chrome-extension-regional-restrictions.md` for full details):

1. **Direct CRX download via Google Update Service** ⭐ — safest, pulls from Google CDN:
   ```
   https://clients2.google.com/service/update2/crx?response=redirect&acceptformat=crx2,crx3&x=id%3Dhehggadaopoacecdllhhajmbjkdcmjag%26uc
   ```
   Paste in Chrome → downloads `.crx` → rename to `.zip` → extract → Chrome `chrome://extensions/` → Developer Mode → Load unpacked.

2. **Sideload via Developer Mode** — download CRX from any source, unzip, load unpacked.

3. **VPN + Google account country change** — switch to US VPN, change Google Pay profile to US, retry. May require creating a new US-region Google account.

**GitHub Issues**: `openai/codex#21700` (open, 21 comments), `#29102`, `#27397`. No official offline installer provided.

## Troubleshooting
```bash
# Check what Codex sees in its config
/Applications/Codex.app/Contents/Resources/codex debug models

# Check real-time logs
python3 -c "
import sqlite3
conn = sqlite3.connect('$HOME/.codex/logs_2.sqlite')
cur = conn.cursor()
cur.execute(\"SELECT ts, level, target, feedback_log_body FROM logs WHERE target LIKE '%model%' OR target LIKE '%auth%' ORDER BY id DESC LIMIT 20\")
for r in cur.fetchall():
    print(f'[{r[0]}] [{r[1]}] {r[2]}: {r[3][:200] if r[3] else \"(empty)\"}')
"
```

### Kill Stale Processes
```bash
pkill -f "codex app-server"
pkill -f "Codex.app/Contents/MacOS/Codex"
```

### Key File Locations
- Config: `~/.codex/config.toml`
- Auth: `~/.codex/auth.json` (may not exist)
- Model cache: `~/.codex/models_cache.json`
- Static catalog: `~/.codex/cc-switch-model-catalog.json`
- Logs: `~/.codex/logs_2.sqlite`
- Sessions: `~/.codex/sessions/`
- CC Switch DB: `~/.cc-switch/cc-switch.db`

## References

- `references/models-cache-creation.py` — Script to generate `models_cache.json` from a model list with correct Codex format
- `references/codex-discovery-flow.md` — Detailed model discovery flow with log trace analysis
- `references/codex-chrome-extension-regional-restrictions.md` — Regional restrictions: root cause, workarounds, GitHub issue references
