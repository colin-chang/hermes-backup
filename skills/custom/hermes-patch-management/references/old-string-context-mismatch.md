# Old-String Context Mismatch Pitfall

When constructing an `old_string` for a Python heredoc patch, the most common failure mode is **including wrong surrounding context lines** that don't match the actual upstream code.

## The Pitfall

You visually identify the target line and assume certain lines appear right before it. But the upstream code may have **additional statements** between your assumed context and the target line. The result: `old in content` returns `False`, the patch prints `SKIP`, and the patch silently fails.

## Real Example: P60a Cross-Thread Interrupt Fix

**Target line** (what we wanted to replace):
```python
self._cache_session_source(session_key, source)
```

**Assumed context** (WRONG):
```python
            except Exception:
                pass
        self._cache_session_source(session_key, source)
        if self._is_telegram_topic_lane(source):
```

**Actual upstream code** (RIGHT):
```python
            except Exception:
                pass

        session_entry = self.session_store.get_or_create_session(source)
        session_key = session_entry.session_key
        self._cache_session_source(session_key, source)
        if self._is_telegram_topic_lane(source):
```

The `except Exception: pass` block was there, but two **unexpected lines** (`session_entry = ...` and `session_key = ...`) sat between it and the target. The `old in content` check failed because of this gap.

## How to Avoid

1. **Always `grep` the target line and read the surrounding context BEFORE writing old_string.**
   ```bash
   grep -n -B5 -A2 "cache_session_source" gateway/run.py
   ```

2. **Include enough surrounding lines to make old_string unique, but NOT assumptions about what's adjacent.** Copy the exact lines from the file, not from memory.

3. **After writing old_string, verify with a dry-run:**
   ```bash
   cd ~/.hermes/hermes-agent && git checkout -- <file>
   python3 -c "
   with open('<file>') as f:
       content = f.read()
   old = '''<your_old_string>'''
   print('MATCH' if old in content else 'NO MATCH')
   "
   ```

4. **If the patch SKIPs during apply, DON'T assume it was already applied.** The `SKIP` output means `old in content` returned False — the upstream code doesn't contain your old_string. This is almost always an old_string construction error, not a pre-applied patch.

## Why This Bites

The `_do_patch` function has two layers:
1. **Check pattern** (grep) — detects if the fix IS present
2. **Python heredoc** (`old in content`) — detects if the fix CAN be applied

When the check pattern fails (fix not found), `_do_patch` runs the Python heredoc. If `old in content` is False, it prints `SKIP` and returns **error code 1**, which `_do_patch` reports as "failed". But in some edge cases (triple-quote content with odd characters), the SKIP might be silently swallowed and reported as success — leaving the file unmodified but the status check showing the check pattern as still missing.
