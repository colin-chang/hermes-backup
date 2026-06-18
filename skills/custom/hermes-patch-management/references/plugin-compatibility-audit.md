# Plugin Compatibility Audit Methodology

Systematic workflow for auditing a Hermes custom plugin's compatibility
with a new Hermes Agent version.

---

## When to Run

- After `git pull` on the hermes-agent source
- After `hermes update` or version bump
- When a plugin shows runtime errors after an update

## Audit Steps

### Step 1: Identify Plugin Components

List all `.py` files, `plugin.yaml`, and any shell patch scripts:

```bash
find ~/.hermes/plugins/<plugin-name>/ -name '*.py' -o -name 'plugin.yaml' -o -name '*.sh'
```

### Step 2: Check Method Signature Compatibility

For every method override in the plugin adapter, verify it matches the
parent class signature in the bundled adapter:

```bash
# List all async def in plugin adapter
grep -n "async def " ~/.hermes/plugins/<plugin>/adapter.py

# For each, check parent signature
grep -A5 "async def <method_name>" ~/.hermes/hermes-agent/plugins/platforms/<platform>/adapter.py
```

**Signal of breakage**:
- Parent added/removed a required parameter
- Parent changed return type
- Parent renamed the method

**Safe patterns**:
- Plugin adds extra keyword args with defaults (e.g., `metadata=None`)
- Plugin uses `**kwargs` catch-all

### Step 3: Verify Internal API Dependencies

List every import and attribute access on internal Hermes APIs:

```bash
grep -E "(from |import |\._[a-z]+|self\._[a-z]+|\._session_|\._evict_|\._pending_|\._clear_|\._set_session_)" \
  ~/.hermes/plugins/<plugin>/adapter.py
```

For each dependency, verify it still exists in the new version:

```bash
grep -rn "def <function_name>\|<attribute_name>" ~/.hermes/hermes-agent/
```

**Key targets to check**:
| Category | Examples |
|----------|----------|
| Gateway runner internals | `_session_model_overrides`, `_evict_cached_agent()`, `_set_session_reasoning_override()` |
| Session store | `session_store.reset_session()` |
| Tool utilities | `resolve_gateway_approval()`, `resolve_gateway_clarify()` |
| Config/switch | `load_config()`, `switch_model()`, `get_compatible_custom_providers()` |
| Bundled adapter exports | `MattermostAdapter`, `MAX_POST_LENGTH`, `_apply_yaml_config`, etc. |

### Step 4: Check for Silently Bypassed Parent Features

When a plugin completely overrides a parent method (not just wrapping with
`super().method()`), new parent features may be silently lost.

**How to detect**:
1. Find all methods where the plugin does NOT call `super()`:
   ```bash
   grep -B2 "async def " ~/.hermes/plugins/<plugin>/adapter.py | grep -v super
   ```
2. For each such method, diff the parent's implementation between versions:
   ```bash
   git diff <old-commit>..HEAD -- plugins/platforms/<platform>/adapter.py
   ```
3. Check if any new logic (retry, fallback, error handling) should be
   incorporated into the plugin's override.

**Case study**: `send()` in mattermost-enhancer — completely overrides parent's
`send()`, bypassing new `_post_preserving_thread()` which adds broken-thread-root
fallback. Not a breaking change, but a missed enhancement opportunity.

### Step 5: Verify Plugin Registration

Check `__init__.py`'s `register()` function — all imported names from the
bundled adapter must still exist:

```python
from hermes_plugins.platforms_<name>.adapter import (
    _apply_yaml_config,   # ← must exist
    _is_connected,         # ← must exist
    ...
)
```

### Step 6: Spot-Check Hook Dependencies

If the plugin registers hooks (`pre_gateway_dispatch`, etc.), verify the
hook function's accessed attributes on the gateway/session_store still exist:

```python
def hook(event, gateway, session_store, **kwargs):
    gateway._session_model_overrides  # ← check this attr
```

### Step 7: Test Import Chain

```bash
cd ~/.hermes/hermes-agent
# In the Hermes virtualenv:
python3 -c "
from hermes_plugins.<plugin_name> import register
print('Import OK')
"
```

If the plugin has a fallback import path (like mattermost-enhancer's
try/except ImportError), test both paths.

---

## Quick Audit Checklist

- [ ] All method override signatures match parent
- [ ] All `from X import Y` paths resolve
- [ ] All `gateway.run` internal attributes (`_session_*`, `_evict_*`) exist
- [ ] All tool utility imports (`tools.clarify_gateway`, `tools.approval`) resolve
- [ ] Plugin registration in `__init__.py` uses valid bundled adapter exports
- [ ] No silently bypassed parent features (new retry/fallback logic)
- [ ] `plugin.yaml` `min_hermes_version` is reasonably current
- [ ] Hook functions access only existing gateway attributes
- [ ] Import chain passes in python3
