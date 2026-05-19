Synchronize git worktrees with their PRs and prune obsolete ones: $ARGUMENTS

You are invoking the `sync-worktree` command. Its job is to reconcile the
local git worktrees with their remote PR state:

1. **Commit + push** any worktree whose local branch is ahead of its remote
   (uncommitted changes, unpushed commits, or no remote tracking branch).
2. **Prune** any worktree whose branch is obsolete (PR merged, PR closed
   without merge, or branch already merged into the target/base branch and
   no PR exists).

Default scope is **all worktrees of the current repository**. Pass
`--current` to act on the current worktree only. Pass `--dry-run` to
report what would happen without touching anything.

## Argument parsing

Typical forms:
- `/sync-worktree` — full sweep, all worktrees, with confirmation before deletes
- `/sync-worktree --current` — only the worktree the user is in
- `/sync-worktree --dry-run` — report-only, never commit, push, or delete
- `/sync-worktree --yes` — skip confirmation prompts (still respects `--dry-run`)

Anything else after the flags is a free-form filter: a branch name prefix,
a path substring, or a single worktree path. If the filter matches zero
worktrees, abort with a one-line message.

## Steps

### 0. Sanity check the invocation

- The current working directory must be inside a git repository.
  Run `git rev-parse --show-toplevel`; if it fails, stop with a clear
  message and do nothing.
- Refuse to operate if the repo has no remote `origin` — there is no
  PR concept to reconcile against. Tell the user, stop.

### 1. Enumerate worktrees

```bash
git worktree list --porcelain
```

Parse `worktree <path>`, `HEAD <sha>`, `branch refs/heads/<name>` blocks.
Skip the **main** worktree (the one whose path is the repo root); that one
is never deleted and almost never needs an autonomous commit. The user can
opt into syncing it explicitly with a path filter.

Also skip any worktree marked `prunable` (already detached/missing on disk)
— git's own `git worktree prune` handles those; mention them in the
summary but do not touch.

### 2. Resolve the target/base branch

The PR base may not be `main`. For Superconductor-managed worktrees, run:

```bash
sc worktree status --json
```

inside the worktree to read `target_branch`. Otherwise fall back to the
repo default branch from `gh repo view --json defaultBranchRef -q .defaultBranchRef.name`.
Cache the result per worktree; do not infer it from the current branch.

### 3. For each worktree, classify it

Run these inside the worktree (use `git -C <path>` rather than `cd`):

```bash
git -C "$WT" status --porcelain                         # dirty?
git -C "$WT" rev-parse --abbrev-ref HEAD                # branch name
git -C "$WT" rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null  # upstream
git -C "$WT" rev-list --count '@{u}..HEAD' 2>/dev/null  # ahead
git -C "$WT" rev-list --count 'HEAD..@{u}' 2>/dev/null  # behind
gh pr list --head "$BRANCH" --state all --json number,state,mergedAt,url --limit 1
```

Then assign one of these states:

| State            | Trigger                                                                                  |
|------------------|------------------------------------------------------------------------------------------|
| `clean`          | No uncommitted changes, no unpushed commits, PR (if any) is OPEN.                        |
| `needs-commit`   | Working tree has staged/unstaged/untracked changes.                                      |
| `needs-push`     | Local branch is ahead of upstream (or has no upstream yet).                              |
| `obsolete-merged`| PR is MERGED, **or** branch has no commits beyond the target/base and no open PR exists. |
| `obsolete-closed`| PR is CLOSED without merge.                                                              |
| `behind`         | Branch is behind upstream but otherwise clean — informational only, do not touch.        |
| `conflict`       | Both ahead and behind (diverged) — flag for human, do not auto-resolve.                  |

A worktree can be both `needs-commit` and `obsolete-merged` (uncommitted
work on a branch whose PR already merged). In that case the work wins:
**never delete a worktree with uncommitted changes**, report it as
`conflict` for the human.

### 4. Print the plan

Before any mutation, print a table:

```
worktree                                          branch                          state            action
~/.superconductor/worktrees/repo/sc-foo-1a2b      feat/foo-thing                  needs-commit     commit + push
~/.superconductor/worktrees/repo/sc-bar-3c4d      fix/bar-thing                   obsolete-merged  remove worktree + delete local branch
~/.superconductor/worktrees/repo/sc-baz-5e6f      chore/baz                       clean            skip
```

If `--dry-run`, stop here.

