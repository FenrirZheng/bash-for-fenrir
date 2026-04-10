# Room Routing — Examples and Edge Cases

This reference shows how files get routed to rooms in practice. The SKILL.md body has the four-step priority rules; this file works through examples so you can make good decisions on ambiguous cases.

## The priority rules, restated

Given a file path, its content, and the list of rooms from `mempalace.yaml`, decide which room the file belongs to:

1. **Folder path match** — any path component (except the filename itself) matches a room name or any room keyword
2. **Filename match** — the room name appears inside the filename, or vice versa
3. **Content keyword scoring** — count keyword hits in the first 2000 chars of content; highest score wins if > 0
4. **Fallback** — `general`

## Room definition structure

Each room in `mempalace.yaml` looks like:

```yaml
rooms:
  - name: backend
    description: Server-side code and APIs
    keywords: [api, server, database, auth, flask, fastapi, route]
  - name: frontend
    description: React UI components
    keywords: [react, component, ui, css, tsx, jsx, hook]
  - name: docs
    description: Documentation
    keywords: [readme, tutorial, guide, documentation]
```

Keywords are the routing signal. `description` is for humans and doesn't affect routing.

## Worked examples

### Example 1 — Folder path match

**File**: `backend/auth/login.py`
**Rooms**: `backend`, `frontend`, `docs`

Path components (excluding filename): `backend`, `auth`

Check each component against each room:
- `backend` == `backend` ✓ — room is `backend`

Done at priority 1. Don't bother reading the file.

### Example 2 — Folder path match via keyword

**File**: `api/users/routes.py`
**Rooms**: `backend` (keywords: `[api, server, route]`), `frontend`, `docs`

Path components: `api`, `users`

- Check `api` against `backend` keywords: `api` is in `[api, server, route]` ✓ — room is `backend`

Routed to `backend` by keyword match on the path component.

### Example 3 — Filename match

**File**: `tutorials/docs_intro.md`
**Rooms**: `backend`, `frontend`, `docs`

Path components: `tutorials`. None match any room name or keyword.

Move to priority 2. Filename `docs_intro` contains `docs` — room is `docs`.

### Example 4 — Content keyword scoring

**File**: `random_notes.md` at project root
**Rooms**: `backend` (keywords: `[api, server, database]`), `frontend` (keywords: `[react, component, css]`), `docs`

Path components: none relevant (file is at root).
Filename: `random_notes` matches no room.

Read first 2000 chars of content:
> "I was thinking about the React components we need for the new dashboard. The state management is going to be tricky — we'll need a context provider and maybe a reducer. Also need to think about the CSS layout..."

Score each room by counting keyword occurrences:
- `backend`: `api` (0) + `server` (0) + `database` (0) = 0
- `frontend`: `react` (1) + `component` (1) + `css` (1) = 3
- `docs`: `readme` (0) + `tutorial` (0) + `guide` (0) + `documentation` (0) = 0

Winner: `frontend` with score 3.

### Example 5 — Fallback

**File**: `LICENSE.txt`
**Rooms**: `backend`, `frontend`, `docs`

Path components: none.
Filename: `license` matches no room.
Content: legal text with no keyword hits.

All scores zero → fallback to `general`. The room is created on-demand if it doesn't exist yet.

### Example 6 — Ambiguous content

**File**: `notes/decision-log.md`
**Rooms**: `backend`, `decisions` (keywords: `[decided, chose, picked, trade-off]`), `docs`

Path components: `notes`. No match (unless a room has `notes` keyword).
Filename: `decision-log` contains `decision` → matches `decisions` room. Done.

Note how the filename match beats content scoring — that's deliberate. Filenames are a stronger signal than content because the user chose them.

## Edge cases

### Multiple rooms match on path

If two rooms both match a path component, the **first** room in the `mempalace.yaml` list wins. Order matters. Tell the user to reorder their room list if they want different tiebreaking.

### Partial substring matches

Priority 1 does substring matching with `part == candidate or candidate in part or part in candidate`. So:

- Path component `backends` matches room `backend` ✓
- Path component `docs-v2` matches room `docs` ✓
- Path component `frontend-old` matches room `frontend` ✓

This is deliberately loose to catch naming variations.

### Case sensitivity

All path and filename comparisons are lowercased before matching. `Backend/` matches `backend` room. Keywords in `mempalace.yaml` should be lowercased for consistency.

### Files at project root

Files at the project root have no path components to match (path components excludes the filename). They skip straight to priority 2 (filename match) or priority 3 (content scoring).

### Empty keyword list

If a room has no `keywords`, only its `name` is used for scoring in priority 3. Rooms without keywords are harder to hit — the user should add keywords if routing misses them.

### No `mempalace.yaml`

If the project has no config file, prompt the user to generate one. A good auto-generation heuristic: one room per top-level subdirectory, with the subdirectory name as the room name and its common filenames as keywords. Show the generated config for approval before writing.

## Convos mode routing

Conversation mining doesn't have project structure (no folders, no filenames that matter). It uses content-only scoring against a fixed topic keyword set:

| Room | Keywords |
|------|----------|
| technical | code, python, function, bug, error, api, database, server, deploy, git, test, debug, refactor |
| architecture | architecture, design, pattern, structure, schema, interface, module, component, service, layer |
| planning | plan, roadmap, milestone, deadline, priority, sprint, backlog, scope, requirement, spec |
| decisions | decided, chose, picked, switched, migrated, replaced, trade-off, alternative, option, approach |
| problems | problem, issue, broken, failed, crash, stuck, workaround, fix, solved, resolved |

Score each conversation chunk against all five, pick the highest-scoring room. Tie → `technical` wins (arbitrary but consistent). All zero → `general` fallback.

## General mode routing

In `general` mode, the room name IS the `memory_type` value from the classifier — one of `decision`, `preference`, `milestone`, `problem`, `emotional`. No content scoring needed. See `general-extractor.md` for the classification algorithm.

## Tips for good routing

- **Start with few rooms, add more later.** Too many rooms make routing noisy and rooms end up with 1-2 drawers each. Aim for 3–7 rooms per wing.
- **Use distinctive keywords.** `api` is better than `backend` because `backend` is also the room name (redundant). Use keywords the room `name` doesn't already cover.
- **Check the mine summary.** If 90% of files end up in `general`, your keywords aren't hitting. Rebalance and re-mine.
- **Don't route by file extension alone.** `.py` files can be backend, frontend (JSX via a script), or docs (doctest). Let content and path drive routing, not extension.
