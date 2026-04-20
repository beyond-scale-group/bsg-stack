# PRD-006: Storytelling Agent

**Status:** Draft
**Author:** Guillaume Badin
**Date:** 2026-04-20
**Priority:** P2 — Phase 4

---

## 1. Problem Statement

Companies communicate through dozens of touchpoints — README files, landing
pages, docs, changelogs, blog posts, investor decks, onboarding flows — but
the narrative across these assets drifts over time. The founding story gets
rewritten inconsistently, the value proposition shifts without alignment, and
the brand voice varies from formal in docs to casual in blog posts to robotic
in changelogs. Without a single source of truth for "who we are and how we
talk," every new piece of content is a coin flip on brand consistency.

## 2. Goal

Provide a Claude Code subagent that maintains a narrative bible
(`brand/NARRATIVE.md`), audits brand voice consistency across repo assets, and
generates talking points from product events — ensuring every public-facing
word sounds like it comes from the same company.

## 3. Non-Goals

- **Visual brand identity.** Logos, color palettes, typography are out of scope.
  This agent covers words, not design.
- **Content creation.** The agent audits consistency and generates talking
  points as starting material; it does not write final blog posts or landing
  page copy.
- **Social media management.** No posting, scheduling, or engagement tracking.
- **External content monitoring.** The agent works on repo files only — press
  mentions, partner sites, and social media are out of scope.

## 4. User Stories

| # | As a… | I want to… | So that… |
|---|-------|-----------|----------|
| N1 | Founder | Maintain a narrative bible that defines our story, voice, and positioning | Every team member communicates consistently |
| N2 | Marketing lead | Run `@storytelling tick` and see if any asset drifts from the narrative | I can catch tone/messaging inconsistencies before they go live |
| N3 | Developer | Get talking points when a major release ships | I can write a changelog entry that matches our voice |
| N4 | Content writer | Run `@storytelling voice` to check a draft against brand guidelines | I know if my copy matches the established tone |
| N5 | Founder | See the narrative bible evolve alongside the product | The story stays current as the product matures |
| N6 | Marketing lead | Track narrative health over time in `brand/reports/` | I can demonstrate brand consistency improvements |

## 5. Agent Design

### 5.1 Frontmatter

```yaml
---
name: storytelling
description: >
  Brand narrative auditor for the current GitHub repository. Maintains the
  narrative bible (brand/NARRATIVE.md), audits voice consistency across
  public-facing assets, and generates talking points from product events.
  Use when the user asks for "brand audit", "narrative check", "voice
  consistency", "talking points", "brand story", "tone of voice",
  "narrative bible", "cohérence de marque", "ton éditorial", or
  "storytelling".
tools: Read, Glob, Grep, Bash, Write
model: sonnet
skills: [storytelling-report]
color: violet
output: pr
tick: >
  Audit public-facing repo assets against brand/NARRATIVE.md, land the
  report as brand/reports/YYYY-MM-DD-audit.md via open-report-pr.sh, and
  stay silent unless a silence-breaker fires.
---
```

### 5.2 Routing Table

| User intent | Action |
|---|---|
| "brand audit", "narrative check", "voice consistency" | Run all scripts, produce full report |
| "narrative bible", "who are we", "brand story" | `storytelling-report` -> `references/narrative.md` |
| "voice check", "tone audit", "does this sound right" | `storytelling-report` -> `references/voice.md` |
| "talking points", "release narrative", "how to announce" | `storytelling-report` -> `references/talking-points.md` |
| "positioning", "value proposition", "differentiators" | `storytelling-report` -> `references/positioning.md` |
| "write copy for X", "rewrite this page" | Decline; hand back to main agent |

### 5.3 Tick Action

**Steps:**

1. Run `collect.sh` to gather a brand snapshot (`/tmp/brand-snap.json`):
   - Load `brand/NARRATIVE.md` (voice guidelines, positioning, key messages)
   - Scan public-facing files: README.md, docs/, landing pages, CHANGELOG,
     blog posts, onboarding copy
   - Extract key phrases, tone markers, value propositions from each asset
   - `gh release list --json` for recent releases (talking point triggers)

2. Run individual reporters:
   - `voice.sh --snapshot /tmp/brand-snap.json` — tone consistency scoring
     per asset (formal/casual/technical scale, jargon density, sentence length)
   - `alignment.sh --snapshot /tmp/brand-snap.json` — key message presence in
     each asset vs. narrative bible
   - `talking-points.sh --snapshot /tmp/brand-snap.json` — generate points
     for unnarrated releases

3. `generate-report.sh` composes the full report:
   ```
   brand/reports/2026-04-20-audit.md
   ```

4. Land via `open-report-pr.sh`:
   ```bash
   bash ~/.claude/scripts/open-report-pr.sh \
     brand/reports/$(date +%F)-audit.md \
     --agent storytelling
   ```

