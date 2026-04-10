# Chunking Rules — Detailed Algorithm

This reference documents the exact chunking behavior for `mempalace-mine`. The SKILL.md body has the high-level pseudocode; this file captures edge cases, rationale, and worked examples. Read this file only when the body's pseudocode leaves a question unanswered.

## Why these constants

| Constant | Value | Reason |
|----------|-------|--------|
| `CHUNK_SIZE` | 800 chars | Small enough that each drawer carries a single coherent thought, large enough that most paragraphs fit in one chunk. Tuned empirically in the upstream benchmark suite. |
| `CHUNK_OVERLAP` | 100 chars | Prevents sentences from being cut in half between adjacent drawers. A search hit on "we switched to Postgres because" still finds the full reason even if it crosses a chunk boundary. |
| `MIN_CHUNK_SIZE` | 50 chars (project) / 30 chars (convos) | Below these thresholds, a drawer is almost always noise — a single variable name, a footer, a horizontal rule. Convos use a lower floor because individual Q+A exchanges can be short. |
| `MAX_FILE_SIZE` | 10 MB | Files larger than this are almost always binary, vendored, or machine-generated. Mining them wastes palace space. |
| Half-window | 400 chars | When looking for a paragraph or line break, only accept it if it's at least 400 chars into the 800-char window. Otherwise you end up with 60-char and 740-char neighbors. |

## Project mode — line-by-line pseudocode

```python
content = file.read_text(encoding="utf-8", errors="replace").strip()
if len(content) < 50:
    return []

chunks = []
start = 0
chunk_index = 0
CHUNK_SIZE = 800
OVERLAP = 100
MIN = 50

while start < len(content):
    end = min(start + CHUNK_SIZE, len(content))

    # Try to break at a natural boundary, but only in the second half of the window
    if end < len(content):
        pb = content.rfind("\n\n", start, end)   # paragraph break
        if pb > start + CHUNK_SIZE // 2:
            end = pb
        else:
            lb = content.rfind("\n", start, end)  # line break
            if lb > start + CHUNK_SIZE // 2:
                end = lb
        # If neither found, we cut mid-line — acceptable fallback

    chunk = content[start:end].strip()
    if len(chunk) >= MIN:
        chunks.append({"content": chunk, "chunk_index": chunk_index})
        chunk_index += 1

    start = end - OVERLAP if end < len(content) else end

return chunks
```

Edge cases:

- **Single short file (< 50 chars)**: return `[]`. The file produces zero drawers. The mine summary should not list it in "skipped" — it's just quiet no-op.
- **Single medium file (50–800 chars)**: one chunk, no overlap logic kicks in.
- **Long file with no paragraph breaks**: the `rfind` for `\n\n` returns `-1` (which compares less than `start + 400`), so we fall through to line-break logic. If that also fails, we cut at the hard 800-char boundary.
- **File ending mid-chunk**: the final iteration's `end == len(content)`, the loop condition `end < len(content)` is false, so no overlap is subtracted — we advance `start = end` and exit.
- **Content that starts with whitespace**: the initial `.strip()` removes it, so `len(content)` reflects trimmed length.

## Convos mode — exchange-pair chunking

The insight: chat logs have speaker turns. A "memory" isn't a raw paragraph; it's a question-and-answer pair. Chunking at exchange boundaries keeps Q+A together in one drawer so the search hit brings both halves.

### Detection

```python
lines = content.split("\n")
quote_lines = sum(1 for line in lines if line.strip().startswith(">"))

if quote_lines >= 3:
    return chunk_by_exchange(lines)
else:
    return chunk_by_paragraph(content)
```

The `>= 3` threshold distinguishes real chat logs from markdown files that happen to use occasional block quotes.

### Exchange algorithm

```python
chunks = []
i = 0
MIN = 30

while i < len(lines):
    line = lines[i]
    if line.strip().startswith(">"):
        user_turn = line.strip()
        i += 1

        ai_lines = []
        while i < len(lines):
            nxt = lines[i]
            if nxt.strip().startswith(">") or nxt.strip().startswith("---"):
                break
            if nxt.strip():
                ai_lines.append(nxt.strip())
            i += 1

        # Cap AI response at 8 lines to keep chunks compact
        ai_response = " ".join(ai_lines[:8])
        content = f"{user_turn}\n{ai_response}" if ai_response else user_turn

        if len(content.strip()) > MIN:
            chunks.append({"content": content, "chunk_index": len(chunks)})
    else:
        i += 1
```

Details:

- A `>` line without a following response still produces a chunk containing just the user turn, as long as it's longer than 30 chars. This captures orphan quotes.
- The AI response is joined with spaces — newlines within the response are collapsed. This is lossy for markdown formatting but acceptable because the original file is still on disk as the source.
- The 8-line cap prevents one super-long AI rant from dominating a drawer. Beyond 8 lines, the response is treated as "too much to fit in one memory" and the excess is dropped.

### Paragraph fallback

When there aren't enough `>` markers to trust exchange chunking:

```python
paragraphs = [p.strip() for p in content.split("\n\n") if p.strip()]

if len(paragraphs) <= 1 and content.count("\n") > 20:
    # Single-block transcript with many lines — group every 25 lines
    lines = content.split("\n")
    chunks = []
    for i in range(0, len(lines), 25):
        group = "\n".join(lines[i:i+25]).strip()
        if len(group) > 30:
            chunks.append({"content": group, "chunk_index": len(chunks)})
    return chunks

# Normal paragraph split
return [
    {"content": p, "chunk_index": i}
    for i, p in enumerate(paragraphs)
    if len(p) > 30
]
```

## Normalize pre-pass (convos only)

Before chunking, convo files may need normalization. The upstream `normalize.py` detects these formats:

### Claude Code JSONL exports

```jsonl
{"type": "user", "content": "let's write a migration"}
{"type": "assistant", "content": "Here's a draft..."}
```

Render as:

```
> let's write a migration
Here's a draft...
```

### ChatGPT JSON exports (conversations.json format)

Walk the `mapping` dict, collect messages in `create_time` order, extract `author.role` and `content.parts[0]`, render as:

```
> <user content>
<assistant content>
```

### OpenAI API format

```json
{"messages": [
  {"role": "user", "content": "..."},
  {"role": "assistant", "content": "..."}
]}
```

Same rendering.

### Slack exports

Slack uses `.json` files per channel with `user`, `text`, `ts` fields. Render each message as `[HH:MM] @user: text` and rely on paragraph fallback for chunking (Slack doesn't have clean Q+A turns).

### Plain text

Pass through unchanged.

### When in doubt

If you can't parse a file as JSON and it doesn't have recognizable chat markers, just read it as plain text and let the paragraph fallback handle it. Never fail the whole mine over one weird file — skip it and move on.

## Rationale for verbatim-only storage

The chunking rules preserve the source text character-for-character inside each chunk window. **Do not**:

- Paraphrase or summarize
- Fix typos, spelling, or grammar
- Remove comments from code
- Strip markdown formatting
- Collapse whitespace beyond the initial `.strip()`
- Redact identifiers or filenames

The palace's value is that it stores the exact words the user or their AI used. A search hit for "headache to migrate" must find the original phrase, not a cleaned-up version of it. The benchmark result (96.6% R@5 on LongMemEval) was achieved with raw verbatim mode — any transformation before storage degrades recall.
