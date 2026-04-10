# General Extractor — Memory Classification Rules

This reference explains how to classify free-form text into one of five memory types when the user invokes `mempalace-mine` with `general` mode. It's a direct transcription of the marker-based heuristics in the upstream `general_extractor.py` — no LLM calls, no embeddings, just pattern matching plus a light disambiguation pass.

Read this only when you're actually running `general` mode. For `project` and `convos` modes, ignore this file.

## Memory types

| Type | Captures |
|------|----------|
| **decision** | Choices made, approaches taken, trade-off discussions, configuration choices |
| **preference** | Personal style rules, "always X / never Y", coding conventions |
| **milestone** | Breakthroughs, first-time accomplishments, things that finally worked |
| **problem** | Bugs, failures, crashes, issues — may or may not be resolved |
| **emotional** | Feelings, vulnerability, relational content, `*emphasized*` text |

## Segmentation

Before classifying, split the input into segments you can score individually. Priority:

1. **Speaker-turn splitting** — if the text has 3+ lines matching any of these patterns, split into segments at each turn boundary:
   - `> ` (quoted user turn, lowercase `>` followed by space)
   - `Human:` / `User:` / `Q:` (case-insensitive)
   - `Assistant:` / `AI:` / `A:` / `Claude:` / `ChatGPT:` (case-insensitive)
2. **Paragraph splitting** — fall back to splitting on `\n\n`.
3. **Line-group chunking** — if there's only one giant paragraph but more than 20 lines, group every 25 lines.

Skip any segment shorter than 20 characters.

## Code-line filtering

Classification scores should be computed against **prose only**, not code. Strip these lines before scoring:

- Shell prompts (`^\s*[\$#]\s`)
- Common shell commands at line start: `cd source echo export pip npm git python bash curl wget mkdir rm cp mv ls cat grep find chmod sudo brew docker`
- Fenced code block markers (`^\s*\`\`\``) — toggle "in code block" state
- Code keywords at line start: `import from def class function const let var return`
- All-caps env vars (`^\s*[A-Z_]{2,}=`)
- Table rows (`^\s*\|`)
- Markdown rules (`^\s*-{2,}`)
- Bare brackets `{`, `}`, `[`, `]`
- Control flow keywords: `if for while try except elif else:`
- Method calls (`^\s*\w+\.\w+\(`)
- Assignment to attribute access (`^\s*\w+ = \w+\.\w+`)

Also treat any line with less than 40% alphabetic characters and more than 10 characters as code-like (this catches JSON, stack traces, hex dumps). If stripping leaves nothing, use the original text.

## Marker sets

Score each prose segment against these regex sets. Every match adds 1 to the score for that memory type. Regex is case-insensitive on the lowercased input.

### decision

```
\blet'?s (use|go with|try|pick|choose|switch to)\b
\bwe (should|decided|chose|went with|picked|settled on)\b
\bi'?m going (to|with)\b
\bbetter (to|than|approach|option|choice)\b
\binstead of\b
\brather than\b
\bthe reason (is|was|being)\b
\bbecause\b
\btrade-?off\b
\bpros and cons\b
\bover\b.*\bbecause\b
\barchitecture\b
\bapproach\b
\bstrategy\b
\bpattern\b
\bstack\b
\bframework\b
\binfrastructure\b
\bset (it |this )?to\b
\bconfigure\b
\bdefault\b
```

### preference

```
\bi prefer\b
\balways use\b
\bnever use\b
\bdon'?t (ever |like to )?(use|do|mock|stub|import)\b
\bi like (to|when|how)\b
\bi hate (when|how|it when)\b
\bplease (always|never|don'?t)\b
\bmy (rule|preference|style|convention) is\b
\bwe (always|never)\b
\bfunctional\b.*\bstyle\b
\bimperative\b
\bsnake_?case\b
\bcamel_?case\b
\btabs\b.*\bspaces\b
\bspaces\b.*\btabs\b
\buse\b.*\binstead of\b
```

### milestone

```
\bit works\b
\bit worked\b
\bgot it working\b
\bfixed\b
\bsolved\b
\bbreakthrough\b
\bfigured (it )?out\b
\bnailed it\b
\bcracked (it|the)\b
\bfinally\b
\bfirst time\b
\bfirst ever\b
\bnever (done|been|had) before\b
\bdiscovered\b
\brealized\b
\bfound (out|that)\b
\bturns out\b
\bthe key (is|was|insight)\b
\bthe trick (is|was)\b
\bnow i (understand|see|get it)\b
\bbuilt\b
\bcreated\b
\bimplemented\b
\bshipped\b
\blaunched\b
\bdeployed\b
\breleased\b
\bprototype\b
\bproof of concept\b
\bdemo\b
\bversion \d
\bv\d+\.\d+
\d+x (compression|faster|slower|better|improvement|reduction)
\d+% (reduction|improvement|faster|better|smaller)
```

