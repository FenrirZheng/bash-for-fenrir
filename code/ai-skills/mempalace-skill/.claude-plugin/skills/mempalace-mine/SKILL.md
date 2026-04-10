---
name: mempalace-mine
description: Mine a project directory or conversation export into the user's MemPalace — scan files, chunk them verbatim, route each chunk to the right wing/room, and write drawer markdown files under ~/.mempalace/palace/. Use whenever the user says they want to mine, ingest, index, file, store, or add content to their memory palace; when they mention mempalace mine, mempalace ingest, or dumping a project/conversation into the palace; when they point at a directory and say "add this to my memory"; or when they want to capture a chat export from Claude/ChatGPT/Slack into mempalace. Three modes: project (code and docs), convos (chat exports with exchange-pair chunking), and general (auto-classifies into decisions, milestones, problems, preferences, emotions). No Python CLI is required — this skill does all the filesystem work directly.
allowed-tools: Bash, Read, Write, Edit, Glob, Grep
---

# MemPalace Mine

You are filing verbatim memories into the palace. "Verbatim" is the whole point — never summarize, never paraphrase, never decide what's worth remembering. You store everything. The structure (wings/rooms/drawers) is what makes it findable later, not the quality of the extraction.

This skill replaces the upstream `mempalace mine` CLI entirely with filesystem operations. Everything below is runtime instruction for you, the model.

## Prerequisites

Before mining, confirm the palace exists:

```bash
test -f ~/.mempalace/config.yaml && echo "palace OK" || echo "no palace"
```

If there's no palace, tell the user to run the `mempalace-init` skill first and stop. Do not try to auto-initialize from inside this skill — mining should fail loud when the palace is missing, because silent auto-creation would hide the real onboarding flow.

Read `~/.mempalace/config.yaml` to get the `wings` list and `mode`. Read `~/.mempalace/entities.md` so you can link names in content back to known people during routing.

## Step 1 — Ask what to mine

If the user's prompt already specifies a path and a mode, skip the question and acknowledge what you understood in one line. Otherwise ask three things in a single message:

1. **What to mine** — directory path. (Default: current working directory.)
2. **What kind of source** — pick one:
   - `project` — code, docs, notes (the default when the directory has source files)
   - `convos` — conversation exports from Claude, ChatGPT, Slack, or plain-text transcripts (the default when the directory has `.md`/`.txt`/`.json`/`.jsonl` that look like chat logs)
   - `general` — auto-classify conversation content into decisions, milestones, problems, preferences, emotions
3. **Which wing to file under** — if the user has a `mempalace.yaml` in the project root, read it. Otherwise ask which wing from `~/.mempalace/config.yaml`'s wing list should own these memories.

Offer to detect mode automatically: if the target path has `.py`/`.js`/`.go`/`.rs`/etc. files under it, default to `project`. If it has mostly `.md`/`.txt` files with lines starting with `>` (quote markers), default to `convos`.

## Step 2 — Read the project config (project mode only)

If the target is a project directory, check for `mempalace.yaml` (fall back to legacy `mempal.yaml`) at the project root:

```yaml
wing: my_project
rooms:
  - name: backend
    description: Server-side code
    keywords: [api, server, database, auth]
  - name: frontend
    description: Client UI code
    keywords: [react, component, ui, css]
  - name: docs
    description: Documentation and notes
    keywords: [readme, tutorial, guide]
```

If no `mempalace.yaml` exists, offer to generate a reasonable one by scanning the top-level directory structure: one room per top-level subdirectory that contains source files, plus a `general` room as fallback. Confirm with the user before writing the file.

The wing from `mempalace.yaml` **overrides** the wing the user picked in Step 1, unless the user passed an explicit `--wing` flag-equivalent in their prompt. Tell the user which wing ended up winning and why.

## Step 3 — Scan the filesystem

Walk the target directory using `Glob` or `Bash` (`fdfind` if available, otherwise `find`). Apply these filters in order — every filter here is load-bearing and mirrors `mempalace/miner.py` behavior:

### Skip directories entirely

```
.git, node_modules, __pycache__, .venv, venv, env, dist, build, .next,
coverage, .mempalace, .ruff_cache, .mypy_cache, .pytest_cache, .cache,
.tox, .nox, .idea, .vscode, .ipynb_checkpoints, .eggs, htmlcov, target
```

Also skip any directory ending in `.egg-info`.

### Respect .gitignore

At each directory level, if there's a `.gitignore`, load it and apply the rules. Matching semantics:

- Patterns ending in `/` match directories only
- Patterns starting with `/` are anchored to the `.gitignore` location
- Patterns starting with `!` negate an earlier match
- `**` matches any number of path segments
- Otherwise, patterns are globbed against individual path components
- Nested `.gitignore`s apply to their subtree
- Last matching rule wins (a negation at the end re-includes a path)

The user can pass a list of `include_ignored` paths that override `.gitignore` for explicit force-includes.

