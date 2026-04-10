---
name: mempalace-status
description: Show the current state of the user's MemPalace — wing and room counts, total drawers, storage size, and identity/facts status. Use whenever the user says "palace status", "mempalace status", "show my palace", "how big is my memory", "how many memories do I have", "what's in my palace", or asks a question about the current shape of their memory palace. Also trigger when a just-completed mine operation recommends checking status.
allowed-tools: Bash, Read, Glob, Grep
---

# MemPalace Status

Display a compact, informative snapshot of the palace. Think of this as `git status` for the memory palace — just the facts, no commentary.

## Step 1 — Check palace exists

```bash
test -f ~/.mempalace/config.yaml && echo "ok" || echo "no palace"
```

If there's no palace, respond with a single line:

*"No palace found at ~/.mempalace/. Run the `mempalace-init` skill to set one up."*

Then stop.

## Step 2 — Gather counts

Run these in parallel via Bash calls:

### Config

```bash
cat ~/.mempalace/config.yaml
```

Extract `mode` and `wings` list.

### Wings

```bash
ls -1 ~/.mempalace/palace/ 2>/dev/null
```

### Rooms per wing + drawer counts

For each wing directory, count rooms and drawers. The most efficient single command:

```bash
for wing in ~/.mempalace/palace/*/; do
  wing_name=$(basename "$wing")
  rooms=0
  drawers=0
  for room in "$wing"*/; do
    [ -d "$room/drawers" ] || continue
    rooms=$((rooms + 1))
    count=$(ls -1 "$room/drawers/" 2>/dev/null | grep -c '^drawer_')
    drawers=$((drawers + count))
  done
  echo "$wing_name: $rooms rooms, $drawers drawers"
done
```

### Storage size

```bash
du -sh ~/.mempalace/ 2>/dev/null | cut -f1
```

### Identity and facts status

```bash
wc -c ~/.mempalace/identity.md ~/.mempalace/critical_facts.md ~/.mempalace/entities.md 2>/dev/null
```

Report whether each file exists and its approximate token count (size / 4).

## Step 3 — Present the output

Use this compact format — concise counts, no prose padding:

```
MemPalace Status
  Mode:    combo
  Wings:   4
  Rooms:   12
  Drawers: 3,847
  Size:    4.2M

  By wing:
    projects   5 rooms   2,104 drawers
    family     3 rooms     891 drawers
    work       2 rooms     742 drawers
    health     2 rooms     110 drawers

  Files:
    identity.md        428 bytes (~107 tokens)  ok
    critical_facts.md  1.2K (~300 tokens)       ok
    entities.md        892 bytes (~223 tokens)   ok
```

If the entities file or any metadata file is missing, say `missing` instead of `ok`. If there are wings with zero rooms (only `_wing.md` present), note them separately:

```
  Empty wings (not yet mined):
    research
```

## Step 4 — Suggest one next action

Based on the current state, suggest exactly one action. Pick the most useful:

| Condition | Suggestion |
|-----------|------------|
| Zero drawers across all wings | *"Your palace is empty. Use the `mempalace-mine` skill to add content."* |
| Drawers exist but `identity.md` is missing | *"Your palace has data but no identity file. Run `mempalace-init` to create one."* |
| Drawers exist but `entities.md` is missing | *"Consider running `mempalace-init` to set up your entity registry for better search."* |
| One wing has 90%+ of all drawers | *"Most memories are in the `<wing>` wing. Consider mining additional projects/conversations into other wings."* |
| Everything healthy | *"Use `mempalace-search` to query your memories."* |

Do not offer multiple suggestions. One line, then stop.

## When things go wrong

- **Partial palace** (config exists but palace/ directory is empty): report exactly what's present and what's missing; suggest re-running init.
- **Corrupted drawer files** (files in drawers/ that don't have valid YAML frontmatter): count them as drawers but add a note: *"N drawers have missing or invalid frontmatter."*
- **Permissions issues**: report the exact path that's unreadable and suggest `chmod`.
