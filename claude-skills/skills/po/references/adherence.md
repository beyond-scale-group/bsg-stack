# Plan adherence workflow

Use this when the user asks "how are we tracking against the plan",
"où en est le plan", "what's drifting", "is the project on-course",
or any request that compares intent (`po/PLAN.md`) to reality (the
live snapshot from `collect.sh`).

Adherence is the **headline** of every PO report. Counts, stale
tickets, and milestone progress are supporting evidence below it.

## Preconditions

**Never check for PLAN.md by path directly.** Always use the script:

```bash
bash scripts/parse-plan.sh --typed | jq -r .status
# "ok"      → plan found and parseable, proceed
# "missing" → route to bootstrap flow below
# "unparseable" → plan exists but has no binding tags; treat as missing
```

`parse-plan.sh` resolves `.bsg/PLAN.md` first (preferred), then falls
back to `po/PLAN.md` (legacy). Checking the path manually breaks repos
that store the plan under `.bsg/` — the script is the only correct probe.

## Steps

1. **Collect once** if you don't already have a snapshot:

   ```bash
   bash scripts/collect.sh > /tmp/snap.json
   ```

2. **Run adherence**:

   ```bash
   bash scripts/adherence.sh --snapshot /tmp/snap.json
   ```

   Emits JSON with:
   - `planFound` — boolean.
   - `items[]` — each plan item with `status`, `counts`, `evidence`.
   - `drift.scopeCreep` — open issues / non-draft PRs with no binding.
   - `drift.abandonedItems` — plan items resolved to `not_started`
     despite having bindings.
   - `drift.offCourse` — plan items bound to overdue milestones with
     zero open work.
   - `summary` — totals per status + scope-creep count.

3. **Render the report**. The full `generate-report.sh` already splices
   the adherence section at the top, so for a full report just:

   ```bash
   bash scripts/generate-report.sh > po/reports/$(date +%F)-status.md
   ```

   For an adherence-only deep dive, render just the matrix:

   ```bash
   bash scripts/adherence.sh --snapshot /tmp/snap.json \
     | jq -r -f scripts/render-adherence.jq
   ```

4. **Reply with the headline summary**:
   - Count per status (`done / in-progress / at-risk / not-started`).
   - Total scope-creep items.
   - Top 3 most-urgent drift entries (overdue / abandoned / scope-creep).
   - File path to the saved report.

## Status meanings

| Status | Condition |
|---|---|
| `done` | Every binding is fully closed; at least one closed signal present. |
| `in_progress` | Any binding has mixed open/closed activity. |
| `at_risk` | Any milestone binding is flagged `at_risk` or `overdue`. |
| `not_started` | Every binding has zero matching items, or no bindings. |

## Drift classes

- **Scope creep** — open issues / non-draft PRs not referenced by any
  `[milestone:]`, `[epic:#N]`, `[#N]`, or `[label:]` binding. Might be
  legitimate (bug fixes, chores) — use `unplanned_work_ignore_labels`
  in `po/config.yml` to filter routine categories.
- **Abandoned plan items** — plan items with bindings but zero evidence
  anywhere. Probably forgotten or deferred; propose to the user.
- **Off-course** — milestone-bound plan items where the milestone is
  overdue AND has zero open work. Milestone was supposed to be active;
  nothing's happening.

## Bootstrap flow — when PLAN.md is missing

1. Do **not** create `po/PLAN.md` or `.bsg/PLAN.md` directly. Instead:

   ```bash
   mkdir -p po/drafts
   bash scripts/bootstrap-plan.sh --snapshot /tmp/snap.json \
     > "po/drafts/PLAN-suggested-$(date +%F).md"
   ```

2. Tell the user where the draft lives and ask them to review + rename:

   ```
   Drafted a starter plan from your milestones and top labels:
     po/drafts/PLAN-suggested-2026-04-14.md

   Edit it, then move to .bsg/PLAN.md (preferred) to activate adherence tracking.
   po/PLAN.md also works but .bsg/PLAN.md is the canonical location.
   ```

3. **Never** post to GitHub as part of bootstrap. The draft is local
   markdown only, committed to the tracked repo for auditability.

## Confirming actions

Adherence reporting is **observation only**. If the user asks to *act*
on drift findings (close stale issues, request reviews, reschedule
milestones), confirm each action before running `gh`. Proactive
proposals go to `po/drafts/triage-<date>.md`, never to GitHub.

---

## How to improve this skill

This file is a cached copy of `claude-skills/skills/po/references/adherence.md` in
[beyond-scale-group/bsg-stack](https://github.com/beyond-scale-group/bsg-stack).
That repo is the single source of truth — `~/.claude/skills/po/references/adherence.md` is
overwritten every time the BSG install flow runs.

If the user asks you to improve, fix, or extend this skill, do **not** edit
the local file. Instead:

1. `gh repo clone beyond-scale-group/bsg-stack` (or work in an existing clone)
2. Edit `claude-skills/skills/po/references/adherence.md` on a feature branch
3. Open a pull request against `main`

Bug reports and ideas without a fix → open an issue on the same repo.
