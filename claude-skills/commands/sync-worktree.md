---
name: sync-worktree
description: >-
  Synchronize git worktrees with their PRs and prune obsolete ones.
model: haiku
---
Synchronize git worktrees with their PRs and prune obsolete ones: $ARGUMENTS

You are invoking the `sync-worktree` command. Its job is to reconcile the
local git worktrees with their remote PR state:

1. **Commit + push** any worktree whose local branch is ahead of its remote
   (uncommitted changes, unpushed commits, or no remote tracking branch).
2. **Prune** any worktree whose branch is obsolete (PR merged, PR closed
   without merge, or branch already merged into the target/base branch and
   no PR exists).
3. **Resolve, on request** — when opted in via flag — a worktree that is
   `conflict` (diverged from its target/base branch) or `changes-requested`
   (a peer or human review left actionable feedback on the open PR) by
   delegating the actual code judgement to a fresh sub-agent running a
   stronger model. See the "delegated resolution" parts of step 5 below;
   this command's own `haiku` model only classifies and dispatches, it
   never edits code itself.

Default scope is **all worktrees of the current repository**. Pass
`--current` to act on the current worktree only. Pass `--dry-run` to
report what would happen without touching anything.

## Argument parsing

Typical forms:
- `/sync-worktree` — full sweep, all worktrees, fully automatic (no prompts)
- `/sync-worktree --current` — only the worktree the user is in
- `/sync-worktree --dry-run` — report-only, never commit, push, or delete
- `/sync-worktree --resolve-conflicts` — additionally delegate `conflict`
  worktrees to a sub-agent that attempts to resolve the divergence
- `/sync-worktree --apply-reviews` — additionally delegate `changes-requested`
  worktrees to a sub-agent that applies the reviewer's feedback
- `/sync-worktree --resolve` — shorthand for both of the above

`--resolve-conflicts` and `--apply-reviews` (and their `--resolve`
shorthand) are **opt-in and off by default**. Everything else this command
does is bookkeeping (commit-as-is, push, prune); these two flags are the
only paths by which `sync-worktree` writes new code, so they don't inherit
the "fully automatic" default — a human has to ask for this sweep to attempt
real fixes.

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

If an open PR exists, also check its review decision (used to detect
`changes-requested`):

```bash
gh pr view "$PR_NUMBER" --json reviewDecision,reviews -q .reviewDecision
```

Then assign one of these states:

| State               | Trigger                                                                                  |
|----------------------|------------------------------------------------------------------------------------------|
| `busy`               | Another AI/automation process appears to be actively working in this worktree (see step 3.5). Overrides every other state — do nothing this sweep. |
| `clean`              | No uncommitted changes, no unpushed commits, PR is OPEN.                                 |
| `needs-pr`           | Pushed to remote, no uncommitted changes, no open PR exists, branch has commits beyond target. |
| `needs-commit`       | Working tree has staged/unstaged/untracked changes.                                      |
| `needs-push`         | Local branch is ahead of upstream (or has no upstream yet).                              |
| `obsolete-merged`    | PR is MERGED, **or** branch has no commits beyond the target/base and no open PR exists. |
| `obsolete-closed`    | PR is CLOSED without merge.                                                              |
| `behind`             | Branch is behind upstream but otherwise clean — informational only, do not touch.        |
| `conflict`           | Both ahead and behind (diverged) — flag for human by default; auto-resolvable via `--resolve-conflicts`. |
| `changes-requested`  | Open PR's `reviewDecision` is `CHANGES_REQUESTED`, or an unresolved peer-review rework comment exists (per the peer-review convention in this repo's `CLAUDE.md`) — flag for human by default; auto-resolvable via `--apply-reviews`. |

A worktree can be both `needs-commit` and `obsolete-merged` (uncommitted
work on a branch whose PR already merged). In that case the work wins:
**never delete a worktree with uncommitted changes**, report it as
`conflict` for the human.