### File-level filters

Only keep files whose extension is in this readable set (for `project` mode):

```
.txt, .md, .py, .js, .ts, .jsx, .tsx, .json, .yaml, .yml, .html, .css,
.java, .go, .rs, .rb, .sh, .csv, .sql, .toml
```

For `convos` mode, the readable set is narrower: `.txt, .md, .json, .jsonl`.

Always skip these filenames regardless of extension: `mempalace.yaml`, `mempalace.yml`, `mempal.yaml`, `mempal.yml`, `.gitignore`, `package-lock.json`.

Skip every file that is:

- A symlink (prevents following links to `/dev/urandom`, network mounts, etc.)
- Larger than 10 MB (skip with a brief note in the summary — big files usually aren't the interesting ones)
- Empty, or smaller than 50 characters after stripping whitespace

Skip files whose name ends in `.meta.json` (these are sidecar metadata, not conversation content).

## Step 4 — Chunk each file

For each surviving file, read its content and split into drawer-sized chunks. The chunking algorithm differs by mode.

### Project mode chunking

Constants (from `miner.py`):

- `CHUNK_SIZE = 800` characters per drawer
- `CHUNK_OVERLAP = 100` characters overlap between adjacent drawers
- `MIN_CHUNK_SIZE = 50` characters (skip shorter chunks)

Algorithm:

```
start = 0
chunk_index = 0
while start < len(content):
    end = min(start + 800, len(content))
    if end < len(content):
        # Try to break on a paragraph boundary (\n\n)
        pb = content.rfind("\n\n", start, end)
        if pb > start + 400:   # at least halfway through the window
            end = pb
        else:
            # Fall back to a line boundary
            lb = content.rfind("\n", start, end)
            if lb > start + 400:
                end = lb
    chunk = content[start:end].strip()
    if len(chunk) >= 50:
        emit(chunk, chunk_index)
        chunk_index += 1
    start = end - 100 if end < len(content) else end
```

The 100-char overlap preserves sentence boundaries across chunks. The 400-char "halfway through" threshold prevents tiny chunks when paragraph breaks land early in the window.

### Convos mode chunking (exchange pairs)

Conversation logs have a characteristic structure: user turns prefixed with `>` (quote marker), followed by the AI/other-party response in following lines until the next `>` or a `---` separator.

Algorithm:

1. Split content into lines.
2. Count lines starting with `>`. If fewer than 3, **fall back to paragraph chunking** (see below).
3. Otherwise, walk lines. When you hit a `>` line:
   - Capture it as `user_turn`.
   - Read the next lines until you see another `>` or `---` or end-of-file.
   - Keep at most the first 8 non-empty lines as `ai_response`.
   - Emit `f"{user_turn}\n{' '.join(ai_response)}"` as one chunk.
4. Skip chunks shorter than `MIN_CHUNK_SIZE = 30` characters (note: convos use 30, not 50).

**Paragraph fallback**: split on `\n\n`. If there are no paragraph breaks but the file has more than 20 newlines, group every 25 lines into a chunk. Skip chunks below 30 characters.

### General mode chunking (auto-classification)

This mode classifies content into five memory types and stores each as its own drawer. Read `references/general-extractor.md` for the full classification rules — the short version is:

- **decisions** — "we chose X because Y", "switched to X", "decided against Y"
- **milestones** — "launched", "shipped", "completed", dated achievements
- **problems** — "broken", "failed", "crash", "stuck" + a workaround or fix
- **preferences** — "I prefer X", "always use X over Y", personal tastes
- **emotions** — emotional context, "frustrated", "excited", "worried about X"

Each extracted memory becomes a drawer with `memory_type` equal to the classification. The room name for these drawers is the `memory_type` directly, not the usual room detection.

### Normalization

Before chunking any file in convos mode, normalize the format to plain text. The upstream `normalize.py` handles:

- JSONL chat exports (Claude Code, ChatGPT) — extract `role` and `content` fields, render as `> <user text>` / `<assistant response>` lines
- JSON with a `messages` array — same treatment
- Plain `.txt`/`.md` — pass through unchanged

If the file can't be parsed as JSON, treat it as plain text. Don't fail the whole mine because one file has a weird format — skip it with a note and continue.

## Step 5 — Route each chunk to a room

For each chunk, decide which room under the wing it belongs to. The routing priority (mirrors `detect_room` in `miner.py`):

1. **Folder path match** — split the file's path relative to the project root. For each path component (excluding the filename), check if it matches a room `name` or any room keyword. First hit wins.
2. **Filename match** — check if any room name appears in the filename (or vice versa).
3. **Content keyword scoring** — for each room, count how many times its keywords (and its own name) appear in the first 2000 characters of the chunk. The highest-scoring room wins, as long as the score is > 0.
4. **Fallback** — file under a `general` room.

For convos mode, step 1 and 2 don't apply (conversations don't have project structure). Use the content keyword scoring against these topic keywords:

```yaml
technical:   [code, python, function, bug, error, api, database, server, deploy, git, test, debug, refactor]
architecture: [architecture, design, pattern, structure, schema, interface, module, component, service, layer]
planning:    [plan, roadmap, milestone, deadline, priority, sprint, backlog, scope, requirement, spec]
decisions:   [decided, chose, picked, switched, migrated, replaced, trade-off, alternative, option, approach]
problems:    [problem, issue, broken, failed, crash, stuck, workaround, fix, solved, resolved]
```

The highest-scoring topic wins; fall back to `general` if all scores are zero.

If the target room doesn't exist yet under the wing, create it now: `~/.mempalace/palace/<wing>/<room>/drawers/` and write a `_room.md` metadata file with the room name and any keywords you used for routing. Don't pre-create rooms before you need them.

## Step 6 — Write drawer files

Each drawer is a single markdown file under `~/.mempalace/palace/<wing>/<room>/drawers/` with YAML frontmatter for metadata and the verbatim content below.

### Drawer ID

```
id = f"drawer_{wing}_{room}_{sha256(source_file + str(chunk_index))[:24]}"
```

This makes drawer IDs stable across re-mines — the same file and chunk produce the same ID, so re-mining updates the drawer in place instead of creating duplicates. The filename is `<id>.md`.

### Drawer file format

```markdown
---
id: drawer_projects_backend_a1b2c3d4e5f67890abcd1234
wing: projects
room: backend
source_file: /home/user/code/myapp/backend/auth.py
chunk_index: 3
added_by: mempalace-mine
filed_at: 2026-04-10T12:34:56Z
source_mtime: 1712745296.0
ingest_mode: project
---

<verbatim chunk content goes here — exactly as it appeared in the source file>
```

Always store the content verbatim. Do not strip comments, do not collapse whitespace beyond the initial `strip()` on the chunk, do not fix typos. The raw text is the whole value of the palace.

### Idempotency

Before writing a drawer, check whether a file with the same ID already exists:

- If it doesn't exist, write it.
- If it exists and the `source_mtime` in its frontmatter matches the current `os.path.getmtime()` of the source file, **skip** (the file is unchanged — this chunk is already filed).
- If the source file's mtime is newer than the stored `source_mtime`, **overwrite** the drawer with the fresh content and update `source_mtime` and `filed_at`.

This is the `file_already_mined(check_mtime=True)` behavior from `palace.py`. For convos mode, use `check_mtime=False` — conversation exports don't change, so existence alone is enough to skip.

### Add-by agent tagging

Set `added_by` to `mempalace-mine`. If the user explicitly identified themselves via an `--agent` flag equivalent in their prompt (e.g., "mine this as user 'alice'"), use that instead. This mirrors how the upstream CLI let callers tag their mines.

## Step 7 — Summarize and suggest

After mining finishes, produce a terse status report:

```
MemPalace Mine — done
  Wing:      projects
  Files:     127 scanned, 118 processed, 9 skipped (already filed)
  Drawers:   1,482 new
  By room:
    backend      52 files → 680 drawers
    frontend     41 files → 530 drawers
    docs         25 files → 272 drawers
  Skipped:
    3 files > 10 MB
    2 symlinks
    4 binary (unknown extension)

  Next:
    - Search what you just filed: mempalace-search "auth decisions"
    - See the full state: mempalace-status
```

Keep it compact. Do not list every filed drawer.

## Optional — split mega-files

If the scan reveals any single source file larger than 500 KB but under the 10 MB hard cap, suggest splitting it before mining:

*"`<filename>` is 1.2 MB and will produce ~1,500 drawers from a single source. Want me to offer a dry-run split preview first?"*

If the user says yes, show them roughly how many chunks the file will produce under the 800-char chunking and give them the option to proceed or skip that file. Do not actually modify the source file on disk.

## When things go wrong

- **Unreadable file**: log the path + error, continue with the rest.
- **Can't write to palace dir**: stop immediately and report the exact path that failed. Most likely cause is bad permissions on `~/.mempalace/` or the disk is full.
- **Chunking produces zero chunks for a file**: that means the file was entirely whitespace or below `MIN_CHUNK_SIZE`. Skip it silently — it doesn't belong in the skipped summary unless the user asked for verbose output.
- **Conflict with an existing drawer where the content differs but `source_mtime` says unchanged**: this usually means the source file was edited but its mtime wasn't bumped (e.g., git checkout preserved mtime). Overwrite the drawer anyway, and add a note to the report: *"Replaced N drawers whose content drifted from source despite unchanged mtime."*

## Reference material

- `references/general-extractor.md` — full classification rules for `general` mode
- `references/chunking-rules.md` — detailed chunking algorithm with edge cases
- `references/room-routing.md` — examples of file-to-room routing

Read these only when you hit an edge case the SKILL.md body doesn't cover. For a standard mine, the body is self-contained.
