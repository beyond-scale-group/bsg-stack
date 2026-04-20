# PRD-005: Marketing Agent

**Status:** Draft
**Author:** Guillaume Badin
**Date:** 2026-04-20
**Priority:** P1 — Phase 3

---

## 1. Problem Statement

Marketing and product development operate on parallel timelines that frequently
drift apart. Features ship without marketing awareness, landing pages describe
capabilities that don't exist yet, and content calendars slip without anyone
noticing. There is no automated mechanism to detect the gap between "what the
product does" and "what the marketing says it does" — this misalignment erodes
trust with users and wastes marketing effort on outdated messaging.

## 2. Goal

Provide a Claude Code subagent that maintains a content calendar, audits the
alignment between shipped features and marketed features, and generates campaign
briefs from product milestones — surfacing drift before it reaches customers.

## 3. Non-Goals

- **Executing marketing campaigns.** The agent plans and audits; it does not
  send emails, post to social media, or manage ad spend.
- **Copywriting.** The agent generates campaign briefs and flags copy drift;
  it does not write final marketing copy.
- **Analytics integration.** No Google Analytics, HubSpot, or attribution
  tracking. Data comes from the repo (milestones, READMEs, landing pages,
  changelogs).
- **Design work.** No image generation, layout design, or brand asset creation.

## 4. User Stories

| # | As a… | I want to… | So that… |
|---|-------|-----------|----------|
| M1 | Marketing lead | Run `@marketing tick` and see if any campaigns are overdue | I can reprioritize before deadlines pass |
| M2 | Product manager | See which shipped features have no marketing coverage | I can request campaign briefs for unannounced features |
| M3 | Marketing lead | Maintain a content calendar in `marketing/CALENDAR.md` | The whole team sees what's planned and when |
| M4 | Developer | Run `@marketing alignment` to check feature-marketing parity | I know if the landing page matches current capabilities |
| M5 | Marketing lead | Get campaign briefs auto-generated from milestone closures | I have a starting point for every feature launch |
| M6 | Marketing lead | Track marketing health over time in `marketing/reports/` | I can demonstrate coverage improvements |

## 5. Agent Design

### 5.1 Frontmatter

```yaml
---
name: marketing
description: >
  Marketing auditor for the current GitHub repository. Maintains the content
  calendar, audits alignment between shipped features and marketing copy,
  and generates campaign briefs from product milestones. Use when the user
  asks for "marketing audit", "content calendar", "campaign brief",
  "feature alignment", "what's marketed", "landing page check",
  "calendrier marketing", "brief de campagne", or "alignement produit-marketing".
tools: Read, Glob, Grep, Bash, Write
model: sonnet
skills: [marketing-report]
color: pink
output: pr
tick: >
  Audit the content calendar for overdue items, check feature-marketing
  alignment, land the report as marketing/reports/YYYY-MM-DD-audit.md
  via open-report-pr.sh, and stay silent unless a silence-breaker fires.
---
```

### 5.2 Routing Table

| User intent | Action |
|---|---|
| "marketing audit", "full marketing check" | Run all scripts, produce full report |
| "content calendar", "what's planned", "overdue content" | `marketing-report` -> `references/calendar.md` |
| "feature alignment", "shipped vs marketed" | `marketing-report` -> `references/alignment.md` |
| "campaign brief", "brief for milestone X" | `marketing-report` -> `references/brief.md` |
| "landing page audit", "messaging check" | `marketing-report` -> `references/messaging.md` |
| "write copy for X", "design campaign Y" | Decline; hand back to main agent |

### 5.3 Tick Action

**Steps:**

1. Run `collect.sh` to gather a marketing snapshot (`/tmp/mkt-snap.json`):
   - Parse `marketing/CALENDAR.md` for scheduled items and their dates
   - `gh release list --json` for recent releases
   - `gh api /repos/{owner}/{repo}/milestones` for closed/upcoming milestones
   - Scan landing pages / README / docs for feature claims
   - Scan changelog / release notes for shipped features

2. Run individual reporters:
   - `calendar.sh --snapshot /tmp/mkt-snap.json` — overdue items, upcoming deadlines
   - `alignment.sh --snapshot /tmp/mkt-snap.json` — shipped-vs-marketed matrix
   - `brief.sh --snapshot /tmp/mkt-snap.json` — auto-generate briefs for unannounced releases

