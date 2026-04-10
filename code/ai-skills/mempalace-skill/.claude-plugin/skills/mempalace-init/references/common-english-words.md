# Common English Words (ambiguity check list)

Use this list during `mempalace-init` Step 6 ambiguity warning. If a person's
first name (lowercased) appears in this list, warn the user that the name is
also a common English word so they're aware future searches will need context
disambiguation.

This is a curated subset of names that are also common English words — not a
full English dictionary. The upstream Python uses a larger `COMMON_ENGLISH_WORDS`
set in `entity_registry.py`; this list captures the most frequent collisions.

## Names that are also common words

- art (art)
- bill (bill)
- carol (carol)
- don (don)
- drew (drew — past tense of draw)
- earl (earl)
- faith (faith)
- frank (frank)
- grace (grace)
- guy (guy)
- holly (holly)
- hope (hope)
- ivy (ivy)
- jack (jack — as in jack of trades, lift with jack)
- jean (jean)
- joy (joy)
- june (june)
- mark (mark)
- may (may)
- pat (pat)
- penny (penny)
- rose (rose — past tense of rise, or the flower)
- ruby (ruby)
- sage (sage)
- summer (summer)
- victor (victor)
- will (will — as in willpower, last will)

## How to use this list

When you read this file during init:

1. Lowercase the person's first name.
2. Check if it appears in the list above.
3. If yes, warn the user with a one-sentence heads-up and continue.
4. Do not block the name or reject it — this is informational only.

The goal is to set expectations: the user should know that when they later
search for "rose" in their palace, the search skill will have to decide from
context whether they mean the person or "rose to the occasion".
