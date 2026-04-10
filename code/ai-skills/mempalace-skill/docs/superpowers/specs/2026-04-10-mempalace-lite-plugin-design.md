# mempalace-lite Plugin Design

**Date:** 2026-04-10
**Status:** Approved
**Author:** fenrir

## Summary

Package the five existing pure-prompt MemPalace skills into a Claude Code plugin called `mempalace-lite`. The plugin adds slash commands, pure-bash auto-save hooks, and a manifest — no Python, no ChromaDB, no external dependencies.

## Background

The upstream `mempalace` plugin (`../mempalace/.claude-plugin/`) ships as a full Claude Code plugin backed by a Python package with ChromaDB. This project already contains five skills that reimplement all of that as pure prompt instructions operating on the filesystem. This spec describes how to wrap those skills into a distributable plugin.

## Design Decisions

| Decision | Choice | Rationale |
|---|---|---|
| Plugin name | `mempalace-lite` | Avoids conflict with upstream `mempalace`. "Lite" conveys no-Python, no-ChromaDB. |
| Author | `milla-jovovich` | Same upstream author — this is a derivative, not a fork. |
| Structure | `.claude-plugin/` at repo root | Standard Claude Code plugin layout. Works with both local install and marketplace. |
| Slash commands | Yes, all 5 | Thin delegators to skills. Better discoverability via `/mempalace-lite:*`. |
| Hooks | Pure bash (Stop + PreCompact) | Auto-save without Python. Stop counts messages (threshold 15), PreCompact always saves. |
| MCP servers | None | All operations are direct file I/O by the model. |

## Plugin Structure

```
mempalace-skill/
├── .claude-plugin/
│   ├── plugin.json
│   ├── marketplace.json
│   ├── README.md
│   ├── commands/
│   │   ├── init.md
│   │   ├── mine.md
│   │   ├── search.md
│   │   ├── status.md
│   │   └── help.md
│   ├── hooks/
│   │   ├── hooks.json
│   │   ├── stop-hook.sh
│   │   └── precompact-hook.sh
│   └── skills/
│       ├── mempalace-init/
│       │   ├── SKILL.md
│       │   └── references/common-english-words.md
│       ├── mempalace-mine/
│       │   ├── SKILL.md
│       │   └── references/
│       │       ├── general-extractor.md
│       │       ├── chunking-rules.md
│       │       └── room-routing.md
│       ├── mempalace-search/
│       │   ├── SKILL.md
│       │   └── references/
│       │       ├── palace-layout.md
│       │       └── ripgrep-recipes.md
│       ├── mempalace-status/
│       │   └── SKILL.md
│       └── mempalace-help/
│           └── SKILL.md
├── CLAUDE.md
└── .claude/settings.json
```

## Component Specs

### 1. plugin.json

```json
{
  "name": "mempalace-lite",
  "version": "1.0.0",
  "description": "Pure-prompt MemPalace — AI memory system with zero dependencies. Stores verbatim memories as markdown files, searchable via ripgrep. No Python, no ChromaDB, no API keys.",
  "author": {
    "name": "milla-jovovich"
  },
  "license": "MIT",
  "commands": [],
  "keywords": [
    "memory",
    "ai",
    "palace",
    "search",
    "filesystem",
    "prompt"
  ],
  "repository": "https://github.com/milla-jovovich/mempalace"
}
```

No `mcpServers` field. Commands and skills are auto-discovered from their directories.

### 2. marketplace.json

```json
{
  "name": "mempalace-lite",
  "owner": {
    "name": "milla-jovovich",
    "url": "https://github.com/milla-jovovich"
  },
  "plugins": [
    {
      "name": "mempalace-lite",
      "source": "./.claude-plugin",
      "description": "Pure-prompt AI memory — no Python, no ChromaDB. Stores verbatim memories as markdown files under ~/.mempalace/.",
      "version": "1.0.0"
    }
  ]
}
```

### 3. Slash Commands (commands/*.md)

Each command is a thin delegator. Template:

```markdown
---
description: <short description>
argument-hint: <optional — what to pass>
allowed-tools: <same as target skill>
---

Invoke the mempalace-<name> skill (using the Skill tool), then follow its instructions.
```

| File | Description | Argument hint |
|---|---|---|
| `init.md` | Set up MemPalace — interactive onboarding, creates palace directory tree | (none) |
| `mine.md` | Mine projects and conversations into the MemPalace | Path to project or conversation directory |
| `search.md` | Search your memories across the MemPalace | Search query, optionally with wing/room filters |
| `status.md` | Show palace overview — wings, rooms, drawer counts | (none) |
| `help.md` | Show MemPalace help — skills, architecture, getting started | (none) |