Otherwise, if any row is `obsolete-*` or `conflict` and `--yes` was not
passed, ask the user to confirm with AskUserQuestion before doing the
destructive parts. Commits + pushes proceed without confirmation
(they are reversible — the diff has already been shown in the plan).

### 5. Execute

For each worktree, in this order:

**`needs-commit`:**
1. `git -C "$WT" status --short` — show what will be staged
2. Generate a conventional-commit message from the diff (`feat:`, `fix:`,
   `chore:`, `docs:`, `refactor:`, `test:`, `ci:`, `perf:`, `style:`,
   `build:`) with a kebab-case scope when one is obvious. Keep the body
   short and factual.
3. `git -C "$WT" add -A` then `git -C "$WT" commit -m "<message>"` (via
   a HEREDOC, with the standard `Co-Authored-By` footer used elsewhere
   in this repo).
4. Fall through to `needs-push`.

**`needs-push`:**
1. If upstream exists: `git -C "$WT" push`
2. If no upstream: `git -C "$WT" push -u origin "$BRANCH"`
3. Surface the resulting PR URL with `gh pr view --json url -q .url` if
   one already exists; otherwise mention that no PR is open yet (do
   **not** create one — that's `/ship`'s job).

**`obsolete-merged` and `obsolete-closed`:**
1. `git worktree remove "$WT"` (NOT `--force` — refuse if the tree is
   dirty; the classifier already promoted dirty worktrees to `conflict`).
2. Best-effort local branch cleanup: `git branch -d "$BRANCH"` (lowercase
   `-d`, never `-D`). If `-d` refuses, leave the branch and note it in
   the summary — that's git telling you the branch carries unmerged
   commits worth keeping.
3. **Do not** touch the remote branch. GitHub's "automatically delete
   head branches" setting (or the user) owns that.

**`conflict` and `behind`:**
Report and move on. No mutation.

### 6. Summarize

End with a four-line summary:

```
Synced:   2 worktree(s) committed and pushed
Pruned:   1 worktree(s) removed (obsolete)
Flagged:  1 worktree(s) need human attention (conflict, diverged, …)
Skipped:  3 worktree(s) clean
```

Followed by a bulleted list of any flagged items with the reason.

## Hard rules

- **Never** force-push, `git reset --hard`, `git worktree remove --force`,
  `git branch -D`, or `git push --delete`. If a normal operation refuses,
  the refusal is the answer — flag for human, don't escalate.
- **Never** delete the worktree you are currently running inside. Detect
  this by comparing `$PWD` (resolved with `git rev-parse --show-toplevel`)
  against each candidate's path; if they match, downgrade the action to
  "report only" and tell the user to re-run from the main worktree.
- **Never** commit a file that looks like a secret (`.env`, `*.pem`,
  `id_rsa`, anything matching the `.securityignore` glob if one exists).
  Abort the commit on that worktree and flag it.
- **Never** push to `main` / the target branch directly. If the worktree
  is somehow on the base branch, downgrade to report-only.
- Auto-merge / auto-close decisions on the PR are out of scope — this
  command reconciles **worktrees**, not PR lifecycle. Use `/babysit` or
  `/ship` for that.
- Confirmation prompts use AskUserQuestion, not raw stdin. One question
  covers the whole destructive batch — do not ask per-worktree.

## Why this exists

Superconductor and plain git worktrees accumulate over a day of work:
half-finished branches whose PR landed, scratch branches whose PR was
closed, worktrees the developer forgot to clean up. The state drifts in
two directions at once — local work that never reaches the PR, and PR
state that never reaches the local tree. Reconciling by hand means
running `git worktree list`, then `gh pr view` for each, then a `git
status` for each, then deciding. This command does the bookkeeping so
the human only sees the rows that need a judgement call.

---

## How to improve this skill

This file is a cached copy of `claude-skills/commands/sync-worktree.md` in
[beyond-scale-group/bsg-stack](https://github.com/beyond-scale-group/bsg-stack).
That repo is the single source of truth — `~/.claude/commands/sync-worktree.md` is
overwritten every time the BSG install flow runs.

If the user asks you to improve, fix, or extend this skill, do **not** edit
the local file. Instead:

1. `gh repo clone beyond-scale-group/bsg-stack` (or work in an existing clone)
2. Edit `claude-skills/commands/sync-worktree.md` on a feature branch
3. Open a pull request against `main`

Bug reports and ideas without a fix → open an issue on the same repo.
