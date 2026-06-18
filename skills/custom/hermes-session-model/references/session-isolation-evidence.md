# Session Isolation Evidence (Source Code)

## Platform Constants

File: `gateway/config.py:108-120`
```python
LOCAL = "local"
MATTERMOST = "mattermost"
API_SERVER = "api_server"
```

## Session Key Construction

File: `gateway/session.py:628-670`

```python
def build_session_key(source: SessionSource) -> str:
    platform = source.platform.value  # "mattermost" / "local" / "api_server"
    
    if source.chat_type == "dm":
        # ... DM handling ...
        return f"agent:main:{platform}:dm"
    
    key_parts = ["agent:main", platform, source.chat_type]
    if source.chat_id:
        key_parts.append(source.chat_id)
    if source.thread_id:
        key_parts.append(source.thread_id)
    # ...
```

Key insight: `platform` is the first-level discriminator. Different platforms ALWAYS get different session keys.

## LOCAL → "cli" Mapping

File: `gateway/run.py:1550`
```python
return "cli" if platform == Platform.LOCAL else platform.value
```

Desktop sessions get `source="cli"` in state.db.

## History Loading

File: `gateway/run.py:7867`
```python
history = self.session_store.load_transcript(session_entry.session_id)
```

History is always loaded from state.db, NEVER from the platform's own database (e.g. Mattermost PostgreSQL).

## Desktop Session Skipped in Discovery

File: `gateway/channel_directory.py:82`
```python
_SKIP_SESSION_DISCOVERY = frozenset({"local", "api_server", "webhook"})
```

Local (Desktop/CLI) sessions are hidden from channel directory.

## Session Hygiene / Compression

File: `gateway/run.py:7884-7900`
```python
# Hygiene threshold is 0.85 (85% of context), higher than agent's own 0.50
_hyg_threshold_pct = 0.85
_hyg_hard_msg_limit = 400
```

## Auto-Pruning

File: `hermes_state.py:4195-4197`
```python
def maybe_auto_prune_and_vacuum(
    self,
    retention_days: int = 90,
    ...
```

Only prunes ended sessions (`end_reason IS NOT NULL`).
