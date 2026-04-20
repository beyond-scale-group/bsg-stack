# PRD-007: PR/Comms Agent

**Status:** Draft
**Author:** Guillaume Badin
**Date:** 2026-04-20
**Priority:** P2 — Phase 4

---

## 1. Problem Statement

Newsworthy product events — major releases, milestone completions, partnership
integrations, security fixes — happen continuously but rarely get translated
into external communications in a timely manner. Press releases are written
reactively (or not at all), press kits go stale, and the window of relevance
closes before marketing or comms can act. There is no systematic mechanism to
detect PR-worthy events from the development workflow and prepare communication
materials proactively.

## 2. Goal

Provide a Claude Code subagent that monitors the repository for PR-worthy
events (releases, milestone closures, major merges), drafts press angles and
announcement copy, and maintains a press kit — so the comms team always has
a starting point ready when news breaks.

## 3. Non-Goals

- **Media outreach.** The agent drafts materials; it does not contact
  journalists, send press releases, or manage media lists.
- **Social media posting.** No publishing to Twitter, LinkedIn, or other
  platforms.
- **Crisis communications.** Security incidents and PR crises require human
  judgment; the agent may flag the event but does not draft crisis responses.
- **Investor relations.** Earnings, fundraising, and board materials are out
  of scope.
- **Final copy approval.** The agent produces drafts; a human reviews and
  approves before any external publication.

## 4. User Stories

| # | As a… | I want to… | So that… |
|---|-------|-----------|----------|
| P1 | Comms lead | Run `@pr-comms tick` and see if any product event needs a press angle | I can prepare announcements proactively |
| P2 | Comms lead | Get draft press releases when a major version ships | I have a starting point within minutes of release |
| P3 | Founder | Maintain a press kit in `comms/press-kit/` | Journalists always have up-to-date company materials |
| P4 | Marketing lead | Run `@pr-comms events` to see the PR event timeline | I can plan campaigns around upcoming announcements |
| P5 | Comms lead | Track announcement history in `comms/reports/` | I can see what's been communicated and what hasn't |
| P6 | Comms lead | Run `@pr-comms draft` for a specific release | I get a structured press release draft immediately |

## 5. Agent Design

### 5.1 Frontmatter

```yaml
---
name: pr-comms
description: >
  Public relations and communications agent for the current GitHub repository.
  Monitors for PR-worthy events (releases, milestones, major merges), drafts
  press releases and announcement copy, and maintains the press kit. Use when
  the user asks for "press release", "announcement draft", "PR events",
  "press kit", "communication plan", "newsworthy", "communiqué de presse",
  "annonce produit", or "kit presse".
tools: Read, Glob, Grep, Bash, Write
model: sonnet
skills: [pr-comms-report]
color: cyan
output: pr
tick: >
  Scan for PR-worthy events since last tick, draft press angles for
  unannounced events, land the report as comms/reports/YYYY-MM-DD-events.md
  via open-report-pr.sh, and stay silent unless a silence-breaker fires.
---
```

### 5.2 Routing Table

| User intent | Action |
|---|---|
| "PR audit", "communication check", "what's newsworthy" | Run all scripts, produce full report |
| "press release", "draft announcement", "announce release X" | `pr-comms-report` -> `references/press-release.md` |
| "press kit", "media materials", "company boilerplate" | `pr-comms-report` -> `references/press-kit.md` |
| "PR events", "event timeline", "what happened" | `pr-comms-report` -> `references/events.md` |
| "communication plan", "announcement schedule" | `pr-comms-report` -> `references/plan.md` |
| "send press release", "contact journalist" | Decline; out of scope |

### 5.3 Tick Action

**Steps:**

1. Run `collect.sh` to gather a comms snapshot (`/tmp/comms-snap.json`):
   - `gh release list --json` — all releases with dates, tags, bodies
   - `gh api /repos/{owner}/{repo}/milestones?state=closed` — recently closed
   - Scan `comms/press-kit/` for existing materials and their freshness
   - Load `comms/ANNOUNCED.md` (log of already-communicated events) if present
   - Parse contributor stats for "team growth" angle detection

2. Run individual reporters:
   - `events.sh --snapshot /tmp/comms-snap.json` — classify events by
     newsworthiness (major release, milestone, security fix, community milestone)
   - `press-kit.sh --snapshot /tmp/comms-snap.json` — audit press kit freshness
   - `draft.sh --snapshot /tmp/comms-snap.json` — generate press release
     drafts for unannounced events

3. `generate-report.sh` composes the full report:
   ```
   comms/reports/2026-04-20-events.md
   ```

