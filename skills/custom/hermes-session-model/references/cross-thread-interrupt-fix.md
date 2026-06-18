# Cross-Thread Interrupt Fix (P60a + P60b)

## Bug Summary

When a message interrupts an active agent session from a different thread within the same channel, subsequent responses are routed to the wrong thread.

This affects all platforms with thread support (Mattermost, Discord, Slack) where `busy_input_mode=interrupt`.

## Reproduction

1. Start a conversation in Thread A
2. While the agent is processing, send a channel-level post in the SAME channel
3. The channel-level post interrupts the Thread A agent
4. Agent's response goes to a NEW thread (rooted at the channel-level post), not Thread A

## Root Cause (Two Bugs in `gateway/run.py`)

### Bug 1: `_cache_session_source` overwrite on resume

`_handle_message_with_agent` calls `self._cache_session_source(session_key, source)` on every entry. When the session resumes after an interrupt, `source` is the interrupting message's source (wrong `thread_id`, wrong `message_id`), overwriting the correct cached source.

**Fix (P60a)**:
```python
# Before:
self._cache_session_source(session_key, source)

# After:
if not self._get_cached_session_source(session_key):
    self._cache_session_source(session_key, source)
```

### Bug 2: Thread metadata lost on resume

`_thread_metadata_for_source(source, event_message_id)` returns `None` when `source.thread_id` is `None` (channel-level posts). The stream consumer then routes without thread context.

**Fix (P60b)**:
```python
_thread_metadata = self._thread_metadata_for_source(source, event_message_id)

# Add fallback to cached source:
if _thread_metadata is None:
    _cached_meta_source = self._get_cached_session_source(session_key)
    if _cached_meta_source is not None:
        _thread_metadata = self._thread_metadata_for_source(
            _cached_meta_source, event_message_id)
```

## Evidence (Log Analysis)

From the initial bug report on 2026-06-16:

```
17:13:19 send() — thread_id=63dr38uhktbttk4anosuyo1upc  ← correct (Thread A)
17:15:26 _resolve_root_id — input=cbkh1u55m7dh9kqwjo5igmo9qh  ← wrong (interrupting post)
17:15:27 Turn ended: interrupted_during_api_call
17:15:41 → 17:16:34  three sends all targeting cbkh1u55...  ← all wrong
```

The thread routing switched from the original Thread A (`63dr38uh...`) to the interrupting post's thread (`cbkh1u55...`) at the moment of interruption.

## Patch Location

Both patches are in `gateway/run.py`:
- P60a: ~line 7934 (within `_handle_message_with_agent`, after `get_or_create_session`)
- P60b: ~line 12935 (within the streaming setup section)

## Test Verification

```bash
cd ~/.hermes/hermes-agent
git checkout -- gateway/run.py          # revert to upstream
bash ~/.hermes/scripts/hermes-patches.sh apply   # apply all patches
bash ~/.hermes/scripts/hermes-patches.sh check   # verify 9/9
grep "cross-thread" gateway/run.py               # confirm both fixes present
```
