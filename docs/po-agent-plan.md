# PO Agent — Implementation Plan (v5)

**Status:** approved outline, not yet implemented
**Owner:** `claude-skills/agents/po-manager.md` + `claude-skills/skills/po/`
**Scope:** Product Owner agent that runs inside any `beyond-scale-group/*` repo, compares that repo's **big plan** (`po/PLAN.md`, authored by humans) against **live GitHub state**, and reports drift. Launchable repo-by-repo, pure Claude-driven.
**Smoke-test target:** `beyond-scale-group/edomata`

---

## 1. Mental model — what the PO agent is actually for

The PO agent exists to answer **"is this project still following its plan?"** — not "what happened this week."

That splits the artifacts in `po/` into three roles:

| Role | File | Who authors it | Mutability |
|---|---|---|---|
| **Intent** | `po/PLAN.md` | Humans (agent may propose drafts into `po/drafts/`) | Human-edited, rarely. |
| **Reality** | `po/MAP.md` | Agent, from live GitHub state | Overwritten every run. |
| **Adherence** | `po/reports/<date>-status.md` | Agent | Append-only dated snapshot — the diff between Intent and Reality. |
| **Trend source** | `po/history/<date>.json` | Agent (raw GraphQL snapshot) | Append-only; `git log` on this folder = trend store. |

The **adherence report** is the headline output. Counts and tables are supporting evidence.

## 2. Principles

1. **One repo, one agent, one plan.** No central portfolio folder, no cross-repo rollup.
2. **Pure Claude-driven, per-repo, on-demand.** No CI automation (see root `CLAUDE.md`).
3. **`PLAN.md` is input, never output.** The agent reads it, cross-references live state, reports drift. It never overwrites it. Proposed changes land in `po/drafts/` for a human to accept.
4. **Facts come from one GraphQL snapshot per run.** Every report is a pure jq transform of that snapshot.
5. **Git history is the trend store.** Reports and snapshots are committed; burndown / velocity / scope-delta come from `git log po/history/`.
6. **Scripts before LLM.** Risk flags, drift detection, and metrics are computed in bash + jq. The agent narrates.
7. **Propose, never post.** Agent output always lands as committed markdown. `gh` is only called to *fetch*; anything externally-visible (comments, labels, closes) requires explicit human confirmation.

## 3. Data layout — inside each tracked repo

```
<tracked-repo>/
└── po/
    ├── PLAN.md                       # HUMAN-AUTHORED source of truth (intent)
    ├── config.yml                    # optional per-repo overrides
    ├── MAP.md                        # agent-generated current state (reality)
    ├── reports/
    │   └── YYYY-MM-DD-status.md      # adherence report, append-only
    ├── history/
    │   └── YYYY-MM-DD.json           # raw GraphQL snapshot, append-only
    └── drafts/                       # agent proposals awaiting human review
        ├── PLAN-suggested-YYYY-MM-DD.md
        ├── triage-YYYY-MM-DD.md
        └── sprint-plan-YYYY-MM-DD.md
```

- `PLAN.md`, `MAP.md`, and the contents of `reports/` / `history/` / `drafts/` are committed to the tracked repo.
- `PLAN.md` is the **only** file in `po/` the agent never writes to. It appears there after a human accepts the initial draft from `drafts/PLAN-suggested-*.md` (or writes one from scratch).

## 4. `PLAN.md` schema

Plain markdown with **inline binding tags** so the parser can cross-reference live GitHub state without fighting a complex format.

```markdown
# Big plan — <repo-name>

## Objectives
- Ship the payments redesign by end of Q2   [milestone:Payments-v1]
- Migrate every service to Postgres 16       [epic:#142]
- Hire a DevRel engineer                     [label:hire:devrel]

## Milestones
- Payments-v1 — due 2026-06-30                [milestone:Payments-v1]
- Postgres migration done                     [milestone:pg16-done]

## Epics
- Payments redesign                           [epic:#142]
- Postgres 16 migration                       [epic:#287]

## Decision log
- 2026-03-04: defer mobile app to H2         [tag:decision]
```

**Inline tag grammar** (all optional on any bullet):
- `[milestone:<title>]` — binds the item to a GitHub milestone.
- `[epic:#<num>]` or `[#<num>]` — binds to a parent issue (epic) by number.
- `[label:<name>]` — binds to a label query.
- `[tag:decision]`, `[tag:risk]`, `[tag:deferred]` — free-form markers, used for filtering.

Chosen over YAML frontmatter because humans write and edit this file directly; inline tags keep the document readable. Revisable if parsing gets brittle.

## 5. The adherence report (headline section)

For every item in `PLAN.md`, the agent computes a status from the live snapshot:

