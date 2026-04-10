---
name: po-report
description: >
  Product owner reporting and project status for the current GitHub repository.
  Use when the user asks to "generate a PO report", "où en est le projet",
  "project status", "milestone progress", "rapport produit", "list stale issues",
  "burndown", "what's blocking us", "sprint health", or any request for an
  aggregated view of GitHub issues, milestones, labels, or assignees.
  Produces a dated markdown report in .claude/reports/ and prints a summary.
version: 0.1.0
---

# Product Owner Report

Aggregates GitHub state for the **current repository** and produces an
actionable progress report. All heavy lifting is done by bash scripts in
`scripts/` — use them instead of re-deriving data through ad-hoc `gh` calls.

## Intent routing

Read the user's request and pick the matching reference document:

| If the user asks about...                          | Read this reference        |
| -------------------------------------------------- | -------------------------- |
| Overall status / health / "où en est le projet"    | `references/status.md`     |
| Milestone progress, sprint health, burndown        | `references/milestones.md` |
| Stale issues, no recent activity, abandoned work   | `references/stale.md`      |

For multi-topic requests (e.g. "give me a full report"), follow `references/status.md`
which itself orchestrates the others.

## Hard rules

1. **Never invent numbers.** Always read them from the scripts' JSON output.
2. **Always write the final report to `.claude/reports/YYYY-MM-DD-{slug}.md`** so
   it is dated and version-controllable.
3. **Run scripts from the repo root.** They use `gh` which auto-detects the repo.
4. **Do not call `gh issue list` or `gh api` yourself** for aggregation — use
   the scripts. Direct `gh` calls are reserved for follow-up actions on a
   specific ticket the user named.
5. **Confirm before posting** anywhere external (GitHub comments, etc.). Default
   is local-only.

## Available scripts

All scripts live in `scripts/` and emit JSON on stdout (except `generate-report.sh`
which emits markdown). Run them with `bash scripts/<name>.sh [args]`.

| Script                    | Purpose                                                    |
| ------------------------- | ---------------------------------------------------------- |
| `status.sh`               | Repo-wide counts: open/closed issues, PRs, by label, etc.  |
| `milestone-progress.sh`   | For each open milestone: total/closed/open + % complete   |
| `stale-issues.sh [DAYS]`  | Open issues with no activity for N days (default: 14)     |
| `generate-report.sh`      | Composes a full markdown report from the above scripts    |

## Output convention

Reports go to `.claude/reports/`. Filename pattern:

```
.claude/reports/2026-04-10-status.md
.claude/reports/2026-04-10-milestone-v1.md
.claude/reports/2026-04-10-stale.md
```

Use today's date. After writing, print the file path and a 3-bullet executive
summary in the chat — do **not** dump the full report inline.

---

## How to improve this skill

This file is a cached copy of `claude-skills/skills/po-report/SKILL.md` in
[beyond-scale-group/bsg-workflows](https://github.com/beyond-scale-group/bsg-workflows).
That repo is the single source of truth — `~/.claude/skills/po-report/SKILL.md` is
overwritten every time the BSG install flow runs.

If the user asks you to improve, fix, or extend this skill, do **not** edit
the local file. Instead:

1. `gh repo clone beyond-scale-group/bsg-workflows` (or work in an existing clone)
2. Edit `claude-skills/skills/po-report/SKILL.md` on a feature branch
3. Open a pull request against `main`

Bug reports and ideas without a fix → open an issue on the same repo.