4. Land via `open-report-pr.sh`:
   ```bash
   bash ~/.claude/scripts/open-report-pr.sh \
     comms/reports/$(date +%F)-events.md \
     --agent pr-comms
   ```

5. Evaluate silence-breakers. Reply with one-line receipt if none fire.

### 5.4 Silence-Breakers

| Signal | Source | Threshold |
|---|---|---|
| Major release without announcement | `events.sh` -> `unannouncedMajor[]` | Any major/minor release not in ANNOUNCED.md |
| Milestone closed without comms | `events.sh` -> `unannouncedMilestone[]` | Any milestone closure |
| Press kit stale | `press-kit.sh` -> `staleAssets[]` | Any asset > 90 days old |
| Security advisory published | `events.sh` -> `securityAdvisories[]` | Any (flag for human judgment — do not draft) |
| Community milestone (100th PR, Nth contributor) | `events.sh` -> `communityMilestones[]` | Pre-defined thresholds (100, 500, 1000) |

### 5.5 Press Kit Schema

The agent maintains `comms/press-kit/` with this structure:

```
comms/
├── press-kit/
│   ├── boilerplate.md          # Company description (short, medium, long)
│   ├── fact-sheet.md           # Key facts and figures
│   ├── leadership.md           # Founder/team bios and quotes
│   ├── milestones.md           # Company timeline / key events
│   └── faq.md                  # Frequently asked questions for press
├── ANNOUNCED.md                # Log of communicated events (prevents re-drafting)
└── reports/                    # Dated audit reports
```

## 6. Skill Structure

```
skills/pr-comms-report/
├── SKILL.md                    # Intent routing + hard rules
├── references/
│   ├── press-release.md        # Press release drafting guide (structure, tone)
│   ├── press-kit.md            # Press kit management guide
│   ├── events.md               # Event classification methodology
│   └── plan.md                 # Communication planning guide
└── scripts/
    ├── collect.sh              # Snapshot collector (releases + milestones + kit)
    ├── events.sh               # Event classifier (newsworthiness scoring)
    ├── press-kit.sh            # Press kit freshness auditor
    ├── draft.sh                # Press release draft generator
    └── generate-report.sh      # Full report composer
```

## 7. Report Format

```markdown
# PR/Comms Events — 2026-04-20

## Newsworthy Events (Last 30 Days)
| Event | Date | Type | Announced | Priority |
|-------|------|------|-----------|----------|
| v2.4.0 release | Apr 18 | Major release | NO | HIGH |
| Milestone "API v2" closed | Apr 15 | Milestone | NO | HIGH |
| 50th contributor | Apr 12 | Community | NO | MEDIUM |
| v2.3.1 patch | Apr 10 | Patch | — | LOW (skip) |

## Draft Press Releases

### v2.4.0 — Webhook Reliability Update
**Headline:** [Company] Launches Automatic Webhook Retry, Eliminating
Failed Deliveries for API Integrators

**Lead:** [Company], the developer-first API platform, today announced
version 2.4.0 featuring automatic webhook retry with exponential backoff…

**Quote:** "[Suggested founder quote placeholder]"

**Boilerplate:** [From press-kit/boilerplate.md]

## Press Kit Health
| Asset | Last Updated | Status |
|-------|-------------|--------|
| boilerplate.md | 2026-03-01 | OK |
| fact-sheet.md | 2025-12-15 | STALE (127 days) |
| leadership.md | 2026-02-20 | OK |
```

## 8. Dependencies

- `gh` CLI (authenticated) for releases, milestones, contributors
- `jq` for JSON processing
- `date` for freshness calculations
- `git log` for contributor milestones
- No external APIs or services

## 9. Success Metrics

| Metric | Target |
|---|---|
| Major releases with draft press angle available | 100% within 1 tick |
| Press kit freshness | All assets updated within 90 days |
| Event detection accuracy | 100% of major/minor releases detected |
| Draft-to-publish turnaround | Comms team publishes within 48h of draft |

## 10. Risks & Mitigations

| Risk | Mitigation |
|---|---|
| Press release drafts are generic | Templates include placeholders for human-authored quotes, customer stories; agent flags what needs human input |
| Security events require careful handling | Agent flags security advisories but does NOT draft press responses; explicit note: "requires human judgment" |
| `ANNOUNCED.md` not maintained | Agent can infer announced status from press-kit commit history; ANNOUNCED.md is preferred but optional |
| Events in private repos shouldn't be public | Agent adds "CONFIDENTIAL — review before publishing" header; human decides what to release |
| Newsworthiness scoring is subjective | Conservative defaults: major/minor releases always flagged; patches only if security-related |