5. Evaluate silence-breakers. Reply with one-line receipt if none fire.

### 5.4 Silence-Breakers

| Signal | Source | Threshold |
|---|---|---|
| Asset voice drift | `voice.sh` -> `driftScore` | Any asset > 2 standard deviations from narrative bible tone |
| Key message missing from README | `alignment.sh` -> `missingMessages[]` | Any core message absent from primary README |
| Outdated positioning (product evolved past narrative) | `alignment.sh` -> `stalePositioning[]` | Narrative bible references features removed > 30 days ago |
| Release without talking points | `talking-points.sh` -> `unnarratedReleases[]` | Any minor/major release without generated points |
| Narrative bible missing | `collect.sh` -> `narrativeFound: false` | First tick only — suggest bootstrapping |

### 5.5 Narrative Bible Schema

The agent expects (and can bootstrap) `brand/NARRATIVE.md` with this structure:

```markdown
# Brand Narrative Bible

## Our Story
[Origin story — why this company exists, the problem that sparked it]

## Mission
[One sentence: what we do and for whom]

## Vision
[One sentence: the world we're building toward]

## Value Proposition
[2-3 bullet points: why choose us over alternatives]

## Voice Guidelines
- **Tone:** [e.g., confident but not arrogant, technical but accessible]
- **Vocabulary:** [preferred terms, banned terms]
- **Sentence style:** [e.g., short and direct, avoid passive voice]

## Key Messages
1. [Core message that must appear in all primary assets]
2. [Secondary message for technical audiences]
3. [Differentiator message vs. competitors]

## Positioning
- **Category:** [what market category we compete in]
- **Target audience:** [who we serve]
- **Differentiators:** [what makes us unique]
```

## 6. Skill Structure

```
skills/storytelling-report/
├── SKILL.md                    # Intent routing + hard rules
├── references/
│   ├── narrative.md            # Narrative bible management guide
│   ├── voice.md                # Voice consistency analysis guide
│   ├── talking-points.md       # Talking point generation guide
│   └── positioning.md          # Positioning audit guide
└── scripts/
    ├── collect.sh              # Snapshot collector (narrative + assets)
    ├── voice.sh                # Tone/voice consistency scorer
    ├── alignment.sh            # Key message alignment checker
    ├── talking-points.sh       # Talking point generator for releases
    └── generate-report.sh      # Full report composer
```

## 7. Report Format

```markdown
# Brand Audit — 2026-04-20

## Voice Consistency
| Asset | Tone Score | Jargon | Avg Sentence | Drift |
|-------|-----------|--------|-------------|-------|
| README.md | 7.2 (confident) | Low | 14 words | OK |
| docs/getting-started.md | 5.1 (neutral) | High | 22 words | DRIFT |
| CHANGELOG.md | 3.0 (robotic) | Medium | 8 words | DRIFT |

**Bible tone target:** 7.0 (confident, accessible)

## Key Message Alignment
| Message | README | Docs | Landing | Blog |
|---------|--------|------|---------|------|
| "Ship faster with confidence" | YES | YES | YES | NO |
| "Enterprise-grade security" | YES | NO | YES | YES |
| "Developer-first API" | YES | YES | NO | YES |

## Unnarrated Releases
| Release | Date | Talking Points |
|---------|------|----------------|
| v2.4.0 | Apr 18 | MISSING — [auto-generated draft below] |

### Draft Talking Points: v2.4.0
- **Headline:** Webhook reliability, solved
- **Detail:** Automatic retry with exponential backoff means…
- **Voice note:** Lead with user benefit, not technical mechanism
```

## 8. Dependencies

- `jq` for JSON processing
- `gh` CLI for release data
- `wc`, `grep`, `awk` for text analysis (sentence length, word frequency)
- No external NLP APIs — tone scoring uses heuristic rules (word lists,
  sentence length, passive voice detection)

## 9. Success Metrics

| Metric | Target |
|---|---|
| Voice drift detection | Flagged within 1 tick of divergent asset |
| Key message coverage | 100% of core messages present in README and landing page |
| Talking point latency | Points generated within 1 tick of release |
| Narrative bible adoption | Bootstrapped in all customer-facing repos within 8 weeks |

## 10. Risks & Mitigations

| Risk | Mitigation |
|---|---|
| Tone scoring without NLP is imprecise | Use validated heuristics (Flesch readability, passive voice ratio, jargon word lists); flag "review suggested" instead of definitive "wrong" |
| Narrative bible doesn't exist | First tick offers to bootstrap from README + existing copy; template included in skill |
| Too many assets to audit in large repos | `collect.sh` focuses on primary assets (README, docs index, landing page); secondary assets audited on request |
| Voice guidelines are subjective | Agent reports metrics and deviations; human decides if drift is intentional |
| Multilingual repos | Audit one language at a time; default to the language of NARRATIVE.md |
