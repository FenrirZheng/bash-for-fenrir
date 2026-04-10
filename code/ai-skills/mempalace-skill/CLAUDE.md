# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Purpose

This repo contains a **pure-prompt reimplementation of MemPalace** as five standalone Claude Code skills. The upstream `../mempalace` is a Python+ChromaDB plugin; this version replaces all of that with filesystem-based storage and prompt instructions that Claude executes directly. No Python program, no ChromaDB, no embeddings — the model is the runtime.

The upstream `../mempalace` is available read-only via `.claude/settings.json` → `permissions.additionalDirectories` for reference.

## Architecture Decision

The upstream Python code was translated into skill prompts, not wrapped. Key transformations:

| Upstream (Python) | This repo (Skills) |
|---|---|
| ChromaDB vector storage | Markdown files in `~/.mempalace/palace/<wing>/<room>/drawers/` |
| Semantic embedding search | `rg` keyword search + Claude semantic reasoning |
| `miner.py` chunking + routing | Prompt instructions for the same algorithm (800-char chunks, room routing) |
| `general_extractor.py` regex classification | Regex marker sets transcribed into `references/general-extractor.md` |
| `onboarding.py` interactive CLI | `mempalace-init` skill with conversational interview flow |
| MCP server (19 tools) | Not ported — replaced by direct file I/O in each skill |
| Hooks (Stop/PreCompact auto-save) | Pure-bash hooks in `.claude-plugin/hooks/` — auto-save every 15 messages + pre-compact save |

## Plugin Layout

```
.claude-plugin/
├── plugin.json                              # Plugin manifest (name, version, author)
├── marketplace.json                         # Marketplace listing metadata
├── README.md                                # Plugin documentation
├── commands/
│   ├── init.md                              # /mempalace-lite:init → mempalace-init skill
│   ├── mine.md                              # /mempalace-lite:mine → mempalace-mine skill
│   ├── search.md                            # /mempalace-lite:search → mempalace-search skill
│   ├── status.md                            # /mempalace-lite:status → mempalace-status skill
│   └── help.md                              # /mempalace-lite:help → mempalace-help skill
├── hooks/
│   ├── hooks.json                           # Hook registration (Stop + PreCompact events)
│   ├── stop-hook.sh                         # Auto-save every 15 human messages
│   └── precompact-hook.sh                   # Emergency save before context compaction
└── skills/
    ├── mempalace-init/
    │   ├── SKILL.md                         # Onboarding: mode, people, projects, wings → writes config
    │   └── references/
    │       └── common-english-words.md      # Ambiguity check for name-vs-word collisions
    ├── mempalace-mine/
    │   ├── SKILL.md                         # Scan → chunk → route → write drawers
    │   └── references/
    │       ├── general-extractor.md         # 5-type classification rules with regex marker sets
    │       ├── chunking-rules.md            # Detailed chunking algorithm + edge cases
    │       └── room-routing.md              # File-to-room routing examples
    ├── mempalace-search/
    │   ├── SKILL.md                         # rg search → read candidates → judge → present
    │   └── references/
    │       ├── palace-layout.md             # Filesystem spec for the palace tree
    │       └── ripgrep-recipes.md           # Common rg invocations for palace search
    ├── mempalace-status/
    │   └── SKILL.md                         # Count wings/rooms/drawers, show compact summary
    └── mempalace-help/
        └── SKILL.md                         # Overview of all skills, architecture, getting started
```

Each SKILL.md is self-contained for its flow. References are only read when the main body doesn't cover an edge case — progressive disclosure. Slash commands in `commands/` are thin delegators that invoke the matching skill via the Skill tool.

### Hooks

- **Stop hook** (`stop-hook.sh`): Fires after each assistant turn. Counts human messages in the session transcript. After 15 new messages since the last save, blocks to trigger a palace save. State tracked in `~/.mempalace/hook_state/<session_id>.last_save`.
- **PreCompact hook** (`precompact-hook.sh`): Fires before context compaction. Always blocks — compaction permanently loses detailed context, so every compaction event triggers a save opportunity.

Both hooks are pure bash. `jq` is preferred for JSON parsing but sed-based fallback ensures they work without it. Hooks never fail hard — any error outputs `{}` and lets the session continue.

## Palace Filesystem Spec

Created by `mempalace-init`, populated by `mempalace-mine`, queried by `mempalace-search`:

```
~/.mempalace/
├── config.yaml              # mode, palace_path, wings list
├── identity.md              # L0 — always-loaded identity (~100 tokens)
├── critical_facts.md        # L1 — essential story (~500-800 tokens)
├── entities.md              # people, projects, aliases
└── palace/
    └── <wing>/
        ├── _wing.md         # wing metadata
        └── <room>/          # created lazily by mine
            ├── _room.md     # room metadata + keywords
            └── drawers/
                └── <id>.md  # YAML frontmatter + verbatim content
```

Drawer ID format: `drawer_<wing>_<room>_<sha256(source_file + chunk_index)[:24]>`.

## Key Design Principles

- **Verbatim storage only.** Never summarize, paraphrase, or edit drawer content. The benchmark score (96.6% R@5) was from raw mode.
- **Idempotent mining.** Same source file + same chunk index → same drawer ID. Re-mining updates changed drawers, skips unchanged ones.
- **Lazy room creation.** Rooms are created when the first drawer is routed to them, not pre-created during init.
- **Name sanitization.** Wing/room/person names: 1-128 chars, alphanumeric start, no `..`, `/`, `\`, or null bytes.

## Working With the Upstream Source

- `../mempalace` is read-only reference. Edits go in this repo only.
- The Python source files that were transcribed: `miner.py`, `convo_miner.py`, `general_extractor.py`, `searcher.py`, `onboarding.py`, `config.py`, `palace.py`, `layers.py`.
- The upstream instruction files (`../mempalace/mempalace/instructions/*.md`) are no longer the source of truth — this repo's SKILL.md files are authoritative now.
