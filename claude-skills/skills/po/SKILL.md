---
name: po
description: >
  Product owner skill for the current GitHub repository. Covers the full
  scope of a real PO: plan authoring and adherence, backlog triage,
  milestone tracking, stale-issue gardening, PR flow health, sprint
  planning, scope-creep detection, and stakeholder reporting. Use when
  the user asks "où en est le projet", "what's drifting", "triage the
  backlog", "bootstrap a plan", "sprint health", "what's blocking us",
  "generate a PO report", or any product-ownership question. Reporting
  is one capability among many — not the primary purpose.
version: 0.3.0
model: sonnet
---

# Product Owner

The PO skill for the **current repository**. Covers plan adherence,
backlog triage, milestone tracking, sprint planning, scope-creep
detection, and stakeholder reporting. All heavy lifting is done by bash
scripts in `scripts/` — use them instead of re-deriving data through
ad-hoc `gh` calls.

## Intent routing

Read the user's request and pick the matching reference document:

| If the user asks about...                                      | Read this reference         |
| -------------------------------------------------------------- | --------------------------- |
| Plan adherence, drift, "où en est le plan", "on course?"       | `references/adherence.md`   |
| Bootstrap / propose a starter `PLAN.md`                        | `references/adherence.md` (bootstrap flow) |
| PLAN.md schema / how to write bindings                         | `references/plan-schema.md` |
| Overall status / health / "où en est le projet" / full report  | `references/status.md` (adherence is its headline section) |
| Milestone progress, sprint health, burndown                    | `references/milestones.md`  |
| Stale issues, no recent activity, abandoned work               | `references/stale.md`       |
| PR review latency, merge queue, throughput                     | `references/pr-flow.md`     |
| Velocity, burndown, trends, "are we speeding up/slowing down?" | `references/trends.md`      |
| Wire the weekly plan into Google Calendar / assign issues      | `references/weekly-plan.md` |

For multi-topic requests (e.g. "give me a full report"), follow `references/status.md`
which itself orchestrates the others.

## Hard rules

1. **Never invent numbers.** Always read them from the scripts' JSON output.
2. **Always write the final report to `po/reports/YYYY-MM-DD-{slug}.md`** so
   it is dated and version-controllable.
3. **Run scripts from the repo root.** They use `gh` which auto-detects the repo.
4. **Do not call `gh issue list` or `gh api` yourself** for aggregation — use
   the scripts. Direct `gh` calls are reserved for follow-up actions on a
   specific ticket the user named.
5. **Confirm before posting** anywhere external (GitHub comments, etc.). Default
   is local-only.
6. **Never probe for PLAN.md by path** (`cat po/PLAN.md`, `ls po/`, etc.).
   Always use `bash scripts/parse-plan.sh --typed` — it resolves `.bsg/PLAN.md`
   first (preferred), then `po/PLAN.md` (legacy). Path-checking bypasses this
   resolution and silently misses repos that store the plan under `.bsg/`.

## Conventions

These conventions complement the hard rules above. Hard rules say *what
to do*; conventions say *how it must look*. There are two distinct
output channels — **Calendar Events** (time-blocked slots for reviews
and meetings) and **Google Tasks** (5-min markers per actionable
ticket) — never mix them.

### Calendar events posted by the PO

The PO posts calendar events for review slots, decision check-ins, and
delegation hand-offs (via the `google-workspace` skill). Three rules
apply to every event:

1. **Title prefix `[<repo>]`** — every event title is prefixed by the
   repo or project name in brackets so the user can recognize the
   project at a glance from a busy day view. Examples:

   ```
   [the-shift.ai]   PO · Review storytelling #80 — NARRATIVE draft v1
   [bsg-holding.fr] PO · Sprint planning S23
   [expert-flow.ai] PO · Review chiffres trimestre
   ```

2. **GitHub issue URL in description** — when the event is tied to one
   or more issues, include the full `https://github.com/.../issues/N`
   URL(s) in the description. The title carries the issue number
   (`#80`); the description carries the clickable link.