`changes-requested` takes priority over `clean`/`needs-push` (a pushed,
otherwise-clean branch with review feedback pending is not "clean"), but
never overrides `conflict` — a diverged worktree with review feedback is
still `conflict` first; resolve the divergence before applying feedback.

### 3.5 Guard against concurrent AI activity

Before classifying a worktree into any action, check whether another agent
(human-driven or autonomous, Superconductor-managed or not) is actively
working inside it. If so, treat it as `busy` and do not touch it — not even
a commit — this sweep. Colliding with a live editor is worse than skipping
a cycle; the next sweep picks it up once the other process is done.

Two independent signals, either one is sufficient to mark `busy`:

1. **Superconductor-managed agents.** Run `sc agents list --output json`
   and look for any entry whose worktree/path field matches `$WT` and whose
   status indicates it is currently running (not idle, not terminated —
   inspect the actual JSON shape returned, field names can vary by
   version). A running agent targeting this worktree means it may be
   mid-edit right now.
2. **Git-level lock (catches any writer, sc-managed or not).** Worktrees
   keep their own gitdir under the main repo's `.git/worktrees/<name>/`.
   An `index.lock` there means a git operation (commit, rebase, merge,
   checkout) is in flight *right now*:

   ```bash
   GITDIR=$(git -C "$WT" rev-parse --git-dir)
   test -f "$GITDIR/index.lock" && echo busy
   ```

   As a softer heuristic for a process that's mid-edit but hasn't invoked
   git yet, also check for very recently modified tracked/untracked files:

   ```bash
   find "$WT" -not -path '*/.git/*' -newermt '-10 seconds' -type f -print -quit
   ```

   Any hit here is a signal to skip, not a hard proof — treat it the same
   way: skip this sweep rather than risk a race.

Re-run this guard **immediately before** any mutation in step 5, not just
during classification — a sweep over many worktrees can take long enough
for another agent to start mid-sweep. This matters most right before
dispatching a `--resolve-conflicts` / `--apply-reviews` sub-agent, since
that sub-agent is about to write files itself.

### 4. Print the plan

Before any mutation, print a table:

```
worktree                                          branch                          state              action
~/.superconductor/worktrees/repo/sc-foo-1a2b      feat/foo-thing                  needs-commit       commit + push + create PR
~/.superconductor/worktrees/repo/sc-bar-3c4d      fix/bar-thing                   obsolete-merged    remove worktree + delete local branch
~/.superconductor/worktrees/repo/sc-baz-5e6f      chore/baz                       clean              skip
~/.superconductor/worktrees/repo/sc-qux-7g8h      refactor/qux-cleanup            needs-pr           create PR
~/.superconductor/worktrees/repo/sc-liv-9i0j      fix/live-agent-edit             busy               skip (agent active)
~/.superconductor/worktrees/repo/sc-con-1k2l      feat/conflict-thing             conflict           dispatch resolve sub-agent (--resolve-conflicts)
~/.superconductor/worktrees/repo/sc-rev-3m4n      fix/review-thing                changes-requested  dispatch apply-review sub-agent (--apply-reviews)
```

If `--dry-run`, stop here.

Otherwise, proceed immediately to execution. This skill is fully automatic
— it never asks for confirmation. The plan table above is the audit trail;
the hard rules below are the safety net (never force-delete, never touch
dirty worktrees, never delete the current worktree).

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
3. Check for an existing PR: `gh pr list --head "$BRANCH" --state open --json url --limit 1`
4. If a PR exists, surface its URL.
5. If no PR exists and the branch is not the target/base branch, create
   one using `gh pr create` with:
   - A title derived from the branch name (strip the prefix, un-kebab
     the slug, sentence-case it)
   - A body summarizing the commits on the branch vs. the target/base
     (`git log --oneline "$TARGET..$BRANCH"`)
   - `--base "$TARGET"` so the PR targets the correct branch
   - The standard `Generated with Claude Code` footer
   - Print the new PR URL in the plan output

**`needs-pr`:**
1. The branch is already pushed and up-to-date with its remote, but no
   open PR exists and the branch has commits beyond the target/base.
