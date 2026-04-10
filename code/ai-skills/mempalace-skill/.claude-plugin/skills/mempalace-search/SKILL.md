---
name: mempalace-search
description: Search the user's MemPalace for verbatim memories — drawer markdown files stored under ~/.mempalace/palace/. Use whenever the user wants to recall, look up, find, search, or retrieve something they previously mined into the palace; when they ask "what did we decide about X", "when did I last talk about Y", "find notes about Z", "search mempalace for...", "what's in my palace about..."; or any question that sounds like the user expects the answer to live in their memory palace rather than in the current session. Combines ripgrep-based keyword search with Claude-side semantic reasoning, then returns verbatim drawer content with wing/room/source attribution.
allowed-tools: Bash, Read, Glob, Grep
---

# MemPalace Search

You are looking through the user's filesystem palace for verbatim memories. There is no ChromaDB, no vector index, no embeddings — the palace is a directory tree of markdown files, and you search it by grepping for keywords and then reading the matching files with your own semantic judgment.

This skill replaces the upstream `mempalace search` CLI entirely with `rg` + file reading. The critical invariant: **return verbatim drawer content, never summarize**. The user mined the palace precisely to preserve exact wording.

## Prerequisites

Check the palace exists and has something in it:

```bash
test -d ~/.mempalace/palace && ls -1 ~/.mempalace/palace/ 2>/dev/null | wc -l
```

If there's no palace directory, tell the user to run `mempalace-init` first. If the palace exists but is empty (0 wings), tell the user to run `mempalace-mine` first. Don't try to synthesize results from nothing.

Read `~/.mempalace/entities.md` so you can expand name aliases during search (e.g., if the user searches for "D" and entities.md has `D → Devon`, actually search for both).

## Step 1 — Parse the query

Pull three things out of the user's prompt:

1. **Semantic query** — the core thing they're looking for. Keep natural language; don't pre-reduce to keywords yet.
2. **Wing filter** — if the user says "in my work wing" or "in the projects wing", note it. If they reference a project name that matches a wing, same deal.
3. **Room filter** — if they say "in the decisions room" or "in my backend notes", note it.

Example parse:

> *"What did we decide about auth in the Lantern project last month?"*

→ semantic query = `"what did we decide about auth"`, wing = `Lantern` (if present in palace), room = `decisions` (implied by "decide"), temporal hint = "last month".

Temporal hints like "last month", "recently", "before the launch" aren't directly filterable from file content, but they affect which results to surface — you can check the `filed_at` frontmatter of candidate drawers and prefer recent ones when the query implies recency.

## Step 2 — Discover the palace shape

Before searching, find out what wings and rooms actually exist. This is important for two reasons: (a) you can resolve vague wing names to real ones, and (b) you can tell the user if their filter points at a room that doesn't exist.

```bash
# List wings
ls -1 ~/.mempalace/palace/ 2>/dev/null

# List rooms within a specific wing
ls -1 ~/.mempalace/palace/<wing>/ 2>/dev/null | grep -v '^_'
```

The `grep -v '^_'` strips the `_wing.md` / `_room.md` metadata files — those aren't rooms themselves.

If the user's wing filter doesn't match any existing wing, try fuzzy matching (case-insensitive, substring). If still no match, tell them which wings exist and ask which one they meant.

## Step 3 — Extract search keywords

From the semantic query, pick 2–5 concrete keywords that are likely to appear verbatim in drawer content. Prefer:

- **Proper nouns** — names of people, projects, libraries, APIs ("Lantern", "Postgres", "Riley")
- **Distinctive verbs or adjectives** — "switched", "broken", "decided", "migrated"
- **Technical terms** — "auth", "middleware", "schema", "OAuth"

Avoid:

- Function words ("the", "about", "what")
- Generic verbs ("do", "have", "make")
- Words that appear in almost every drawer ("project", "code")

If the query has an alias that's in `entities.md`, include both the alias and the canonical name in the keyword list.

## Step 4 — Run ripgrep across the palace

Use ripgrep (`rg`) if available, otherwise fall back to `grep -r`. Ripgrep is strongly preferred — it's faster and handles large palaces gracefully.

### Base command

```bash
rg --type md \
   --ignore-case \
   --max-count 3 \
   --with-filename \
   --line-number \
   --heading \
   '<keyword>' \
   ~/.mempalace/palace/
```

Flags:
- `--type md` — only search markdown files (drawers, `_wing.md`, `_room.md`). Metadata files rarely match but that's fine.
- `--ignore-case` — unless the keyword is a proper noun the user typed in a specific case; then drop this flag.
- `--max-count 3` — at most 3 matches per file, so one verbose drawer doesn't dominate.
- `--with-filename --line-number --heading` — output is easier to parse.

### Wing/room filtering

If the user gave a wing or room filter, scope ripgrep to the matching directory:

```bash
# Wing filter
rg --type md 'query' ~/.mempalace/palace/<wing>/

# Wing + room filter
rg --type md 'query' ~/.mempalace/palace/<wing>/<room>/drawers/
```

### Multi-keyword search

