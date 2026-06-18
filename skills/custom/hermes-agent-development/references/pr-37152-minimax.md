# PR #37152 — MiniMax max_completion_tokens Fix

## What the PR does

MiniMax chat-completions models reject the legacy `max_tokens` key and require `max_completion_tokens` (same as OpenAI gpt-4o/o-series/gpt-5+). The fix adds model-name-based detection in `AIAgent._max_tokens_param()` — when `model.lower().startswith("minimax")`, use `max_completion_tokens`.

Previously only direct OpenAI, Azure OpenAI, and GitHub Copilot URLs triggered this behavior.

## Pitfall: patch tool fuzzy match on diverged codebase

### What happened

The PR was authored against upstream `main` at a point where `test_returns_max_completion_tokens_for_github_copilot_path` was a simple 3-line test:

```python
def test_returns_max_completion_tokens_for_github_copilot_path(self, agent):
    result = agent._max_tokens_param(4096)
    assert result == {"max_completion_tokens": 4096}
```

But the local fork had already evolved — the same test had gained a docstring and an explicit `base_url`:

```python
def test_returns_max_completion_tokens_for_github_copilot_path(self, agent):
    """Detect Copilot by hostname even when the configured URL includes a path."""
    agent.base_url = "https://api.githubcopilot.com/chat/completions"
    result = agent._max_tokens_param(4096)
    assert result == {"max_completion_tokens": 4096}
```

When the `patch` tool's `old_string` (from the PR diff) was provided, fuzzy matching found the **function signature + `result` + `assert`** triplet and replaced MORE context than intended — stripping the docstring and changing `base_url`.

### Detection and fix

After patching, `read_file` revealed the Copilot test had been altered. A follow-up `patch` restored it:

```python
# Restore
old_string: 'def test_returns_max_completion_tokens_for_github_copilot_path(self, agent):\n        agent.base_url = "https://api.githubcopilot.com"\n        agent.model = "claude-sonnet-4"\n        result = agent._max_tokens_param(4096)'
new_string: 'def test_returns_max_completion_tokens_for_github_copilot_path(self, agent):\n        """Detect Copilot by hostname even when the configured URL includes a path."""\n        agent.base_url = "https://api.githubcopilot.com/chat/completions"\n        result = agent._max_tokens_param(4096)'
```

### Rule

**After every `patch` on a test file, immediately `read_file` the ±20 lines around the change.** Check that adjacent functions/tests were not modified. If local code has diverged from PR base, expect fuzzy matching to be over-eager.

## Test results

```
tests/run_agent/test_run_agent.py::TestMaxTokensParam - 9 passed ✅
```

The two new tests:

1. `test_returns_max_completion_tokens_for_minimax_models` — `MiniMax-M3` with custom router URL → `max_completion_tokens`
2. `test_returns_max_completion_tokens_for_minimax_models_case_insensitive` — `minimax-m2.7` (lowercase) → still detected → `max_completion_tokens`
