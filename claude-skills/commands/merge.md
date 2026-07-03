---
name: merge
description: >-
  Signal a pull request is ready for peer review: run local preflight, take it out of draft, and request a reviewer. Auto-runs /ship first when no PR exists yet.
model: haiku
---
Signal the current branch's pull request is ready for peer review: run local
preflight, flip it out of draft, and request a reviewer. If the branch has no
open PR yet, run the `/ship` pipeline first to create one, then continue.
$ARGUMENTS

You are the **merge** command. Your job is *not* to merge code into the base
branch — that is a human decision (or `/ship_and_merge`'s job when a repo
explicitly wants the full auto-merge pipeline). Your job is to tell your
peers "this is ready": verify it locally one more time, flip GitHub's draft
status to ready-for-review, and get a reviewer assigned.

## Argument parsing

Typical forms:
- `/merge` — preflight, ready-for-review, auto-assign a reviewer
- `/merge --skip-checks` — skip local preflight, go straight to ready + reviewer
- `/merge --reviewer <github-handle>` — request a specific reviewer instead
  of the configured preferred list (repeatable for multiple reviewers)

When the branch has no open PR yet, any of these forms first runs the
`/ship` pipeline to create one (see step 0), then proceeds normally.

## Steps

### 0. Sanity checks

- Must be inside a git repository (`git rev-parse --show-toplevel`).
- Must NOT be on the base/target branch.
- Find the open PR for the current branch:
  `gh pr view --json number,url,isDraft,headRefName,author 2>/dev/null`
  - If there is no open PR, do **not** stop — run the full `/ship` pipeline
    (see `claude-skills/commands/ship.md`) to preflight, commit, push, and
    open the PR, then continue with the steps below against the PR it
    created. Forward relevant flags: `--skip-checks` passes through to
    `/ship`, and since `/merge` flips the PR to ready itself, have `/ship`
    create the PR as a draft (`--draft`) so there is no window where an
    unreviewed PR sits ready without a reviewer.
  - If `/ship` stops (red preflight, nothing to commit and no commits ahead
    of the base branch, or refused on the base branch), stop too and relay
    its error — there is no PR to operate on.
  - When `/ship` just ran its preflight green, skip step 1 below — re-running
    the same checks back-to-back is pure waste.

### 1. Preflight (unless `--skip-checks`)

Run the same toolchain-detection preflight as `/ship` step 2 (lint,
typecheck, tests — auto-detected from `package.json` / `Makefile` /
`pyproject.toml` / etc., skipping any check whose tool isn't present).

**On failure:** stop, show the error output, and tell the user what failed.
Do NOT flip the PR to ready or request a reviewer on a red preflight. Offer
to fix the issue or re-run with `--skip-checks`.

### 2. Take the PR out of draft

- If `isDraft` is `true`: `gh pr ready <pr-number>`
- If already ready: no-op, continue.

### 3. Request a reviewer

Reviewer selection, in order:

1. If `--reviewer <handle>` was passed (one or more times), use exactly
   those handles — skip auto-selection entirely.
2. Otherwise, read a `preferred_reviewers:` list (ordered, most-preferred
   first) from `.bsg/AUTOPILOT.yml` at the repo root, if present.
3. Walk the list in order and pick the **first available** candidate:
   - Skip the PR author (can't review your own PR).
   - Skip anyone GitHub reports as unavailable to review (e.g. no repo
     access) — check via `gh api repos/{owner}/{repo}/collaborators/{user}
     --silent` (204 = has access) before requesting.
   - "Available" beyond repo access (out-of-office, at capacity, etc.) is
     not something `gh`/GitHub exposes generically — if the repo's
     `.bsg/AUTOPILOT.yml` doesn't define an availability signal, treat repo
     access as the only availability check.
4. If no `preferred_reviewers:` list is configured and no `--reviewer` was
   passed, fall back to `gh pr edit <n> --add-reviewer` with GitHub's own
   suggested reviewers if any are returned by
   `gh api repos/{owner}/{repo}/pulls/{n}/requested_reviewers`; otherwise
   leave the PR unassigned and say so in the final report — don't guess at
   names that aren't configured anywhere.
- Assign with: `gh pr edit <pr-number> --add-reviewer <handle>[,<handle>...]`

### 4. Report

One-line summary:

```
Ready for review: PR #<n> (<url>) — reviewer: @<handle>
```

Or if no reviewer could be determined:

```
Ready for review: PR #<n> (<url>) — no reviewer assigned (configure preferred_reviewers in .bsg/AUTOPILOT.yml)
```

## Hard rules

- **Never** merge the PR into the base branch. That is not this command's
  job — see `/ship_and_merge` for the opt-in auto-merge pipeline, or leave
  the actual merge to a human.
- **Never** guess at reviewer usernames. Only assign handles that came from
  `--reviewer`, `.bsg/AUTOPILOT.yml`'s `preferred_reviewers:`, or GitHub's
  own suggested-reviewers API.
- **Never** flip a PR to ready-for-review on a failing preflight.
- **Never** bypass required status checks or reviews.

---

## How to improve this skill

This file is a cached copy of `claude-skills/commands/merge.md` in
[beyond-scale-group/bsg-stack](https://github.com/beyond-scale-group/bsg-stack).
That repo is the single source of truth — `~/.claude/commands/merge.md` is
overwritten every time the BSG install flow runs.

If the user asks you to improve, fix, or extend this skill, do **not** edit
the local file. Instead:

1. `gh repo clone beyond-scale-group/bsg-stack` (or work in an existing clone)
2. Edit `claude-skills/commands/merge.md` on a feature branch
3. Open a pull request against `main`

Bug reports and ideas without a fix → open an issue on the same repo.