### problem

```
\b(bug|error|crash|fail|broke|broken|issue|problem)\b
\bdoesn'?t work\b
\bnot working\b
\bwon'?t\b.*\bwork\b
\bkeeps? (failing|crashing|breaking|erroring)\b
\broot cause\b
\bthe (problem|issue|bug) (is|was)\b
\bturns out\b.*\b(was|because|due to)\b
\bthe fix (is|was)\b
\bworkaround\b
\bthat'?s why\b
\bthe reason it\b
\bfixed (it |the |by )\b
\bsolution (is|was)\b
\bresolved\b
\bpatched\b
\bthe answer (is|was)\b
\b(had|need) to\b.*\binstead\b
```

### emotional

```
\blove\b
\bscared\b
\bafraid\b
\bproud\b
\bhurt\b
\bhappy\b
\bsad\b
\bcry\b
\bcrying\b
\bmiss\b
\bsorry\b
\bgrateful\b
\bangry\b
\bworried\b
\blonely\b
\bbeautiful\b
\bamazing\b
\bwonderful\b
i feel
i'm scared
i love you
i'm sorry
i can't
i wish
i miss
i need
never told anyone
nobody knows
\*[^*]+\*          (emphasis markers — often emotional)
```

## Length bonus

After scoring, add a bonus to the winning score based on segment length:

- `len(segment) > 500` → +2
- `len(segment) > 200` → +1
- otherwise → +0

Longer segments contain more context, so a winner derived from more material gets a confidence boost.

## Disambiguation pass

Raw marker scoring confuses "problem" and "milestone" when a problem is resolved in the same segment. Fix this before committing to a classification:

1. If the top type is `problem` AND the segment contains a resolution marker (`fixed`, `solved`, `resolved`, `patched`, `got it working`, `it works`, `nailed it`, `figured it out`, `the (fix|answer|solution)`), promote it to `milestone`. But if it also scored on `emotional` and has positive sentiment, prefer `emotional`.
2. If the top type is `problem` AND the segment sentiment is positive (more positive than negative words), promote to `milestone` if `milestone` scored > 0, else `emotional` if `emotional` scored > 0.

### Sentiment word sets

**Positive:** pride, proud, joy, happy, love, loving, beautiful, amazing, wonderful, incredible, fantastic, brilliant, perfect, excited, thrilled, grateful, warm, breakthrough, success, works, working, solved, fixed, nailed, heart, hug, precious, adore

**Negative:** bug, error, crash, crashing, crashed, fail, failed, failing, failure, broken, broke, breaking, breaks, issue, problem, wrong, stuck, blocked, unable, impossible, missing, terrible, horrible, awful, worse, worst, panic, disaster, mess

Sentiment = compare how many unique positive vs negative words appear in the segment.

## Confidence threshold

After disambiguation, compute:

```
confidence = min(1.0, (max_score + length_bonus) / 5.0)
```

Skip the segment if `confidence < 0.3`. This prevents borderline matches from polluting the palace.

## Output format

Each extracted memory becomes one drawer in the mine-output. The room name for general-mode drawers is the `memory_type` value directly (one of `decision`, `preference`, `milestone`, `problem`, `emotional`). The drawer frontmatter gets an extra field `extract_mode: general` so the search skill can filter for extracted memories specifically.

## Example walkthrough

Input segment:
> We decided to switch from MongoDB to Postgres because the aggregation pipeline was getting hairy and we needed real joins. It was a headache to migrate — three weekends of work — but now queries that took 40 seconds run in 200ms. Finally working.

Scoring on prose:
- `decision`: matches `\bwe (should|decided|chose|went with|picked|settled on)\b`, `\binstead of\b` (no), `\bbecause\b`, `\barchitecture\b` (no) → score 2
- `problem`: matches `\b(bug|error|crash|fail|broke|broken|issue|problem)\b` (no), `\bworkaround\b` (no), `\bheadache\b` (not in set), `\bkeeps? failing\b` (no) → score 0
- `milestone`: matches `\bit works\b` (no — "working" not "it works"), `\bfinally\b` → score 1; bonus for `\d+ms` (no)
- `emotional`: no matches → score 0

Length: ~270 chars → +1 bonus

Top type: `decision` (score 2+1=3). Confidence = 3/5 = 0.6. Passes 0.3 threshold. Output:

```json
{"memory_type": "decision", "content": "<original segment>", "chunk_index": N}
```