3. **Free/busy check before posting** — call `freebusy.query` on a
   ±2 h window around the target slot. If there is a conflict, shift
   to the nearest free quarter-hour and **explicitly mention the shift
   in the description** (e.g. *"Décalé de 17:00 à 17:45 — conflit avec
   réunion 16:00–17:30"*). Never silently overlay.

### Cross-repo narrative drift

A PO report on repo `A` must surface — and propose to relocate — any
narrative element that belongs to a sibling repo `B`. Examples to
watch for:

- A holding-level press talking point sitting in a portfolio company's
  `PLAN.md` (e.g. *"Constellation Software français"* content found in
  `the-shift.ai` when it belongs to `bsg-holding.fr`).
- A product-specific case study in the parent holding's content
  calendar instead of the operating company's.
- Brand positioning lines that contradict the repo's own
  `brand/NARRATIVE.md`.

Each finding goes in a `## Cross-repo drift` subsection of the PO
report with: (a) source line + file:line reference, (b) target repo,
(c) one-line rewrite for the current repo, (d) one-line stub for the
target repo. **No silent deletion** — the user decides.

### Delegation to specialist skills

The PO is an orchestrator, not a writer. When a backlog item requires
brand voice, French copy review, SEO work, Qualiopi audit, or
fact-checking, the PO does **not** write the deliverable. Instead:

1. Launch the matching skill or subagent (`storytelling`, `french`,
   `seo`, `qualiopi`, `truth`, etc.) with a self-contained brief.
2. Post a 15-min review slot in the user's calendar following the
   "Calendar events" convention above.
3. Track the delegation in the PO report so accountability stays
   clear.

### Decisions must be actionable

Every PO report ends with a `## Décisions à confirmer` (or `## Decisions
to confirm`) section. Each decision is a **closed question** — yes/no
or A/B — attached to an owner name. No open-ended deliberations like
*"want to discuss?"* or *"tu veux qu'on en parle ?"*. Decisions move
work; deliberations stall it.

### Milestone hygiene at every check

When the PO surfaces open issues that lack a milestone, it must also
**propose the target milestone for each**, based on the issue title,
labels, and the active `PLAN.md` objectives. Never just list *"3
issues without milestone"* — always pair each orphan with a proposed
rattachement so the user can ack with a single yes.

### Per-ticket Google Tasks (5 min, repo-specific task list)

Every open GitHub issue surfaced in a PO report has a corresponding
**Google Task** (not Calendar Event) in the **repo-specific task
list**. Three rules:

1. **Task list = repo name** — one task list per repo
   (`the-shift.ai`, `bsg-holding.fr`, `expert-flow.ai`, …). Create on
   first use if absent. Never dump cross-repo tickets in a generic
   "My Tasks" list.

2. **Title format `[<repo>] #<N> · <truncated-title>`** — recognizable
   from the merged Google Calendar / Tasks view, ticket number always
   present so the user can `gh issue view <N>` in one keystroke. Put
   the full GitHub URL in the task body.

3. **5-min default effort + Tasks ≠ slots** — note `est: 5 min` in the
   task body as the default. Google Tasks integrate into the Calendar
   UI but **do not block time slots** — that's the point. Use Calendar
   Events for time-blocked reviews / meetings (15 min slots, the
   "Calendar events" convention above). Use Tasks for the actionable
   work-to-do list (5 min markers). Never use a Calendar Event where a
   Task fits.

## Available scripts

All scripts live in `scripts/` and emit JSON on stdout (except
`generate-report.sh` which emits markdown). `collect.sh` is the single
GraphQL fetch; every other script is a pure jq transform of that
snapshot — pass it with `--snapshot <path>`, pipe it in, or let the
script auto-collect a fresh one.

| Script                    | Purpose                                                                |
| ------------------------- | ---------------------------------------------------------------------- |
| `collect.sh`              | One paginated GraphQL fetch → full snapshot JSON (issues, PRs, milestones, releases, repo meta). Every other script consumes this. |
| `parse-plan.sh`           | Parse `.bsg/PLAN.md` (preferred) or `po/PLAN.md` (legacy fallback) into an array of plan items with typed bindings (`milestones`, `epics`, `labels`). Use `--typed` for a `{status, items}` response; empty array if the file is missing in default mode. |
| `adherence.sh`            | Join plan items with the snapshot → per-item status, evidence, and the three drift classes (`scopeCreep`, `abandonedItems`, `offCourse`). |
| `bootstrap-plan.sh`       | Emit a draft starter `PLAN.md` from current milestones + top labels. Never writes to disk — caller saves under `po/drafts/`. |
| `status.sh`               | Repo-wide counts + PR flow summary (review pending, failing checks, oldest open PR, avg time-to-first-review). |
| `pr-flow.sh`              | Deeper PR metrics: review latency p50/p90, open-PR age buckets, reviewer load, merge-queue depth, throughput. |
| `milestone-progress.sh`   | Per-milestone progress with risk flags (`overdue`, `at_risk`, `understaffed`, `stalled`) computed in jq. |
| `stale-issues.sh [DAYS]`  | Open issues with no comment activity for N days (default: 14). Uses `lastCommentedAt` so bot label bumps don't reset staleness. |
| `trends.sh`               | Reads `po/history/*.json` → velocity (issues closed / PRs merged per week), scope delta, timeseries. Git history is the trend store — no extra state. |
| `generate-report.sh`      | Collects once, runs adherence, composes a full markdown report with the adherence matrix as headline. |
| `render-adherence.jq`     | Standalone jq program that turns `adherence.sh` output into the "Plan adherence" markdown section (used by `generate-report.sh`). |
| `weekly-plan.sh`          | Emits a Mon→Fri JSON breakdown of open issues; with `--calendar` creates/patches one `gws calendar +insert` event per working day (repo prefix mandatory); with `--assign --user X` batch-assigns the cited issues (dry-run by default, `--yes` to mutate). See `references/weekly-plan.md`. |

**Invocation patterns:**

```bash
# One-shot: collect + render
bash scripts/generate-report.sh > po/reports/$(date +%F)-status.md

# Reuse one snapshot across multiple reports
bash scripts/collect.sh > /tmp/snap.json
bash scripts/status.sh            --snapshot /tmp/snap.json
bash scripts/milestone-progress.sh --snapshot /tmp/snap.json

# Target a specific repo without a checkout
GH_REPO=owner/name bash scripts/collect.sh | jq '.issues | length'
```

## Output convention

Reports go to `po/reports/`. Filename pattern:

```
po/reports/2026-04-10-status.md
po/reports/2026-04-10-milestone-v1.md
po/reports/2026-04-10-stale.md
```

Use today's date. After writing, print the file path and a 3-bullet executive
summary in the chat — do **not** dump the full report inline.

---

## How to improve this skill

This file is a cached copy of `claude-skills/skills/po/SKILL.md` in
[beyond-scale-group/bsg-stack](https://github.com/beyond-scale-group/bsg-stack).
That repo is the single source of truth — `~/.claude/skills/po/SKILL.md` is
overwritten every time the BSG install flow runs.

If the user asks you to improve, fix, or extend this skill, do **not** edit
the local file. Instead:

1. `gh repo clone beyond-scale-group/bsg-stack` (or work in an existing clone)
2. Edit `claude-skills/skills/po/SKILL.md` on a feature branch
3. Open a pull request against `main`

Bug reports and ideas without a fix → open an issue on the same repo.
