# Cross-Thread Interrupt Routing Bug — Diagnosis

When a user reports that a response appeared in the wrong Mattermost thread ("串台"), this is the diagnostic workflow.

## Symptoms

- User: "消息串台了，A 线程的回复跑到 B 线程了"
- The wrong-thread response typically contains content meant for a different thread
- The symptom typically happens shortly after sending a message that interrupted a running agent

## Root Cause (Confirmed)

Two bugs in `gateway/run.py`:

1. **Session source overwrite on resume** (~L7934): `_cache_session_source()` overwrites the original session's source with the interrupting message's source on rerentry to `_handle_message_with_agent`.

2. **Thread metadata loss** (~L12884): When `source.thread_id` is `None` (channel-level post), `_thread_metadata_for_source()` returns `None`, causing the stream consumer to lose thread routing.

Combined effect: interrupted session restarts with wrong `message_id` and `thread_id=None`, sending all responses to wrong thread.

## Diagnostic Steps

### Step 1: Identify the Sessions

```bash
# In session_search, find the session that produced the misrouted content
session_search(query="MiMo DeepSeek 对比")  # replace with relevant keywords
```

Note the `session_id` and the `source` (mattermost).

### Step 2: Find the Session Key Context

In `gateway.log`, find the inbound messages for the time window:
```bash
grep "inbound message" ~/.hermes/logs/gateway.log | grep "<time_range>"
```

Note the `chat=` value (channel ID).

### Step 3: Trace the send() Routing

Search for `send() threading` and `_resolve_root_id` around the interruption time:
```bash
grep -n "send() threading\|_resolve_root_id" ~/.hermes/logs/agent.log | grep "<timestamp_range>"
```

**Key pattern**: If the `reply_to`/`resolved_root` in `send() threading` lines changes BEFORE and AFTER an interruption, this is the bug.

Example:
```
# Before interrupt (correct):
send() threading — thread_id=63dr38uhktbttk4anosuyo1upc  ✅

# After interrupt (wrong):
send() threading — reply_to=cbkh1u55m7dh9kqwjo5igmo9qh  ❌
```

### Step 4: Confirm the Interruption

```bash
grep "interrupted_during_api_call\|tcp_force_closed=1" ~/.hermes/logs/agent.log
```

The turn exit reason tells you the agent was interrupted during an API call.

### Step 5: Verify Against Patches

```bash
bash ~/.hermes/scripts/hermes-patches.sh check
```

P60a and P60b should be listed. If they show `[WARN]`, the fix is not applied.

## Fix Reference

Two patches in `hermes-patches.sh`:
- **P60a**: Guards `_cache_session_source` call with `if not self._get_cached_session_source(session_key)`
- **P60b**: Falls back to cached session source for `_thread_metadata` when current source returns `None`

## Related

- `hermes-patch-management` skill — patch creation conventions
- `hermes-session-model` skill — session_key architecture
- `hermes-operations` skill — general log analysis workflow