2. Create a PR using `gh pr create` with:
   - A title derived from the branch name (strip the prefix, un-kebab
     the slug, sentence-case it)
   - A body summarizing the commits on the branch vs. the target/base
     (`git log --oneline "$TARGET..$BRANCH"`)
   - `--base "$TARGET"` so the PR targets the correct branch
   - The standard `Generated with Claude Code` footer
3. Print the new PR URL.

**`obsolete-merged` and `obsolete-closed`:**
1. `git worktree remove "$WT"` (NOT `--force` — refuse if the tree is
   dirty; the classifier already promoted dirty worktrees to `conflict`).
2. Best-effort local branch cleanup: `git branch -d "$BRANCH"` (lowercase
   `-d`, never `-D`). If `-d` refuses, leave the branch and note it in
   the summary — that's git telling you the branch carries unmerged
   commits worth keeping.
3. **Do not** touch the remote branch. GitHub's "automatically delete
   head branches" setting (or the user) owns that.

**`busy`:**
Report and move on. No mutation, no exceptions — not even a commit. This
is the one state that isn't a judgement call: another process owns the
worktree right now.

**`behind`:**
Report and move on. No mutation.

**`conflict` (default) and `changes-requested` (default):**
Report and move on. No mutation. This is still the default even when the
worktree would otherwise be eligible for delegation below — without the
opt-in flag, `sync-worktree` never writes code.

**`conflict` with `--resolve-conflicts` — delegated resolution:**
1. Re-run the step 3.5 busy guard. If it now trips, downgrade to `busy`
   and skip.
2. Launch a fresh sub-agent via the Agent tool — do **not** attempt the
   resolution inline. This command runs on a lightweight model
   (`haiku`, see frontmatter) that is not equipped to read a conflicting
   hunk and judge which side is correct; a stronger model (Sonnet or
   equivalent — pass `model: "sonnet"`) is what actually does the work.
   Run it in the foreground (`run_in_background: false`) since the rest
   of this worktree's row depends on the outcome.