3. `generate-report.sh` composes the full report:
   ```
   marketing/reports/2026-04-20-audit.md
   ```

4. Land via `open-report-pr.sh`:
   ```bash
   bash ~/.claude/scripts/open-report-pr.sh \
     marketing/reports/$(date +%F)-audit.md \
     --agent marketing
   ```

5. Evaluate silence-breakers. Reply with one-line receipt if none fire.

### 5.4 Silence-Breakers

| Signal | Source | Threshold |
|---|---|---|
| Overdue calendar item | `calendar.sh` -> `overdueItems[]` | Any item past its scheduled date |
| Shipped feature with no marketing | `alignment.sh` -> `unmarketed[]` | Any release/milestone closed without matching content |
| Marketed feature not yet shipped | `alignment.sh` -> `unshipped[]` | Any landing page claim with no matching release |
| Calendar missing or empty | `calendar.sh` -> `calendarFound: false` | First tick only — suggest bootstrapping |
| Campaign brief not picked up | `brief.sh` -> `staleBriefs[]` | Brief generated > 14 days ago with no follow-up |

## 6. Skill Structure

```
skills/marketing-report/
├── SKILL.md                    # Intent routing + hard rules
├── references/
│   ├── calendar.md             # Content calendar management guide
│   ├── alignment.md            # Feature-marketing alignment methodology
│   ├── brief.md                # Campaign brief generation guide
│   └── messaging.md            # Landing page / messaging audit guide
└── scripts/
    ├── collect.sh              # Snapshot collector (calendar + releases + pages)
    ├── calendar.sh             # Content calendar auditor
    ├── alignment.sh            # Shipped-vs-marketed parity checker
    ├── brief.sh                # Campaign brief generator
    └── generate-report.sh      # Full report composer
```

## 7. Report Format

```markdown
# Marketing Audit — 2026-04-20

## Content Calendar
| Item | Scheduled | Status |
|------|-----------|--------|
| Blog: API v2 launch | 2026-04-15 | OVERDUE |
| Newsletter: Q2 update | 2026-04-30 | On track |
| Case study: Acme Corp | 2026-05-10 | On track |

**Summary:** 1 overdue, 2 on track, 0 completed this period

## Feature-Marketing Alignment
| Feature | Shipped | Marketed | Status |
|---------|---------|----------|--------|
| OAuth2 login | v2.3.0 (Apr 10) | Landing page | ALIGNED |
| Webhook retry | v2.4.0 (Apr 18) | — | GAP |
| "AI assistant" | — | Landing page | PREMATURE |

## Campaign Briefs (Auto-generated)
### Webhook Retry (v2.4.0)
- **What:** Automatic webhook retry with exponential backoff
- **Who:** Developers integrating via webhooks
- **Angle:** Reliability — never miss a webhook again
- **Assets needed:** Blog post, changelog entry, docs update
```

## 8. Dependencies

- `gh` CLI (authenticated) for releases and milestones
- `jq` for JSON processing
- `grep` for content scanning
- `date` for calendar date comparison
- Maintained `marketing/CALENDAR.md` (bootstrapped on first tick if absent)

## 9. Success Metrics

| Metric | Target |
|---|---|
| Feature-marketing alignment gap detection | 100% of shipped features without marketing flagged |
| Calendar overdue detection | Flagged within 1 tick of overdue date |
| Campaign brief generation latency | Brief available within 1 tick of release |
| Marketing audit adoption | Active in all customer-facing repos within 6 weeks |

## 10. Risks & Mitigations

| Risk | Mitigation |
|---|---|
| No `marketing/CALENDAR.md` exists | First tick bootstraps a template; subsequent ticks skip calendar check gracefully |
| Feature detection is heuristic (based on releases/milestones) | Conservative: only flag releases tagged as minor/major, ignore patches |
| Landing page copy changes without repo update | Agent works on repo source; out-of-repo copy (CMS, Webflow) is out of scope — document this limitation |
| "Marketed" detection via keyword matching is imprecise | Use feature names from milestone titles as search terms; allow `.marketingignore` for false positives |
