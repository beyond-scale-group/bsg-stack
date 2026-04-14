# PO Agent — Implementation Plan (v4)

**Status:** approved outline, not yet implemented
**Owner:** `claude-skills/agents/po-manager.md` + `claude-skills/skills/po-report/`
**Scope:** Product Owner agent that runs inside any `beyond-scale-group/*` repo, stores its data and plan updates in that repo, and is launchable repo-by-repo.
**Smoke-test target:** `beyond-scale-group/edomata`

---

## 1. Principles

1. **One repo, one Product Owner Agent, one plan.** No central portfolio folder, no cross-repo rollup in this plan.
2. **Facts come from one GraphQL snapshot per run.** Every report is a pure jq transform of that snapshot — reproducible, diff-friendly, zero re-queries.
3. **Git history is the trend store.** Snapshots and reports are committed, so burndown / velocity / scope-delta are computed from `git log` — no separate database.
4. **Scripts before LLM.** Risk flags, tree walks, and metrics are computed in bash + jq. The agent only narrates.
5. **Skill code stays in `bsg-stack`; data stays in each tracked repo.** `bsg-stack` is the single source of truth for the skill; each tracked repo owns its own `po/` directory.

## 2. Data layout — inside each tracked repo

Stored at the **root** of the tracked repo (not under `.claude/`), and committed:

```
<tracked-repo>/
└── po/
    ├── config.yml                 # optional per-repo overrides
    ├── MAP.md                     # planning map — regenerated every run
    ├── PLAN.md                    # current-sprint plan — agent writes, humans edit
    ├── reports/
    │   └── YYYY-MM-DD-status.md   # dated snapshots, append-only
    └── history/
        └── YYYY-MM-DD.json        # full GraphQL snapshot, append-only
```