3. Brief the sub-agent with everything it needs and nothing it should
   guess at: the worktree path (`$WT`), the branch name, the resolved
   target/base branch, and explicit instructions to:
   - Bring the branch up to date against the target/base (merge or
     rebase, whichever the worktree's history already implies) inside
     `$WT` only.
   - Resolve any conflict markers by reading both sides' intent — never
     take one side wholesale without reading the other, never delete a
     hunk just to make the marker go away.
   - Run the project's build/test command if one is discoverable, to
     catch a resolution that's syntactically clean but semantically
     wrong.
   - Commit the resolution with a factual message once the tree is
     clean, using the same `Co-Authored-By` footer convention.
   - If any hunk requires a product/business decision it can't safely
     infer, stop without committing and report exactly which hunk and
     why — do not guess.
4. On success (sub-agent reports a clean tree and a commit landed): fall
   through to `needs-push`.
5. On failure or an explicit "can't safely resolve" report: leave the row
   as `conflict`, and append the sub-agent's stated reason to the flagged
   list in the summary so the human knows *why*, not just *that*.
6. The sub-agent inherits every hard rule below (no force-push, no
   `reset --hard`, never touch a worktree other than `$WT`) — state that
   explicitly in its prompt, don't assume it infers the constraints.

**`changes-requested` with `--apply-reviews` — delegated resolution:**
1. Re-run the step 3.5 busy guard. If it now trips, downgrade to `busy`
   and skip.
2. Gather the actual feedback before dispatching anyone:
   `gh pr view "$PR_NUMBER" --json reviews,comments`. Include both
   formal GitHub reviews (`CHANGES_REQUESTED` reviews and their inline
   comments) and, for repos running the BSG peer-review convention,
   comment-only rework requests from a peer-review agent (see this
   repo's `CLAUDE.md` — "Peer review" section) — those never carry a
   review *state*, only a comment, so check the comment thread too.
3. Launch a fresh sub-agent via the Agent tool with `model: "sonnet"`
   (or an equivalent stronger model), foreground, for the same reason as
   above: applying reviewer intent is a judgement call this command's
   own `haiku` model shouldn't make.
4. Brief the sub-agent with: the worktree path (`$WT`), the PR number,
   and the full verbatim text of every unresolved review comment/thread
   (don't paraphrase — the sub-agent should see exactly what the
   reviewer wrote). Instruct it to:
   - Apply only what was asked. Do not use the pass as an opportunity to
     refactor, fix unrelated issues, or address feedback the reviewer
     didn't give.
   - Keep the diff scoped to the files/lines the feedback actually
     touches.
   - If a comment is ambiguous or requires a decision the sub-agent
     can't make safely (e.g. two reviewers disagree, or the ask implies
     a design choice), skip that comment, leave everything else applied,
     and report which comment was skipped and why.
5. If the sub-agent applied any changes: run the same conventional-commit
   flow as `needs-commit` (commit locally), then fall through to
   `needs-push`.
6. **Do not** reply to the review thread, resolve/dismiss it, or
   re-request review — that's either a human call or `/babysit`'s /
   `/ship`'s job. This command's responsibility ends at "the code now
   reflects the ask"; leave the state as `changes-requested` in spirit
   (report it applied, but don't claim the review itself is resolved)
   until a human or the PR's own reviewers say otherwise.
7. If nothing could be safely applied, leave the row as
   `changes-requested` and report why in the summary.

### 6. Summarize

End with a summary; the first four lines are always present, the last two
only appear when the corresponding flag was used this sweep:

```
Synced:   2 worktree(s) committed and pushed
PRs:      1 PR(s) created for branches without one
Pruned:   1 worktree(s) removed (obsolete)
Flagged:  1 worktree(s) need human attention (conflict, diverged, …)
Skipped:  3 worktree(s) clean or busy (see below)
Resolved: 1 conflict(s) resolved via sub-agent (--resolve-conflicts)
Applied:  1 review request(s) applied via sub-agent (--apply-reviews)
```

Followed by a bulleted list of any flagged/skipped-as-busy items with the
reason, and — when `--resolve-conflicts` / `--apply-reviews` ran — one
line per sub-agent dispatch naming the worktree and the outcome (resolved,
or left as-is with the sub-agent's stated reason).

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
- PR creation uses a simple title derived from the branch name and a
  commit-log body. For richer descriptions or draft PRs, use `/ship`.
- Auto-merge / auto-close decisions on the PR are out of scope — this
  command reconciles **worktrees**, not PR lifecycle. Use `/babysit` or
  `/ship` for that.
- **Never prompt for confirmation.** This skill is designed for `/loop` and
  automated use — it must run fully unattended. The plan table is printed
  before mutations so the user can review output, but execution never
  pauses. Safety comes from the hard rules (no force-delete, no dirty
  worktree deletion, no current-worktree deletion), not from prompts.
- **Never touch a `busy` worktree.** If step 3.5 detects another agent or
  automation actively working inside a worktree (Superconductor agent
  status, a live `index.lock`, or very-recently-modified files), skip it
  entirely this sweep — no commit, no push, no prune, no sub-agent
  dispatch. Re-check immediately before every mutation, not just once at
  classification time, since a sweep can outlast a short window where the
  worktree looked idle.
- **`--resolve-conflicts` and `--apply-reviews` only ever run through a
  dispatched sub-agent**, never inline in this command's own turn. This
  command's frontmatter pins `model: haiku` for classification and
  bookkeeping speed; conflict resolution and review-feedback application
  require real code judgement, so they're delegated to a fresh sub-agent
  explicitly given a stronger model (Sonnet or equivalent). The dispatched
  sub-agent inherits every rule in this section — say so explicitly in its
  prompt.
- Both delegated-resolution paths are scoped to a single worktree
  (`$WT`) and must never touch any other worktree, branch, or the PR's
  review state itself (no resolving/dismissing review threads, no
  re-requesting review) — that remains a human or `/babysit`/`/ship`
  decision.

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
