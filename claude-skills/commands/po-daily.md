Run a full autonomous PO tick on the current repository: triage tickets, organize milestones, audit PRs, clean stale items.

You are the **PO daily auditor**. Your job is to keep the backlog in order
without daily babysitting from the human: every open issue should belong to
a milestone, every milestone should have a credible due date, every PR
should be flowing, and every stale item should be either pinged or closed.

Delegate the work to the `po-manager` subagent with the brief below. Do
**not** re-implement the audit yourself — `po-manager` already owns the
scripts and the report convention.

## Brief to send to `po-manager`

Pass this prompt verbatim (substitute `{{TODAY}}` with `date +%F`, and
`{{REPO}}` with the current repo's `owner/name` from `gh repo view --json
nameWithOwner -q .nameWithOwner`):

> Daily PO tick on `{{REPO}}` — {{TODAY}}. Full-auto: execute every safe
> action yourself, only stop for genuinely ambiguous or destructive calls.
>
> **1. Audit (read-only).**
> - `bash scripts/collect.sh > /tmp/po-snap-{{TODAY}}.json`
> - `bash scripts/adherence.sh --snapshot /tmp/po-snap-{{TODAY}}.json` (if `po/PLAN.md` exists)
> - `bash scripts/milestone-progress.sh --snapshot /tmp/po-snap-{{TODAY}}.json`
> - `bash scripts/pr-flow.sh --snapshot /tmp/po-snap-{{TODAY}}.json`
> - `bash scripts/stale-issues.sh 14`
>
> **2. Auto-execute (mutate GitHub via `gh`):**
> - Assign every unmilestoned open issue to the best-matching milestone
>   (bucket by label prefix, title keywords, body context). If no milestone
>   fits, create a credible one with a T+90d due date — but only if at
>   least 3 issues belong in it. Single-issue buckets stay unmilestoned and
>   get a `❓` in the report.
> - Add `priorité:urgente` (create if missing, color `#B60205`) to issues
>   with a deadline ≤ 14 days mentioned in title/body/comments.
> - For each open PR: if review-pending > 3 days and the PR has no
>   reviewer, surface it in the report (do not auto-assign reviewers).
> - For stale issues > 30 days: post a French "toujours pertinent ?" ping
>   comment (one per issue) unless one was already posted in the last 14
>   days. Do not close.
> - Close any milestone that is 100% done with no open issues.
> - Delete labels orphaned on both open and closed issues (safety check:
>   keep any label with > 5 historical closed-issue uses; report them
>   instead).
>
> **3. Stop and ask only when:**
> - An issue could plausibly go in 2+ milestones and the wrong choice
>   would mislead downstream planning.
> - A stale issue has recent comments suggesting it might be revived.
> - A milestone is overdue and has open work — flag the slip, propose a
>   new due date, but don't move it without confirmation.
>
> **4. Write outputs to disk:**
> - `po/reports/{{TODAY}}-tick.md` — full report (adherence, milestones, PR
>   flow, stale, executed actions, open questions).
> - `po/reports/{{TODAY}}-todo.md` — checkbox list of every action,
>   ticked (☑) for done, `❓` for questions to Guillaume.
>
> **5. Commit and push:**
> - Branch `chore/po-tick-{{TODAY}}` from the repo's default branch.
> - Commit message: `chore(po): tick automatique {{TODAY}}`.
> - Open a PR titled `PO tick — {{TODAY}}` with the executive summary as
>   the body. Do not auto-merge.
>
> **6. Return a chat summary ≤ 200 words:**
> - Counts: created / assigned / labeled / pinged / closed.
> - Numbered list of any open questions for Guillaume.
> - PR URL.
>
> Constraints: never close an issue without explicit human approval. Never
> force-push. Never touch `main` directly. French in GitHub comments,
> bilingual OK in chat.

## Output discipline

- If `po-manager` reports zero open questions and zero risks, print only
  its one-line receipt (PR URL + counts). No further commentary.
- If there are open questions, surface them as a numbered list and stop —
  let Guillaume answer before any follow-up.
- If the agent errors out (missing `gh` auth, missing `po/` scripts, etc.),
  print the error verbatim and suggest the fix — do **not** retry blindly.

## Scheduling

Designed to be invoked daily. Options:

- Manual: `/po-daily` whenever you want a fresh tick.
- Local recurring: `/loop 24h /po-daily` while Claude Code is running.
- Cron-style remote: `/schedule` it via the schedule skill (recommended:
  weekdays 08:00 local).

## Rules

- **Repo-scoped.** Runs only against the current `gh repo view` repo.
- **Idempotent.** Re-running on the same day reuses the existing
  `chore/po-tick-{{TODAY}}` branch and updates the PR.
- **No destructive defaults.** Closing issues, deleting widely-used
  labels, or rewriting milestone scope always requires confirmation.
- **No GitHub Actions.** This is a human-driven (or schedule-driven)
  command, not CI.

---

## How to improve this skill

This file is the source of truth in
[beyond-scale-group/bsg-stack](https://github.com/beyond-scale-group/bsg-stack)
at `claude-skills/commands/po-daily.md`. The local copy at
`~/.claude/commands/po-daily.md` is overwritten on every BSG install
run — edit the source and PR.
