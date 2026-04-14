# PLAN.md schema — the "big plan" source of truth

`po/PLAN.md` is the **human-authored source of truth** for a project's
intent: objectives, milestones, epics, and decisions. The `po-report`
skill reads it and cross-references live GitHub state to compute
adherence — it **never writes back to this file**. Proposed changes
land in `po/drafts/` as markdown for a human to accept.

This document is the grammar the parser expects.

## File shape

Plain markdown. Any structure is fine; the parser only cares about
bullets that carry inline **binding tags** and the headings that
group them. A typical file:

```markdown
# Big plan — <repo-name>

## Objectives
- Ship the payments redesign by end of Q2   [milestone:Payments-v1]
- Migrate every service to Postgres 16       [epic:#142]
- Hire a DevRel engineer                     [label:hire:devrel]

## Milestones
- Payments-v1 — due 2026-06-30               [milestone:Payments-v1]
- Postgres migration done                    [milestone:pg16-done]

## Epics
- Payments redesign                          [epic:#142]
- Postgres 16 migration                      [epic:#287]

## Decision log
- 2026-03-04: defer mobile app to H2         [tag:decision]
- 2026-03-18: adopt Projects v2 for sprints  [tag:decision]
```

## Binding tag grammar

Any bullet line may carry one or more tags, each wrapped in square
brackets. The parser extracts them with a regex — order and
placement within the bullet are unconstrained.

| Tag | Meaning | Example |
|---|---|---|
| `[milestone:<title>]` | Bind this plan item to a GitHub milestone by title. Whitespace-sensitive, case-sensitive — must match the milestone on GitHub exactly. | `[milestone:Payments-v1]` |
| `[epic:#<num>]` | Bind to a GitHub issue that acts as an epic (parent of sub-issues or grouping of child issues). | `[epic:#142]` |
| `[#<num>]` | Shorthand for `[epic:#<num>]`. Use when the plan item is just "work on issue N". | `[#42]` |
| `[label:<name>]` | Bind to all issues / PRs carrying this label. Useful for cross-cutting initiatives that don't map to a single milestone or epic. | `[label:hire:devrel]` |
| `[tag:decision]` | Mark a decision-log entry. Adherence ignores these — they're narrative, not tracked work. | `[tag:decision]` |
| `[tag:risk]` | Mark a known risk item the PO is watching. Surfaces in the adherence report's "tracked risks" section. | `[tag:risk]` |
| `[tag:deferred]` | Mark an item deliberately deferred. Adherence treats it as "not started" and expects zero activity. | `[tag:deferred]` |

### Multiple bindings per bullet

A bullet with several tags joins across all of them:

```markdown
- Finish payments migration  [milestone:Payments-v1] [epic:#142] [label:area:payments]
```

The parser emits one plan item with `bindings: { milestones: [...], epics: [...], labels: [...] }`
and the adherence check considers the item resolved when *any* binding
shows activity.

### Bullets without any tag

Are treated as prose / context and ignored by the parser. The agent
will never fabricate a binding.

## Section headings

Headings are advisory — the parser doesn't enforce any specific
section names. But when rendering the adherence report, items under
these well-known headings get their section preserved for readability:

- `## Objectives`
- `## Milestones`
- `## Epics`
- `## Decision log`
- `## Risks` / `## Tracked risks`

## Parser output

`parse-plan.sh` emits a JSON array, one object per bullet that
contains at least one binding tag:

```json
[
  {
    "raw": "Ship the payments redesign by end of Q2",
    "section": "Objectives",
    "bindings": {
      "milestones": ["Payments-v1"],
      "epics": [],
      "labels": []
    },
    "tags": [],
    "line": 5
  }
]
```

## When no PLAN.md exists

The first invocation of the agent against a repo without `po/PLAN.md`
does **not** create one silently. It writes
`po/drafts/PLAN-suggested-<date>.md` with a proposed starter plan
derived from the README, existing milestones, and top-label clusters.
The human reviews, edits, and renames (or `git mv`s) the draft to
`po/PLAN.md`. Only then does subsequent adherence reporting activate.

---

## How to improve this skill

This file is a cached copy of `claude-skills/skills/po-report/references/plan-schema.md` in
[beyond-scale-group/bsg-stack](https://github.com/beyond-scale-group/bsg-stack).
That repo is the single source of truth — `~/.claude/skills/po-report/references/plan-schema.md` is
overwritten every time the BSG install flow runs.

If the user asks you to improve, fix, or extend this skill, do **not** edit
the local file. Instead:

1. `gh repo clone beyond-scale-group/bsg-stack` (or work in an existing clone)
2. Edit `claude-skills/skills/po-report/references/plan-schema.md` on a feature branch
3. Open a pull request against `main`

Bug reports and ideas without a fix → open an issue on the same repo.