- `MAP.md` and `PLAN.md` are overwritten each run. `PLAN.md` preserves sections marked `<!-- human-edited -->` on regeneration.
- `reports/` and `history/` are append-only. Past files are never modified.
- Everything is committed to the tracked repo (per Guillaume's decision — traceability).

## 3. Per-repo configuration — `po/config.yml`

All fields optional; defaults documented in `references/setup.md`.

```yaml
sprint_source: milestones        # or: projectv2
projectv2_number: null
stale_days: 14
priority_labels: [priority:high, bug]
status_labels: [status:blocked, status:in-review]
ignore_labels: [duplicate, wontfix]
commit_reports: true
```

## 4. Code layout — in `bsg-stack`

```
bsg-stack/
└── claude-skills/
    ├── agents/po-manager.md      # routing + per-repo scope; updated paths
    └── skills/po-report/
        ├── SKILL.md
        ├── references/
        │   ├── status.md         # existing — paths updated to po/
        │   ├── milestones.md     # existing — paths updated
        │   ├── stale.md          # existing
        │   ├── epic-map.md       # NEW
        │   ├── pr-flow.md        # NEW
        │   ├── health-audit.md   # NEW
        │   └── setup.md          # NEW — @po-manager usage, scopes, first-time init
        └── scripts/
            ├── collect.sh        # ONE paginated GraphQL query → history/*.json
            ├── status.sh         # thin wrapper over collect.sh (compat)
            ├── milestone-progress.sh
            ├── stale-issues.sh
            ├── epic-tree.sh      # NEW — sub-issues → tree + %
            ├── pr-flow.sh        # NEW — review latency, merge queue, CI
            ├── health-audit.sh   # NEW — dependabot, branch protection
            ├── render-status.sh  # JSON → dated status.md
            ├── render-map.sh     # JSON → MAP.md (overwrite)
            └── render-plan.sh    # JSON → PLAN.md (merge-preserve)
```

## 5. The one GraphQL query

`collect.sh` fetches all data needed by every downstream report in one paginated query and writes the full result to `po/history/<date>.json`. Fields:

| Entity | Fields |
|---|---|
| Issues | `number, title, state, stateReason, issueType, labels, milestone, assignees, reactions{THUMBS_UP}, subIssues, trackedInIssues, timelineItems(CLOSED_EVENT, LABELED_EVENT), lastCommentedAt` |
| Pull requests | `number, state, isDraft, reviewDecision, reviews, mergeStateStatus, mergeQueueEntry, statusCheckRollup, closingIssuesReferences, createdAt, mergedAt` |
| Milestones | `title, dueOn, progressPercentage, openIssueCount, closedIssueCount` |
| Releases | `tagName, publishedAt` |
| Branch protection | `pattern, requiredStatusCheckContexts, requiresApprovingReviews` |
| Vulnerability alerts | `securityVulnerability, dismissedAt` (needs `security_events` scope) |
| Repo metadata | `topics, defaultBranchRef.target.history(first: 100)` |

All downstream reports are **pure jq** against this file. No re-queries.

## 6. Reports produced

| File | When | Contents |
|---|---|---|
| `po/reports/<date>-status.md` | Every run | At-a-glance metrics, top labels, assignee load, milestone progress, stale issues, oldest PR |
| `po/MAP.md` | Every run (overwritten) | Now / Sprint / Epics / Next up / Blocked / Shipped recently / Risks |
| `po/PLAN.md` | Every run (merge-preserve) | Current sprint plan with human-editable sections preserved |
| `po/history/<date>.json` | Every run | Full GraphQL snapshot (audit + trend source) |

`MAP.md` is the "best planning mapping" artifact: parent issues → sub-issue trees → linked PRs → CI state, grouped by status.

## 7. Launch modes — all per-repo, all user-initiated

No CI automation. The agent runs only when a human asks for it, from inside the tracked repo.

1. **Interactive with `@agent` mention** (primary path). Inside `<tracked-repo>`, in any Claude Code session:

   ```
   @po-manager give me the full status
   @po-manager où en est le sprint
   @po-manager list stale issues over 30 days
   @po-manager rebuild the planning map
   ```

   The `@po-manager` mention hands the turn to the subagent defined in `claude-skills/agents/po-manager.md`. It runs the `po-report` skill's scripts, writes to `po/`, and returns a 3-bullet summary + the report path.

2. **Headless one-shot.** From any shell inside the tracked repo:

   ```bash
   claude -p "@po-manager run a full status report and commit the results"
   ```

   Useful for a user-side cron or an ad-hoc catch-up run. Same behavior as interactive; no session UI.

Documented in `claude-skills/agents/po-manager.md` and `references/setup.md`. No GitHub Actions, no secrets, no scheduled workflow.

## 8. Required GitHub scopes

```
gh auth refresh -h github.com -s read:org,repo,read:project,security_events
```

Documented in `references/setup.md`. Private repos, Projects v2, and Dependabot alerts all require these.

## 9. Phasing — three PRs against `bsg-stack`

### PR 1 — Refactor collector to GraphQL, fix known bugs
- Replace every REST `gh issue list` loop in `status.sh` with one paginated GraphQL query in `collect.sh`.
- Emit risk flags (`at_risk`, `overdue`, `understaffed`, `stalled`) from jq in `milestone-progress.sh` — currently documented but not computed.
- Fix multi-assignee aggregation (`.assignees[].login`, not `[0]`).
- Use `lastCommentedAt` instead of `updatedAt` in `stale-issues.sh` so bot label bumps don't reset staleness.
- Add PR review metrics (time-to-first-review, review decision mix, merge-queue depth, oldest draft).
- Update paths from `.claude/reports/` to `po/reports/`.
- Add `tests/test_po_report.py` with fixture-based tests (PATH-shimmed `gh`).
- Smoke-test against `beyond-scale-group/edomata`. Auto-memory is already off and Context7 is available in the test session because the BSG updater merges those keys into `~/.claude/settings.json` globally — no per-repo setup needed.

### PR 2 — Planning map, plan, epic tree, PR flow, health audit
- Add `render-map.sh`, `render-plan.sh`, `epic-tree.sh`, `pr-flow.sh`, `health-audit.sh`.
- Add references: `epic-map.md`, `pr-flow.md`, `health-audit.md`, `setup.md`.
- Update `po-manager.md` routing: "planning map", "epic status", "PR health", "security debt".
- `PLAN.md` merge logic: preserves any section fenced with `<!-- human-edited -->`.
- Document the `@po-manager` invocation pattern in `setup.md` and in the top of `po-manager.md`.

### PR 3 — Projects v2 path + polish
- `sprint_source: projectv2` branch in `milestone-progress.sh` and `render-map.sh`.
- French-localized summaries in `render-status.sh` (matches bilingual triggers already in `po-manager.md`).
- Velocity and scope-delta computed from `git log` of `po/history/*.json`.

## 10. Open items

- **`po/` vs `.claude/po/`.** Chosen `po/` at root (per Guillaume). The existing `SKILL.md` and `po-manager.md` still reference `.claude/reports/` — updated in PR 1.

## 11. Validation checklist (for PR 1 smoke test)

Against `beyond-scale-group/edomata`:

- [ ] `collect.sh` produces a valid `po/history/<date>.json` in one run.
- [ ] `status.sh` (wrapped over collect) matches the pre-refactor numbers within rounding.
- [ ] Multi-assignee issues contribute to each assignee's count (regression check).
- [ ] `milestone-progress.sh` emits risk flags for at least one milestone with a past due date or low progress.
- [ ] `stale-issues.sh` ignores issues whose only recent `updatedAt` bump is a label change by a bot.
- [ ] Fixture-based unit tests pass locally.
