---
name: hermes-agent-development
description: "Develop, patch, and contribute to Hermes Agent source code — apply upstream PRs, run tests, understand project layout."
version: 1.0.0
author: Hermes Agent
license: MIT
platforms: [macos, linux]
metadata:
  hermes:
    tags: [hermes, development, pr, patch, testing]
    related_skills: [hermes-agent, hermes-patch-management]
---

# Hermes Agent Development

Working with the Hermes Agent source code — merging upstream PRs into a local fork, running tests, and understanding the project layout.

## Triggers

- User asks to merge/apply a PR, pull upstream changes, or patch the hermes-agent source
- User wants to run hermes-agent tests
- User asks about hermes-agent project structure or development workflow

## Key Paths

| Item | Path |
|------|------|
| Source root | `~/.hermes/hermes-agent/` |
| Tests | `tests/` (pytest, ~3000 tests) |
| Agent loop | `run_agent.py` (AIAgent class) |
| Providers | `hermes_cli/providers.py` |
| CLI commands | `hermes_cli/commands.py` |
| Gateway | `gateway/run.py` |

For full project layout, load the `hermes-agent` bundled skill.

## PR Merge Workflow

### 1. Confirm repo state

```bash
cd ~/.hermes/hermes-agent
git log --oneline -5
git branch --show-current
git remote -v
```

### 2. Fetch PR details

```bash
cd ~/.hermes/hermes-agent
gh pr view <NUMBER> --repo NousResearch/hermes-agent --json title,body,state,files,headRefName,baseRefName
```

### 3. Get the diff

```bash
gh pr diff <NUMBER> --repo NousResearch/hermes-agent
```

Review the changed files and the nature of changes before applying.

### 4. Apply changes with the `patch` tool

Use `patch` (mode='replace') for each modified file. Prefer targeted edits over bulk file rewrites.

**⚠️ PITFALL — diverged codebase**: The local `main` branch is a fork and may have accumulated changes beyond the PR's base branch. The `old_string` you provide to `patch`:

- May exist in a **different location** than expected (line numbers shifted)
- May exist in a **slightly different form** (e.g. a test case gained a docstring or extra setup lines since the PR was authored)
- The `patch` tool uses fuzzy matching (9 strategies) — it WILL find a close-enough match, potentially at the wrong location

**Mitigation**: After EVERY `patch` call on a test file or code file:
1. Immediately `read_file` the area around the change to verify correct placement
2. Check that adjacent code (nearby tests, nearby functions) was NOT inadvertently modified
3. Run `git diff` to review the full delta
4. If anything looks off, use `patch` again to restore the original, then adjust `old_string`

### 5. Verify — run relevant tests

```bash
cd ~/.hermes/hermes-agent
python -m pytest -q tests/<path>/test_<file>.py -k "<TestClassName>" -v --tb=short
```

Use `-k` to filter to the specific test class, not the whole file (faster, less noise).

### 6. Final review

```bash
git diff
```

Confirm only the intended files changed, and the diff matches the PR's intent.

## Running Tests

```bash
# Full suite (slow)
python -m pytest tests/ -o 'addopts=' -q

# Specific test file
python -m pytest tests/tools/test_foo.py -v --tb=short

# Specific test class or method
python -m pytest tests/run_agent/test_run_agent.py -k "TestMaxTokensParam" -v --tb=short
```

- Tests auto-redirect `HERMES_HOME` to temp dirs — safe to run without side effects
- Use `-o 'addopts='` to clear any baked-in pytest flags from `pyproject.toml`

## Project Layout (Quick Reference)

```
hermes-agent/
├── run_agent.py          # AIAgent — core conversation loop
├── model_tools.py        # Tool discovery and dispatch
├── toolsets.py           # Toolset definitions
├── cli.py                # Interactive CLI (HermesCLI)
├── hermes_state.py       # SQLite session store
├── agent/                # Prompt, compression, memory, model routing, skills
├── hermes_cli/           # CLI subcommands, config, setup, slash commands
├── tools/                # One file per tool
├── gateway/              # Messaging gateway + platform adapters
├── cron/                 # Job scheduler
├── tests/                # pytest suite
```

Full details: load `hermes-agent` bundled skill.

## References

- `references/pr-37152-minimax.md` — Pitfall case study: patch tool fuzzy matching on diverged codebase (PR #37152)
