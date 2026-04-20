---
name: storytelling-report
description: >
  Brand narrative + voice audit toolkit for the current GitHub
  repository. Parses `brand/NARRATIVE.md` for voice guidelines, key
  messages, and positioning; scores public-facing assets (README,
  docs, CHANGELOG, landing files) on heuristic voice metrics
  (jargon density, sentence length, passive-voice ratio, Flesch
  reading ease); checks key-message coverage; generates talking-point
  drafts for unnarrated releases. Use when the user asks to "check
  brand voice", "audit narrative consistency", "draft talking points",
  or "find key messages missing from README". No external NLP APIs.
---

# Storytelling Report

The brand-narrative audit skill for the **current repository**.
Shipped as the implementation layer behind the `@storytelling`
subagent.

## Intent routing

| If the user asks about...                                         | Read this reference              |
| ----------------------------------------------------------------- | -------------------------------- |
| Narrative bible structure and maintenance                         | `references/narrative.md`        |
| Voice / tone scoring across assets                                | `references/voice.md`            |
| Talking-point generation for release narratives                   | `references/talking-points.md`   |
| Positioning audit and value-proposition consistency               | `references/positioning.md`      |

For a **full audit** run `generate-report.sh`.

## Hard rules

1. **Never invent metrics.** Every score and drift reading comes from
   a script's output.
2. **Always write the final report to `brand/reports/YYYY-MM-DD-*.md`.**
3. **Don't edit the narrative bible.** Bootstrap on the first tick
   (with user consent); never rewrite on subsequent runs.
4. **Tone scores are heuristic.** Present them as "signals that
   warrant review," not verdicts.
5. **Confirm before posting** to GitHub.

## Available scripts

| Script                | Purpose                                                                 |
| --------------------- | ----------------------------------------------------------------------- |
| `collect.sh`          | Load `brand/NARRATIVE.md` (voice guidelines, key messages, positioning), enumerate public-facing assets (README, docs/, landing files, CHANGELOG, blog/), extract word count / sentence-length distribution / passive-voice count / jargon matches / Flesch reading ease per asset. List recent releases. |
| `voice.sh`            | Score each asset on a 0–10 tone scale derived from sentence length + passive ratio + Flesch, plus jargon density. Flag assets whose tone score is > 2σ from the bible-target score. |
| `alignment.sh`        | For each key message in the narrative bible, check presence (case-insensitive substring) in each asset. Emit `missingMessagesInREADME[]` and a full coverage matrix. |
| `talking-points.sh`   | For each release not already covered by a file under `brand/talking-points/`, either generate a stub (with `--write`) or emit a plan entry. |
| `generate-report.sh`  | Collects once, runs every reporter, composes the full markdown audit. |

**Invocation patterns:**

```bash
# Full audit
bash scripts/generate-report.sh > brand/reports/$(date +%F)-audit.md

# Reuse one snapshot
bash scripts/collect.sh > /tmp/brand-snap.json
bash scripts/voice.sh          --snapshot /tmp/brand-snap.json
bash scripts/alignment.sh      --snapshot /tmp/brand-snap.json
bash scripts/talking-points.sh --snapshot /tmp/brand-snap.json
```

## Output convention

Reports go to `brand/reports/`. Talking-point drafts go to
`brand/talking-points/`:

```
brand/reports/2026-04-20-audit.md
brand/talking-points/2026-04-20-v2.4.0-webhook-retry.md
```

## Tick action

Users invoke `tick` (via `@storytelling tick` from `/loop` or
`/schedule`). It is **idempotent, repo-scoped, silent by default**
— BSG convention, see [`CLAUDE.md`][claude-md].

[claude-md]: https://github.com/beyond-scale-group/bsg-stack/blob/main/CLAUDE.md

### Steps

1. Generate the full audit:

   ```bash
   mkdir -p brand/reports brand/talking-points
   bash ~/.claude/skills/storytelling-report/scripts/generate-report.sh \
     > brand/reports/$(date +%F)-audit.md
   ```

2. Land the report:

   ```bash
   bash ~/.claude/scripts/open-report-pr.sh \
     brand/reports/$(date +%F)-audit.md \
     --agent storytelling
   ```

3. Evaluate silence-breakers. Agent owns thresholds.

4. Reply with one-line receipt on clean, summary + PR URL otherwise.

### Silence is a feature

Do **not** pad the reply with "narrative looks consistent" wording.
Remediation (rewriting drifting copy, updating the bible, editing
the README to include a missing key message) is **never** part of
`tick`.

---

## How to improve this skill

This file is a cached copy of `claude-skills/skills/storytelling-report/SKILL.md` in
[beyond-scale-group/bsg-stack](https://github.com/beyond-scale-group/bsg-stack).
That repo is the single source of truth — `~/.claude/skills/storytelling-report/SKILL.md` is
overwritten every time the BSG install flow runs.

If the user asks you to improve, fix, or extend this skill, do **not** edit
the local file. Instead:

1. `gh repo clone beyond-scale-group/bsg-stack` (or work in an existing clone)
2. Edit `claude-skills/skills/storytelling-report/SKILL.md` on a feature branch
3. Open a pull request against `main`

Bug reports and ideas without a fix → open an issue on the same repo.
