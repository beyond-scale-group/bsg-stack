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
version: 0.2.0
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

## Available scripts

All scripts live in `scripts/` and emit JSON on stdout (except
`generate-report.sh` which emits markdown). `collect.sh` is the single
GraphQL fetch; every other script is a pure jq transform of that
snapshot — pass it with `--snapshot <path>`, pipe it in, or let the
script auto-collect a fresh one.

| Script                    | Purpose                                                                |
| ------------------------- | ---------------------------------------------------------------------- |
| `collect.sh`              | One paginated GraphQL fetch → full snapshot JSON (issues, PRs, milestones, releases, repo meta). Every other script consumes this. |
| `parse-plan.sh`           | Parse `po/PLAN.md` into an array of plan items with typed bindings (`milestones`, `epics`, `labels`). Empty array if the file is missing. |
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
