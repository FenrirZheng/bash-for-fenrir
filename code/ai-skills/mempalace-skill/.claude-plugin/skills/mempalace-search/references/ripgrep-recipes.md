# Ripgrep Recipes for MemPalace Search

Practical `rg` invocations for searching drawer files. Use these as starting points and adapt to the query at hand.

## Basic — single keyword, whole palace

```bash
rg --type md --ignore-case --max-count 3 --with-filename --line-number \
   'postgres' \
   ~/.mempalace/palace/
```

- `--type md` keeps output clean (drawers are `.md` files)
- `--max-count 3` caps hits per file so a verbose drawer doesn't flood
- `--with-filename --line-number` makes results parseable

## Multi-keyword AND (all must match)

Ripgrep doesn't have native AND-across-lines. Two approaches:

**Approach 1 — intersect file lists**

```bash
files_a=$(rg --type md --files-with-matches 'postgres' ~/.mempalace/palace/)
files_b=$(rg --type md --files-with-matches 'migration' ~/.mempalace/palace/)
comm -12 <(echo "$files_a" | sort) <(echo "$files_b" | sort)
```

**Approach 2 — regex lookahead** (requires `--pcre2`)

```bash
rg --pcre2 --type md '(?=.*postgres)(?=.*migration)' ~/.mempalace/palace/
```

Approach 1 is more portable and handles multi-line drawers better. Use approach 2 only when you want matches on the same line.

## Multi-keyword OR (any match)

```bash
rg --type md -e 'postgres' -e 'mongodb' -e 'mysql' ~/.mempalace/palace/
```

The `-e` flag lets you pass multiple patterns; ripgrep matches any.

## Phrase search

```bash
rg --type md '"we decided to switch"' ~/.mempalace/palace/
```

Quoting preserves the space literally. For fuzzier phrase matching, use word boundaries:

```bash
rg --type md '\bwe decided\b.*\bswitch\b' ~/.mempalace/palace/
```

## Scope by wing or room

```bash
# Only the projects wing
rg --type md 'auth' ~/.mempalace/palace/projects/

# Only the decisions room in projects
rg --type md 'auth' ~/.mempalace/palace/projects/decisions/drawers/

# Multiple specific rooms
rg --type md 'auth' \
   ~/.mempalace/palace/projects/decisions/drawers/ \
   ~/.mempalace/palace/projects/problems/drawers/
```

## Date-range filtering

Ripgrep can't filter by mtime directly, but you can combine with `find`:

```bash
# Drawers filed in the last 30 days
find ~/.mempalace/palace/ -name "drawer_*.md" -mtime -30 -print0 | \
  xargs -0 rg --type md 'auth'
```

For frontmatter-based date filtering (more accurate than mtime because drawer files can be touched without the memory actually being new), ripgrep the `filed_at` field:

```bash
rg --type md --files-without-match '^filed_at: 202[56]-' ~/.mempalace/palace/
```

## Count hits without full output

```bash
rg --type md --count 'postgres' ~/.mempalace/palace/
```

Useful for telling the user how many drawers mention a keyword without listing each.

## Case-sensitive for proper nouns

```bash
rg --type md 'MemPalace' ~/.mempalace/palace/
```

Drop `--ignore-case` when the query is a proper noun that would collide with common words (e.g., "Lantern" the project vs "lantern" in casual speech).

## Boundary anchoring

Match whole words only:

```bash
rg --type md --word-regexp 'auth' ~/.mempalace/palace/
```

This hits `auth` but not `authentication`, `authorize`, `author`. Use when the user is searching for a specific acronym or symbol name.

## Exclude metadata files

Drawer content lives in `drawer_*.md` files. Wing and room metadata live in `_wing.md` and `_room.md`. To exclude metadata:

```bash
rg --type md --glob '!_wing.md' --glob '!_room.md' 'auth' ~/.mempalace/palace/
```

Or scope the search to `drawers/` subdirectories only:

```bash
rg --type md 'auth' ~/.mempalace/palace/*/*/drawers/
```

## Pretty output for the user

When displaying results, ripgrep's `--heading` + `--line-number` combo is readable:

```bash
rg --type md --ignore-case --max-count 3 \
   --heading --line-number --context 2 \
   'auth decision' \
   ~/.mempalace/palace/
```

`--context 2` adds two lines before and after each match — good for showing the surrounding verbatim text.

## Falling back when ripgrep is missing

If `rg` isn't installed:

```bash
find ~/.mempalace/palace/ -name "*.md" -print0 | \
  xargs -0 grep -l -i 'postgres'
```

This is slower but works everywhere. If the palace has < 1000 drawers, the speed difference is imperceptible.

## Performance tips

- **Scope narrowly.** Always pass the most specific directory you can. `palace/projects/decisions/drawers/` is 100x faster than `palace/` on a large palace.
- **Use `--files-with-matches` first** when you only need to know which drawers match, not the content. Then `Read` the ones you need.
- **Cache ripgrep's index** — wait, ripgrep doesn't cache. But it's fast enough that caching isn't needed for most palaces.
- **Parallel keyword searches.** Spawn multiple `rg` processes concurrently and intersect file lists in the shell; this is faster than a single regex alternation for many keywords.
