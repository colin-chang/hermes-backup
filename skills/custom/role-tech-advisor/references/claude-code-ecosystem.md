# Claude Code Ecosystem — Desktop GUI Wrappers & Performance Analysis

> Last updated: 2026-06-19
> Research session: Claude Code Desktop vs Codex Desktop comparison + third-party GUI catalog

## 1. Official Desktop Performance Issues (Root Cause)

### Context Bloat
- System prompt assembled from 30+ conditional modules (Drew Breunig, Apr 2026 analysis)
- GitHub Issue #49593: system prompt bloat 40-50% between v2.1.92→v2.1.100 (startup 8%→22% of context window)
- GitHub Issue #48050: system prompt tripled after v2.1.101, causing 3x quota consumption
- **Per-turn overhead: ~6-8k tokens** confirmed on bare default config (paulalbert1, #51809)

### Hidden Safety Injections
- GrowthBook remote flag injections at startup (hidden classifiers, sentinel warnings, prompt injection detection)
- Identity constraints and guardrails consume invisible context tokens

### Electron Overhead
- Official Desktop is Electron-based → 30s+ first-response latency (GitHub Issue #61898)
- IPC overhead between Electron renderer and Node.js backend

### Interaction Model Mismatch
- Claude Code is conversation-first; adding GUI doesn't improve conversation, just adds visual overhead
- Codex Desktop is delegation-first; GUI genuinely enables multi-thread review, diffs, annotate, mobile access

## 2. Third-Party Claude Code GUI Wrappers

### Active (2026)

| Tool | Stars | Last Push | Tech | License | Notes |
|------|-------|-----------|------|---------|-------|
| **Clarc** (ttnear/Clarc) | 289 | 2026-06-02 | SwiftUI (native macOS) | Apache 2.0 | ✅ Spawns real `claude` CLI underneath; 5.6MB download; CLAUDE.md/skills/MCP preserved |
| **claude-code-gui** (markes76/claude-code-gui) | 28 | 2026-03-12 | Electron + React + TS | — | Comprehensive: CLAUDE.md, MCP, skills, agents, hooks management |
| **laborany** (laborany/laborany) | 69 | 2026-05-16 | TypeScript | — | 基于 Claude Code，支持飞书/QQ 远程调度 |

### Stale / Inactive

| Tool | Stars | Last Push | Notes |
|------|-------|-----------|-------|
| **Opcode** (winfunc/opcode, formerly Claudia) | 22K | 2025-10-16 | 8-month hiatus; 1705 forks but no active maintainer fork found; Tauri 2 + Rust + React; was the gold standard |

### NOT Suitable for "Thin GUI Shell" Use Case

These are full replacements that manage their own context/prompts, NOT thin wrappers around Claude Code CLI:
- Cursor (IDE, own context system)
- Cline (VS Code extension, own agent logic)
- Nimbalyst (multi-agent workspace, own context)
- OpenCode (standalone agent framework)

## 3. Decision Framework

**If user wants:** A desktop GUI that preserves Claude Code CLI's context engineering (CLAUDE.md, skills, MCP, hooks)
→ **Clarc** — only active native macOS option that spawns real `claude` CLI

**If user wants:** Full desktop experience with best agent performance (don't care about preserving CLI configs)
→ **Codex Desktop** or **Cursor** — both outperform official Claude Code Desktop

**If user is on Linux/Windows:**
→ Options are limited; claude-code-gui (Electron) or run Claude Code CLI in a modern terminal emulator (Warp, iTerm2)

## 4. Research Methodology Notes

- Used `dokobot read --local` with Google search to discover URLs, then direct read of key pages
- GitHub API (`curl api.github.com/repos/...`) for maintenance status verification
- Cross-referenced: GitHub issues (#49593, #48050, #61898, #51809), Drew Breunig blog, Tarek Alaaddin comparison, Iwo Szapar feature matrix