| Plan item | Binding | Status | Evidence |
|---|---|---|---|
| Ship payments redesign | milestone:Payments-v1 | **At risk** | 40% done, due in 3d |
| Migrate to Postgres 16 | epic:#287 | On track | 6/10 sub-issues closed, PR #312 open |
| Hire DevRel | label:hire:devrel | Not started | 0 issues with label |
| (unplanned) CI flake fix | — | In progress | 3 PRs, no plan anchor |

**Three drift classes** get their own subsection:

- **Plan → ∅ (abandoned)**: plan items with 0 GitHub activity for > N days.
- **∅ → Reality (scope creep)**: in-flight issues/PRs not bound to any plan item.
- **Plan ≠ Reality (off-course)**: plan item is supposed to be in-flight but the milestone/label shows it isn't, or vice-versa.

## 6. Per-repo configuration — `po/config.yml`

All fields optional; defaults documented in `references/setup.md`.

```yaml
plan_path: po/PLAN.md
sprint_source: milestones              # or: projectv2
projectv2_number: null
stale_days: 14
abandoned_plan_item_days: 30           # drift threshold for "Plan → ∅"
priority_labels: [priority:high, bug]
status_labels: [status:blocked, status:in-review]
ignore_labels: [duplicate, wontfix]
unplanned_work_ignore_labels: [chore, dependencies]   # routine work that doesn't need plan anchoring
commit_reports: true
```

## 7. Code layout — in `bsg-stack`

```
bsg-stack/
└── claude-skills/
    ├── agents/po-manager.md          # routing + per-repo scope; paths → po/
    └── skills/po/
        ├── SKILL.md
        ├── references/
        │   ├── adherence.md          # NEW — primary reference (plan vs reality)
        │   ├── plan-schema.md        # NEW — PLAN.md tag grammar + bootstrap
        │   ├── status.md             # existing — demoted to "supporting evidence"
        │   ├── milestones.md
        │   ├── stale.md
        │   ├── epic-map.md           # NEW
        │   ├── pr-flow.md            # NEW
        │   ├── health-audit.md       # NEW
        │   └── setup.md              # NEW — @po-manager usage, scopes
        └── scripts/
            ├── collect.sh            # ONE paginated GraphQL query → history/*.json
            ├── parse-plan.sh         # NEW — PLAN.md → JSON of plan items + bindings
            ├── adherence.sh          # NEW — join plan items with snapshot → matrix + drift
            ├── milestone-progress.sh
            ├── stale-issues.sh
            ├── epic-tree.sh          # NEW — sub-issues → tree + %
            ├── pr-flow.sh            # NEW — review latency, merge queue, CI
            ├── health-audit.sh       # NEW — dependabot, branch protection
            ├── bootstrap-plan.sh     # NEW — propose drafts/PLAN-suggested-<date>.md
            ├── render-status.sh      # JSON → dated adherence report
            ├── render-map.sh         # JSON → MAP.md (overwrite)
            └── render-drafts.sh      # JSON → triage / sprint-plan proposals
```

## 8. The one GraphQL query

`collect.sh` fetches every field any downstream report needs and writes one file per run to `po/history/<date>.json`. All reports are pure jq transforms of this file — no re-queries.

| Entity | Fields |
|---|---|
| Issues | `number, title, state, stateReason, issueType, labels, milestone, assignees, reactions{THUMBS_UP}, subIssues, trackedInIssues, timelineItems(CLOSED_EVENT, LABELED_EVENT), lastCommentedAt` |
| Pull requests | `number, state, isDraft, reviewDecision, reviews, mergeStateStatus, mergeQueueEntry, statusCheckRollup, closingIssuesReferences, createdAt, mergedAt` |
| Milestones | `title, dueOn, progressPercentage, openIssueCount, closedIssueCount` |
| Releases | `tagName, publishedAt` |
| Branch protection | `pattern, requiredStatusCheckContexts, requiresApprovingReviews` |
| Vulnerability alerts | `securityVulnerability, dismissedAt` (needs `security_events` scope) |
| Repo metadata | `topics, defaultBranchRef.target.history(first: 100)` |

## 9. Launch modes — all per-repo, all user-initiated

Unchanged from v4: `@po-manager <request>` inside a Claude Code session, or `claude -p "@po-manager ..."` for a headless one-shot. No CI automation.

After writing its outputs, the agent **stages and commits** the updated `po/` files with a conventional message (`chore(po): <date> <slug>`). Pushing stays a human decision.

Example prompts:

```
@po-manager how are we tracking against the plan?
@po-manager où en est le plan ?
@po-manager what's drifting?
@po-manager propose a starter PLAN.md — no plan exists yet
@po-manager draft the triage queue for today
```

## 10. Required GitHub scopes

```
gh auth refresh -h github.com -s read:org,repo,read:project,security_events
```

