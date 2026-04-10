---
name: mempalace-help
description: Show comprehensive MemPalace help — what skills are available, the palace architecture, the filesystem layout, and quick-start guidance. Use whenever the user asks about mempalace capabilities, says "mempalace help", "what can mempalace do", "how does mempalace work", "what are the mempalace commands", or mentions wanting to understand the memory palace system. Also trigger when the user seems confused about which skill to use.
allowed-tools: Bash, Read
---

# MemPalace Help

MemPalace is a filesystem-based AI memory palace. It stores verbatim memories as markdown files organized into wings (projects/people), rooms (topics), and drawers (individual memories). No Python program, no external database, no embeddings — Claude reads and writes the files directly.

## Skills

| Skill | Trigger phrases | What it does |
|-------|-----------------|--------------|
| `mempalace-init` | "set up mempalace", "initialize palace" | Interactive onboarding: asks about your mode, people, projects, wings. Creates `~/.mempalace/` with config, identity, entity registry, and palace skeleton. |
| `mempalace-mine` | "mine this project", "add to palace", "ingest into mempalace" | Scans a directory, chunks files verbatim, routes chunks to the right wing/room, writes drawer `.md` files. Three modes: `project` (code+docs), `convos` (chat exports), `general` (auto-classify decisions/milestones/problems). |
| `mempalace-search` | "search mempalace", "what did we decide", "find in palace" | Grep-based search across drawer files with wing/room filtering. Returns verbatim drawer content with source attribution. |
| `mempalace-status` | "palace status", "how many memories" | Counts wings/rooms/drawers, shows storage size, checks identity and entity file health. One compact summary. |
| `mempalace-help` | "mempalace help", "what can mempalace do" | This screen. |

## Architecture

```
Wings (projects, people, life areas)
  └── Rooms (topics within a wing)
       └── Drawers (verbatim memories — one chunk per file)
```

**Halls** connect rooms within a wing (navigated by browsing rooms under the same wing directory).
**Tunnels** connect rooms across wings (discovered by searching keywords that appear in multiple wings).

The upstream Python version stored all of this in ChromaDB with vector embeddings. This skill-based version stores it as plain markdown files — Claude's own reading and reasoning replace the vector index.

## Filesystem layout

```
~/.mempalace/
├── config.yaml              # mode (work/personal/combo), wings list
├── identity.md              # L0 — "who is this AI + user" (~100 tokens)
├── critical_facts.md        # L1 — essential story (~500-800 tokens)
├── entities.md              # people, projects, aliases
└── palace/
    └── <wing>/
        ├── _wing.md         # wing metadata
        └── <room>/
            ├── _room.md     # room metadata + keywords
            └── drawers/
                └── <id>.md  # verbatim drawer (YAML frontmatter + raw content)
```

### Drawer format

```markdown
---
id: drawer_projects_backend_a1b2c3d4e5f6
wing: projects
room: backend
source_file: /home/user/code/app/auth.py
chunk_index: 3
filed_at: 2026-04-10T12:34:56Z
ingest_mode: project
---

<verbatim content from the source file>
```

## The 4-Layer Memory Stack

This model of progressive memory loading comes from the upstream `layers.py`:

| Layer | What it contains | When to load |
|-------|------------------|-------------|
| L0 — Identity | `~/.mempalace/identity.md` (~100 tokens) | Always — describes who the user is, key people |
| L1 — Essential Story | `~/.mempalace/critical_facts.md` (~500-800 tokens) | Always — bootstrapped at init, enriched by mining |
| L2 — On-Demand | Browse drawers by wing/room | When a specific topic comes up in conversation |
| L3 — Deep Search | Grep across all drawers | When the user asks a specific question |

Wake-up cost is ~600-900 tokens (L0+L1), leaving 95%+ of context free for the conversation.

## Getting started

1. **Initialize**: use the `mempalace-init` skill to create your palace.
2. **Mine**: use `mempalace-mine` to add content from projects or chat exports.
3. **Search**: use `mempalace-search` to find what you stored.
4. **Check status**: use `mempalace-status` to see how big your palace is.

## Mining modes

| Mode | Best for | How chunking works |
|------|----------|-------------------|
| `project` | Code, docs, config files | 800-char chunks at paragraph/line boundaries |
| `convos` | Chat exports (Claude, ChatGPT, Slack) | Q+A exchange pairs (one user turn + response = one drawer) |
| `general` | Auto-classification of text | Classifies into decisions, preferences, milestones, problems, emotional |

## Key principles

- **Store everything, summarize nothing.** Every drawer holds the exact text from the source. No LLM decides what's worth remembering.
- **Structure makes it findable.** Wings/rooms/drawers give Claude a navigable map. Grep + reasoning replaces vector search.
- **Local only, no cost.** Everything lives in `~/.mempalace/` on the user's machine. No API calls, no cloud, no subscription.
- **Idempotent mining.** Re-mining the same directory updates changed drawers and skips unchanged ones. Safe to run repeatedly.
