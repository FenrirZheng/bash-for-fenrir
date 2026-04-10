---
name: mempalace-init
description: Bootstrap a fresh MemPalace — a filesystem-based AI memory palace under ~/.mempalace/. Use whenever the user says they want to set up mempalace, initialize a memory palace, create their palace, start fresh, do mempalace onboarding, or asks "how do I get started with mempalace". Also trigger when the user mentions they want AI memory but have nothing set up yet. Runs an interactive onboarding that asks about their mode (work/personal/combo), important people, projects, and wings, then scaffolds ~/.mempalace/{config.yaml,identity.md,critical_facts.md,entities.md,palace/<wing>/} with no Python dependency at all.
allowed-tools: Bash, Read, Write, Edit, Glob, Grep
---

# MemPalace Init

You are setting up a brand-new memory palace for the user. The palace is entirely filesystem-based: wings are directories, rooms are sub-directories, and drawers (verbatim memories) are markdown files. There is **no Python program**, no ChromaDB, no embeddings, no CLI. You — the model — are the whole runtime. Everything you do here is plain file I/O.

The goal is to end this flow with:

- A valid palace directory tree at `~/.mempalace/palace/<wing>/<room>/drawers/`
- A `~/.mempalace/config.yaml` capturing the chosen wings and mode
- A `~/.mempalace/identity.md` (L0 — "who is this AI + user", ~100 tokens)
- A `~/.mempalace/critical_facts.md` (L1 — essential story bootstrap, enriched later by mining)
- A `~/.mempalace/entities.md` (people, projects, aliases — used by later skills for entity linking)

The palace is the user's brain outside the session. Treat the setup like a short interview, not a form. Explain the palace concept in one or two sentences up front, then ask questions conversationally.

## Why this matters

Every conversation the user has with an AI disappears when the session ends. The palace captures verbatim memories and organizes them so Claude can find them later by grepping. Unlike summarization approaches that ask an LLM to decide what's worth remembering, this palace **stores everything**. The structure (wings → rooms → drawers) gives Claude a navigable map instead of a flat search index. See the [Architecture overview](#architecture) section for the full layout.

## Preconditions check

Before asking anything, run these three checks in parallel with Bash and report the results to the user in one line each:

1. `ls -la ~/.mempalace 2>&1 | head -20` — does a palace already exist? If `~/.mempalace/config.yaml` is present, **stop and ask the user** whether they want to (a) keep the existing palace and skip init, (b) reinitialize (which you'll do by renaming the old one to `~/.mempalace.bak.<timestamp>` rather than deleting), or (c) add new wings to the existing palace.
2. `which rg` and `which fd` (or `which fdfind`) — these aren't strictly required, but future `mempalace-search` and `mempalace-mine` skills benefit from them. Just note their presence or absence.
3. `df -h ~ | tail -1` — confirm there's free space in the home directory. A palace is usually a few MB unless the user mines huge codebases; just sanity-check that the disk isn't full.

Do not abort on missing `rg`/`fd`. They're nice-to-have.

## Interview flow

Conduct the onboarding as a conversation. Don't dump all questions at once — ask, wait for the answer, move on. Offer the defaults in square brackets so the user can press enter to accept.

### Step 1 — Mode

Ask: *"How will you use MemPalace? (1) Work — projects, clients, decisions  (2) Personal — family, health, reflections  (3) Both — combined personal and professional"*.

Store the answer as one of `work`, `personal`, or `combo`. This drives the default wing list in Step 4.

### Step 2 — People

Ask for the important people in the user's life (for `personal` or `combo`) and/or in their work (for `work` or `combo`). Collect name + relationship. Example prompts:

- Personal: *"Who are the important people in your personal life? Give me name and relationship, one per line. Examples: 'Riley, daughter', 'Devon, partner'. Say 'done' when finished."*
- Work: *"Who are the colleagues, clients, or collaborators you'd want to find in your notes later? Give me name and role. Say 'done' when finished."*

After each name, ask about nicknames with: *"Any nickname for &lt;name&gt;? (press enter to skip)"*. This matters because later mining will need to link "Alex" and "Al" to the same person.

Build two structures in memory:

```yaml
people:
  - name: Riley
    relationship: daughter
    context: personal
  - name: Ben
    relationship: co-founder
    context: work
aliases:
  Al: Alex
```

### Step 3 — Projects

Skip this step if the user picked `personal` mode. Otherwise ask: *"What are your main projects? These help the palace distinguish project names (e.g. 'Lantern' the project) from the same word in casual speech. Say 'done' when finished."*

Collect a simple list of strings: `projects: ["Lantern", "MemPalace"]`.

### Step 4 — Wings

Offer the mode-specific defaults. The suggestions come from the original `onboarding.py` defaults:

| Mode | Default wings |
|------|---------------|
| work | projects, clients, team, decisions, research |
| personal | family, health, creative, reflections, relationships |
| combo | family, work, health, creative, projects, reflections |

Say: *"Here are the suggested top-level wings for {mode} mode: {defaults}. Press enter to keep these, or give me your own comma-separated list."*

If the user adds custom wings, validate each name with the [name sanitization rules](#name-validation) below and reject any that fail. Show the reason.

### Step 5 — Auto-detect hint (optional)

Ask: *"Want me to scan a directory for additional names we might have missed? (yes/no, enter to skip)"*. If yes, ask for a directory path, then:

- Use `Grep` to look for capitalized words that appear multiple times in `.md`, `.txt`, `.py` files under that directory. This is a cheap approximation of the upstream `entity_detector.py`.
- Present candidates with their frequency: *"Found 5 additional name candidates: Sarah (12 mentions), Alex (8), ..."*.
- For each candidate the user accepts, ask for relationship/role and context (personal/work). Append to `people:`.

Skip this step silently if the user declines or if no obvious candidates emerge.

### Step 6 — Ambiguity warning

Before finalizing, scan the collected `people` list against common English words (see `references/common-english-words.md` — read it only if you need to double-check a specific name). If any person's first name is also a common word (e.g., "Hope", "Rose", "Art"), warn the user:

*"Heads up — 'Rose' is also a common English word. When searching later, I'll check context to decide whether it's the person or the noun. You can override this by using her full name in searches."*

## Write the files

After the interview, write these files. Use `Write` for each — do not cat-heredoc through Bash. Run a `mkdir -p ~/.mempalace/palace` first via Bash if the directory doesn't exist.

### `~/.mempalace/config.yaml`

```yaml
mode: <work|personal|combo>
palace_path: ~/.mempalace/palace
wings:
  - <wing1>
  - <wing2>
created_at: <ISO8601 timestamp>
```

### `~/.mempalace/identity.md`

This is L0 — always loaded into context when the palace "wakes up". Keep it under ~100 tokens (~400 chars). Seed it from the interview answers. Template:

```markdown
# Identity

I am an AI assistant with a persistent memory palace for <user_name_if_known>.
Mode: <mode>
Traits: <leave blank for the user to fill in later>
Key people: <comma-list of top 3 people from the interview>
<if work mode> Projects: <comma-list of projects></if>
```

Tell the user after writing it: *"I've seeded ~/.mempalace/identity.md with your setup. Edit it any time — this file is always loaded when the palace wakes up, so keep it lean (~100 tokens)."*

### `~/.mempalace/critical_facts.md`

L1 — the "essential story". At init time this is just a bootstrap; the mining skill fills it in later. Template:

```markdown
# Critical Facts

## People (personal)
- **Riley** (RIL) — daughter
- **Devon** (DEV) — partner

## People (work)
- **Ben** (BEN) — co-founder

## Projects
- **Lantern**
- **MemPalace**

## Palace
Wings: family, work, health, creative
Mode: combo

*This file will be enriched after mining.*
```

### `~/.mempalace/entities.md`

Used by the mining and search skills to link name variants. Template:

```markdown
# Entity Registry

## People
- Riley [personal] — daughter
- Devon [personal] — partner (alias: D)
- Ben [work] — co-founder

## Projects
- Lantern
- MemPalace

## Aliases
D → Devon
Al → Alex
```

### Palace skeleton

For each wing, create `~/.mempalace/palace/<wing>/` and drop a `_wing.md` file with just the wing name and a one-line description the user can edit later. Example:

```markdown
---
wing: projects
created_at: 2026-04-10T12:00:00
---

Top-level wing for all project-related memories.
```

Do **not** pre-create rooms. Rooms are created on-demand by the `mempalace-mine` skill when it first encounters content that matches a new topic. Pre-creating them leads to empty directories that clutter the status output.

## Verification

After writing everything, run these checks in parallel and report a single-line summary:

1. `ls -la ~/.mempalace/` — confirm all top-level files exist
2. `ls -la ~/.mempalace/palace/` — confirm all wings were created
3. `wc -c ~/.mempalace/identity.md ~/.mempalace/critical_facts.md ~/.mempalace/entities.md` — confirm non-zero sizes

If any check fails, report the specific file path and the user can retry.

## Tell the user what's next

Finish with a short message explaining the next two actions, no more:

1. *"Mine a project or a conversation export: use the `mempalace-mine` skill and point it at a directory."*
2. *"Once there's something in the palace, search it with `mempalace-search`."*

Do **not** offer to do either of these yourself right now. Init is done; let the user drive the next step.

---

## Architecture

This is the layout you just created. Keep it in your head for future skill invocations:

```
~/.mempalace/
├── config.yaml              # palace config (mode, wings, palace_path)
├── identity.md              # L0 — always-loaded identity (~100 tokens)
├── critical_facts.md        # L1 — essential story (~500-800 tokens)
├── entities.md              # people/projects/aliases
└── palace/
    └── <wing>/              # top-level category (project/person/life-area)
        ├── _wing.md         # wing metadata
        └── <room>/          # sub-category created lazily by mine
            ├── _room.md     # room metadata + keywords
            └── drawers/
                └── <id>.md  # verbatim drawer files (created by mine)
```

Drawer files are markdown with YAML frontmatter. See the `mempalace-mine` skill's reference for the exact schema.

## Name validation

Wing names, room names, and person names must:

- Be 1–128 characters
- Start with an alphanumeric character
- Contain only `a-z`, `A-Z`, `0-9`, underscore, space, period, apostrophe, or hyphen
- Not contain `..`, `/`, `\`, or null bytes

Reject any name that fails these checks and tell the user which rule it broke.

## When things go wrong

- **`~/.mempalace/` already exists with data**: never silently overwrite. Rename the old directory to `~/.mempalace.bak.<unix_timestamp>` and tell the user where it went.
- **User cancels mid-interview**: don't write any files. Tell them nothing was saved and they can run init again whenever they're ready.
- **Home directory isn't writable**: report the exact error from the failed `mkdir` and stop. Ask the user if they want to put the palace somewhere else — if so, write that path into `config.yaml` as `palace_path:` and create everything under that root instead of `~/.mempalace/palace/`.