For multiple keywords, run ripgrep once per keyword in parallel, then intersect the set of matching files. A drawer that hits **all** keywords is a stronger match than one hitting just one. You can also use `rg -e k1 -e k2` to union them.

### Regex when helpful

If the user's query is a phrase, try it as a literal regex with word boundaries:

```bash
rg --type md '\bauth decision\b' ~/.mempalace/palace/
```

This is faster than two separate keyword searches joined by an AND.

## Step 5 — Rank candidates

Ripgrep gives you a list of matching files. Rank them before reading:

1. **Multi-keyword matches first** — drawers matching all keywords > matching most > matching one.
2. **Exact phrase matches beat split matches** — `"switched to Postgres"` as contiguous text beats `"switched"` and `"Postgres"` in separate paragraphs.
3. **Room relevance boost** — if the user hinted at a room ("decisions", "problems"), boost drawers from that room.
4. **Recency boost for temporal queries** — if the user said "recently" or "last week", prefer drawers with newer `filed_at` frontmatter.

Take the top 5–10 candidates forward. More than that and the output becomes too verbose.

## Step 6 — Read and judge the candidates

Read each candidate drawer with `Read`. For each one, decide:

- **Is this actually relevant to the query?** Ripgrep matches keywords, not meaning. A drawer containing "we decided against using auth" is NOT a match for "when did we add auth" — opposite intent. Use your own judgment to filter out keyword-true, semantically-wrong hits.
- **Is this a duplicate?** If two drawers contain nearly identical content (common when chunking overlapping sections), keep the earlier `chunk_index` and drop the later one.
- **What's the frontmatter telling me?** Extract `wing`, `room`, `source_file`, `filed_at`, `chunk_index` for the response.

Discard drawers that ranked high on keyword count but fail semantic judgment. It's better to return 3 relevant hits than 10 noisy ones.

## Step 7 — Present results

Format the response for the user's consumption. Template:

```
## Results for: "<query>"
Filters: wing=<wing>, room=<room>  (if any)

### [1] projects / decisions
  Source: /home/user/code/myapp/ARCHITECTURE.md  (filed 2026-03-15)

  > We decided to switch from REST to GraphQL for the v2 API. The main
  > reason was the mobile team needed to batch requests and REST was
  > forcing 4-5 round trips per screen. Trade-off: harder to cache,
  > more complex schema, but latency dropped from 800ms to 120ms.

### [2] projects / decisions
  Source: /home/user/code/myapp/docs/v2-plan.md  (filed 2026-03-14)

  > Auth decision: JWT in httpOnly cookies, not localStorage. Caleb
  > pushed back on localStorage because of XSS risk. Refresh tokens
  > via /auth/refresh endpoint. Short JWT lifetime (15 min), long
  > refresh (7 days).

---
Found 2 matching drawers in 14ms.
```

### Key formatting rules

- **Show verbatim content as a block quote** (`> `) so it's visually distinct from your own words.
- **Always attribute** with `wing / room` header and `Source:` line.
- **Include `filed_at`** when helpful — users often care about "recent" vs "old" memories.
- **Do not summarize the drawer content** — show it exactly as stored.
- **Do not editorialize** the drawers with "I found this interesting..." or "this seems relevant because...". The user is reading their own memories; commentary is noise.

## Step 8 — Offer deeper navigation

At the end of the results, offer the user two or three short next steps based on what you found:

- **Drill deeper**: *"Want me to search within the `decisions` room specifically? Or narrow by wing?"*
- **Browse related**: *"These results all came from the `Lantern` wing. Want me to list other rooms in that wing?"*
- **No hits**: *"No drawers matched. Want me to try a broader keyword, or list the rooms in the `projects` wing so you can browse?"*

Keep these to one or two lines. Don't turn the search response into a conversation menu.

## When search returns nothing

Zero results usually means one of:

1. **Keywords don't appear verbatim.** The palace stores exact text. If the user asks about "the database migration" and their notes say "switching to Postgres", a keyword search on "database migration" won't hit. Suggest broader keywords or a topic-level browse.
2. **Filter too narrow.** The wing or room filter excluded everything. Retry without the filter to see if there are hits elsewhere.
3. **Content was never mined.** The memory doesn't exist in the palace because the source file was never fed to `mempalace-mine`. Tell the user where the palace thinks the content should be, and ask if they need to mine an additional source.

Always explain *why* the search returned nothing — not just "no results". The user needs enough information to decide whether to refine the query or go mine more data.

## Performance tips

- **Use ripgrep, not grep.** On a 10k-drawer palace, `rg` takes ~50ms; `grep -r` takes seconds.
- **Scope to `<wing>/<room>/drawers/`** when possible. Even with ripgrep, searching a 100-drawer subdirectory is instant.
- **Parallel keyword search** — run one `rg` per keyword concurrently and intersect results. This is faster than a single regex alternation for large palaces.
- **Read the frontmatter first when triaging**, not the body. The frontmatter is always in the first ~10 lines; you can judge relevance from wing/room/source before reading the whole drawer.

## Reference

- `references/palace-layout.md` — filesystem layout the search is navigating
- `references/ripgrep-recipes.md` — useful `rg` invocations beyond the basics
