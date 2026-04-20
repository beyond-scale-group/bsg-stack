# Narrative Bible Management

## `brand/NARRATIVE.md` schema

```markdown
# Brand Narrative Bible

## Our Story
[Origin story — why this company exists, the problem that sparked it]

## Mission
[One sentence: what we do and for whom]

## Vision
[One sentence: the world we are building toward]

## Value Proposition
- [Bullet 1]
- [Bullet 2]
- [Bullet 3]

## Voice Guidelines
- **Tone target:** 7.0  (0=robotic, 10=casual; bible target drives voice.sh scoring)
- **Preferred vocabulary:** [list]
- **Banned vocabulary:** [list]
- **Sentence style:** [e.g. short and direct, avoid passive voice]

## Key Messages
1. [Core message, must appear in all primary assets]
2. [Secondary message for technical audiences]
3. [Differentiator vs. competitors]

## Positioning
- **Category:** [market category]
- **Target audience:** [who we serve]
- **Differentiators:** [what makes us unique]
- **Feature anchors:** [product capabilities the positioning depends on;
  the skill checks that these still exist in the product]
```

Rules:

- The `**Tone target:** <number>` line is parsed by `voice.sh`. If
  absent, it defaults to 7.0 (confident-casual).
- Key messages must be numbered. `alignment.sh` matches each against
  the asset text as a case-insensitive substring — keep them
  short-ish (< 8 words) for realistic matching.
- Banned vocabulary (if present) is added to the jargon list with
  a heavy penalty in voice scoring.
- Feature anchors are optional; they power the `stalePositioning`
  detector in `alignment.sh`.

## How to run

```bash
# Narrative status only (no voice / alignment)
jq '.narrative' /tmp/brand-snap.json
```

## Bootstrapping

If `brand/NARRATIVE.md` doesn't exist, `collect.sh` reports
`narrativeFound: false`. The `@storytelling` agent surfaces a
bootstrap suggestion on the first tick:

1. Copy the schema above.
2. Draft from existing README copy and landing pages.
3. Commit the file.
4. Re-run `@storytelling tick`.

Subsequent ticks with `narrativeFound: false` are silent — the
agent has already suggested; repeating is noise.

## What NOT to do

- Don't auto-write the bible. It requires human judgment that the
  agent can't replicate.
- Don't copy the README verbatim into the bible on bootstrap —
  the bible should distill, not duplicate.
- Don't modify the schema without updating the parser. The
  frontmatter keys are stable contract surfaces.
