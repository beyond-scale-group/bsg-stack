---
name: ship_and_merge
description: >-
  Ship and merge the current branch: preflight checks, fix failures, commit, push, open a PR, wait for CI green, and merge.
model: haiku
---
Ship and merge the current branch: run preflight checks, fix failures, commit, push, open a PR, wait for CI green, and merge. $ARGUMENTS

You are the **ship_and_merge** command. You do everything `/ship` does, plus
you babysit CI and merge the PR once all checks pass. If preflight or CI
fails, you diagnose, fix, and retry — looping until green or until you've
exhausted reasonable attempts.

## Argument parsing

Typical forms:
- `/ship_and_merge` — full pipeline: lint, test, fix, commit, push, PR, wait for CI, merge
- `/ship_and_merge --skip-checks` — skip local preflight, go straight to commit + push + PR + CI + merge
- `/ship_and_merge --base staging` — target a specific base branch
- `/ship_and_merge --squash` — squash merge (default)
- `/ship_and_merge --rebase` — rebase merge instead of squash
- `/ship_and_merge "feat: add dark mode support"` — use as commit message

Free-form text after flags is treated as the commit message override.

## Steps

### 0–5: Same as `/ship`

Follow `/ship` steps 0 through 5 exactly (sanity checks, resolve target,
preflight, stage + commit, push, create PR), with one critical difference:

**On preflight failure: fix and retry.**

When lint, typecheck, or tests fail:

1. Read the error output carefully
2. Identify the root cause
3. If it's something you can fix (code error, formatting, missing import,
   type error, test assertion), fix it
4. Re-run the failed check to verify the fix
5. If it passes, continue the pipeline
6. If it still fails, try a different approach
7. After **3 fix attempts** on the same check, stop and ask the user

This is the key difference from `/ship`: instead of stopping on failure,
you enter a fix-retry loop. Each fix gets its own commit with a clear
message explaining what was fixed.

### 6. Wait for CI

After the PR is created (or updated with a push):

1. Get the latest check run: `gh pr checks <pr-number> --watch`
   Or poll with: `gh pr checks <pr-number> --json name,state,conclusion`
2. Wait for all required checks to complete
3. Poll every 30-60 seconds (use `gh run watch` if a run ID is available)

### 7. Handle CI failures

If CI fails:

1. Get the failure logs: `gh run view <run-id> --log-failed`
2. Diagnose the root cause
3. If fixable (same rules as preflight): fix, commit, push
4. The PR updates automatically — go back to step 6
5. After **5 fix-push cycles**, stop and report what's still broken

**Do NOT retry endlessly.** Track fix attempts and give up gracefully.

### 8. Merge

Once all checks are green and the PR is mergeable:

1. Check mergeable state: `gh pr view <n> --json mergeable,mergeStateStatus`
2. If `BEHIND` — rebase onto the target: `gh pr merge <n> --rebase` handles
   this, or `git pull --rebase origin <target>` + push if needed
3. If `BLOCKED` — report what's blocking (required reviews, etc.) and stop
4. If `CLEAN` or `UNSTABLE` (only non-required checks failed):
   - Default: `gh pr merge <n> --squash --delete-branch`
   - With `--rebase`: `gh pr merge <n> --rebase --delete-branch`
5. Verify the merge succeeded: `gh pr view <n> --json state`

### 9. Report

Final one-line summary:

```
Shipped & merged: PR #<n> (<url>) → <target> — lint ✓ typecheck ✓ tests ✓ CI ✓
```

Or if fixes were needed:

```
Shipped & merged: PR #<n> (<url>) → <target> — 2 fixes applied, CI green after 3 runs
```

Or if it couldn't merge:

```
Shipped but NOT merged: PR #<n> (<url>) — blocked by: required review from @team
```

## Hard rules

- **Never** force-push. If the branch diverged, rebase and normal-push.
- **Never** merge without CI green. If checks are still running, wait.
  If checks failed and you can't fix them, stop.
- **Never** bypass required reviews. If the repo requires approvals,
  report it and stop — don't use `--admin` or any override.
- **Never** merge to a branch other than the resolved target.
- **Never** commit secrets. Same rules as `/ship`.
- **Give up after 5 total fix attempts** (preflight + CI combined).
  Report what you tried and what's still broken.
- **Delete the remote branch** after merge (`--delete-branch`). The
  local branch and worktree are left for the user to clean up (or
  `/sync-worktree` handles it).
- Each fix gets its own commit — never amend a previous commit.
- Between CI polls, wait 30-60 seconds to avoid API rate limits.

---

## How to improve this skill

This file is a cached copy of `claude-skills/commands/ship_and_merge.md` in
[beyond-scale-group/bsg-stack](https://github.com/beyond-scale-group/bsg-stack).
That repo is the single source of truth — `~/.claude/commands/ship_and_merge.md` is
overwritten every time the BSG install flow runs.

If the user asks you to improve, fix, or extend this skill, do **not** edit
the local file. Instead:

1. `gh repo clone beyond-scale-group/bsg-stack` (or work in an existing clone)
2. Edit `claude-skills/commands/ship_and_merge.md` on a feature branch
3. Open a pull request against `main`

Bug reports and ideas without a fix → open an issue on the same repo.