Documented in `references/setup.md`.

## 11. Phasing — three PRs against `bsg-stack`

### PR 1 — Refactor collector to GraphQL, fix known bugs, move to `po/`

Mechanical cleanup, no plan-adherence logic yet.

- Replace every REST `gh issue list` loop in `status.sh` with one paginated GraphQL query in `collect.sh`.
- Emit risk flags (`at_risk`, `overdue`, `understaffed`, `stalled`) from jq in `milestone-progress.sh` — currently documented but not computed.
- Fix multi-assignee aggregation (`.assignees[].login`, not `[0]`).
- Use `lastCommentedAt` instead of `updatedAt` in `stale-issues.sh` so bot label bumps don't reset staleness.
- Add PR review metrics (time-to-first-review, review decision mix, merge-queue depth, oldest draft).
- Update paths from `.claude/reports/` to `po/reports/` + `po/history/` + `po/MAP.md`.
- Extend the integration test (`test_po_report_integration.py`) with structural assertions on the new GraphQL output fields.
- Smoke-test against `beyond-scale-group/edomata`. Auto-memory is already off and Context7 is available globally via the BSG updater merge.

### PR 2 — Plan-adherence engine (the point of this project)

- Define and document the `PLAN.md` inline-tag grammar in `references/plan-schema.md`.
- `parse-plan.sh` — read `po/PLAN.md`, emit JSON of plan items with their bindings.
- `adherence.sh` — join plan items with `history/<date>.json`; compute status per item + the three drift classes.
- `render-status.sh` — the adherence matrix is now the **headline section** of every report; the old count tables move to "supporting evidence" at the bottom.
- `bootstrap-plan.sh` — when no `PLAN.md` exists, draft one from README + milestones + top labels → `po/drafts/PLAN-suggested-<date>.md`. Human accepts by `mv`-ing it to `po/PLAN.md`.
- `render-drafts.sh` — `po/drafts/triage-<date>.md` and `po/drafts/sprint-plan-<date>.md` with concrete proposed actions (assign, label, close, reschedule) — always committed markdown, never posted.
- Update `po-manager.md` routing: "how are we tracking the plan", "what's drifting", "propose a plan", "draft today's triage".
- `MAP.md` and `PLAN.md` paths coexist but PLAN.md is never overwritten by the agent.

### PR 3 — Trends, epic trees, PR flow, health audit, Projects v2

- `epic-tree.sh` — sub-issue graph + % complete per epic, rendered into `MAP.md`.
- `pr-flow.sh` — review latency p50/p90, oldest draft, merge-queue depth.
- `health-audit.sh` — Dependabot + branch-protection audit.
- Velocity and scope-delta computed from `git log po/history/*.json`.
- `sprint_source: projectv2` alternative in `adherence.sh` and `milestone-progress.sh`.
- French-localized summaries in `render-status.sh` (matches bilingual triggers in `po-manager.md`).

## 12. Open items

- **PLAN.md tag grammar**: inline tags chosen for human writability. Revisit if the parser needs stricter structure.
- **Bootstrap confidence**: the first `bootstrap-plan.sh` output will be rough; iterating on the prompt is part of PR 2.
- **PLAN.md ownership**: humans commit changes to it. The agent detects PLAN.md edits via `git log` and reports "plan last updated Xd ago" in every adherence report so stale plans are visible.
- **Existing `SKILL.md` / `po-manager.md` paths** still reference `.claude/reports/` — fixed in PR 1.

## 13. Validation checklist

### PR 1 smoke test (against `beyond-scale-group/edomata`)
- [ ] `collect.sh` produces a valid `po/history/<date>.json` in one run.
- [ ] `status.sh` (wrapped over collect) matches pre-refactor numbers within rounding.
- [ ] Multi-assignee issues contribute to each assignee's count.
- [ ] `milestone-progress.sh` emits risk flags for at least one milestone with a past due date or low progress.
- [ ] `stale-issues.sh` ignores issues whose only recent `updatedAt` bump is a label change by a bot.
- [ ] Integration test in CI still green.

### PR 2 smoke test (against `beyond-scale-group/edomata`)
- [ ] With a hand-written `po/PLAN.md` containing 3 items (one milestone binding, one epic binding, one label binding), `adherence.sh` emits a matrix with correct statuses.
- [ ] Running against a repo with no `PLAN.md` produces `po/drafts/PLAN-suggested-<date>.md` — not `po/PLAN.md`.
- [ ] "Scope creep" drift class surfaces at least one unplanned open PR.
- [ ] "Abandoned plan item" drift class surfaces a plan item bound to an untouched label.
- [ ] `po/drafts/triage-<date>.md` exists and contains zero `gh` side-effects in its implementation.
