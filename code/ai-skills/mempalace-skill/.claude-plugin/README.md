# mempalace-lite

Pure-prompt MemPalace — AI memory system with zero dependencies. Stores verbatim memories as markdown files, searchable via ripgrep. No Python, no ChromaDB, no API keys.

## Prerequisites

- **bash** (required)
- **jq** (optional — hooks use it for JSON parsing; falls back to sed)
- **rg** / ripgrep (optional — search is faster with ripgrep; falls back to grep)

## Installation

### Local

```bash
claude plugin add /path/to/mempalace-skill
```

### Marketplace (after publishing)

```bash
claude plugin marketplace add milla-jovovich/mempalace-lite
claude plugin install --scope user mempalace-lite
```

## Slash Commands

| Command | Description |
|---------|-------------|
| `/mempalace-lite:init` | Set up MemPalace — interactive onboarding, creates palace directory tree |
| `/mempalace-lite:mine` | Mine projects and conversations into the MemPalace |
| `/mempalace-lite:search` | Search your memories across the MemPalace |
| `/mempalace-lite:status` | Show palace overview — wings, rooms, drawer counts |
| `/mempalace-lite:help` | Show MemPalace help — skills, architecture, getting started |

## Hooks

### Stop Hook (auto-save)

Fires after every assistant turn. Counts human messages in the session transcript. After 15 messages since the last save, pauses to let the model save conversation context to the palace using the `mempalace-mine` skill.

State is tracked per-session in `~/.mempalace/hook_state/<session_id>.last_save`.

### PreCompact Hook (emergency save)

Fires before context compaction. Always pauses to let the model save context before the conversation history is compressed. This is the last chance to capture detailed conversation content.

## How It Works

MemPalace organizes memories into a directory tree:

```
~/.mempalace/palace/
+-- <wing>/          # Projects, people, life areas
    +-- <room>/      # Topics within a wing
        +-- drawers/
            +-- <id>.md  # Individual verbatim memories
```

- **Wings** are top-level categories (e.g., `projects`, `family`, `work`)
- **Rooms** are sub-categories within a wing (e.g., `backend`, `decisions`)
- **Drawers** are individual memories stored as markdown files with YAML frontmatter

Search uses ripgrep for keyword matching combined with Claude's semantic reasoning to find relevant memories.

## Full Version

For the Python-based version with ChromaDB vector search, see [mempalace](https://github.com/milla-jovovich/mempalace).