### 4. Hooks

#### hooks.json

```json
{
  "description": "MemPalace auto-save hooks (pure bash, no Python)",
  "hooks": {
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "bash ${CLAUDE_PLUGIN_ROOT}/hooks/stop-hook.sh"
          }
        ]
      }
    ],
    "PreCompact": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "bash ${CLAUDE_PLUGIN_ROOT}/hooks/precompact-hook.sh"
          }
        ]
      }
    ]
  }
}
```

#### stop-hook.sh

**Purpose:** Auto-save every 15 human messages.

**Algorithm:**

1. Read JSON from stdin using `jq`.
2. Extract `session_id`, `transcript_path`, and `stop_hook_active` from the input.
3. If `stop_hook_active` is `true`, output `{}` and exit (prevents infinite save loops).
4. If `transcript_path` is empty or the file doesn't exist, output `{}` and exit.
5. Count human messages in the transcript:
   - For JSONL transcripts: count lines containing `"role":"human"` or `"type":"human"`
   - Fallback: count lines starting with `> ` (markdown quote — user turns)
6. Load the last save count from `~/.mempalace/hook_state/<session_id>.last_save`. Default to 0 if not found.
7. If `(current_count - last_save_count) >= 15`:
   - Create `~/.mempalace/hook_state/` if needed
   - Write `current_count` to the state file
   - Output blocking JSON:
     ```json
     {
       "continue": false,
       "stopReason": "MemPalace auto-save: 15+ messages since last save. Please review what was discussed and use the mempalace-mine skill to save important conversation context to the palace."
     }
     ```
8. Otherwise output `{}`.

**Dependencies:** `jq` (for JSON parsing). If `jq` is not available, fall back to `grep`/`sed` parsing. The hook must never fail hard — if anything goes wrong, output `{}` and let the session continue.

**State directory:** `~/.mempalace/hook_state/` — one file per session, content is a single integer (the message count at last save).

#### precompact-hook.sh

**Purpose:** Emergency save before context compaction.

**Algorithm:**

1. Read JSON from stdin (consumed but not parsed — we don't need anything from it).
2. Always output:
   ```json
   {
     "continue": false,
     "stopReason": "MemPalace pre-compact save: Context is about to be compacted. Please review the conversation and use the mempalace-mine skill to save important context to the palace before compaction proceeds."
   }
   ```

This hook is unconditional because compaction means the AI is about to lose detailed context permanently. Every compaction event should trigger a save opportunity.

### 5. README.md

Plugin documentation covering:

- One-line description
- Prerequisites: bash, optionally `rg` and `jq`
- Installation: local (`claude plugin add`) and marketplace
- Available slash commands table
- Hook behavior explanation
- Link to the upstream mempalace for the full Python version

### 6. Skills (existing, moved)

The 12 existing files move from `skills/` to `.claude-plugin/skills/` with no content changes. All five skills are self-contained and already reference `~/.mempalace/` as the palace root.

### 7. CLAUDE.md Update

Update to reflect the plugin layout: `.claude-plugin/` as the root, note that skills are now under `.claude-plugin/skills/`, document the new commands and hooks.

## File Operations Summary

| Action | Files |
|---|---|
| **Move** (12 files) | `skills/*` → `.claude-plugin/skills/*` |
| **Create** (10 files) | plugin.json, marketplace.json, README.md, 5 commands, hooks.json, 2 hook scripts |
| **Update** (1 file) | CLAUDE.md |
| **Delete** (0 files) | Nothing deleted — old `skills/` dir becomes empty after move |

**Total new files:** 10
**Total moved files:** 12
**Net change:** +10 new files, same 12 skills relocated

## Installation

```bash
# Local
claude plugin add /path/to/mempalace-skill

# Marketplace (after publishing)
claude plugin marketplace add milla-jovovich/mempalace-lite
claude plugin install --scope user mempalace-lite
```

## Testing Plan

1. **Smoke test:** `claude plugin add .` from the repo root, verify `/mempalace-lite:help` works
2. **Skill trigger test:** each skill triggers from natural language (e.g., "search my palace for auth decisions")
3. **Hook test:** verify Stop hook counts messages and fires after 15, PreCompact always fires
4. **Init → Mine → Search round-trip:** full end-to-end flow with no Python installed
5. **Edge cases:** missing `jq` (hook fallback), missing `rg` (search fallback), empty palace

## Non-Goals

- No MCP server — all operations are direct file I/O by the model
- No Python dependency — the plugin must work on a fresh machine with only bash
- No AAAK dialect support — the upstream's experimental compression layer is out of scope for the lite version
- No knowledge graph — the upstream's SQLite-backed KG is replaced by flat drawer files and grep
