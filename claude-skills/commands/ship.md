---
name: ship
description: >-
  Ship the current branch: run preflight checks, commit, push, and open a PR.
model: haiku
---
Ship the current branch: run preflight checks, commit, push, and open a PR. $ARGUMENTS

You are the **ship** command. Your job is to take the current branch from
working state to an open pull request, with confidence that nothing is broken.

## Argument parsing

Typical forms:
- `/ship` — full pipeline: lint, test, commit, push, create PR
- `/ship --skip-checks` — skip lint/test, go straight to commit + push + PR
- `/ship --draft` — create the PR as a draft
- `/ship --base staging` — target a specific base branch (default: use
  `sc worktree status --json` → `target_branch`, else repo default branch)
- `/ship "feat: add dark mode support"` — use the quoted string as the
  commit message (skip auto-generation)

Free-form text after flags is treated as the commit message override.

## Steps

### 0. Sanity checks

- Must be inside a git repository (`git rev-parse --show-toplevel`).
- Must NOT be on the base/target branch — refuse to ship directly to
  `main`/`staging`/the target branch.
- Must have a remote `origin` configured.

### 1. Resolve the target branch

Run `sc worktree status --json` to read `target_branch`. If the `sc` CLI
is unavailable, fall back to `gh repo view --json defaultBranchRef -q .defaultBranchRef.name`.

### 2. Preflight checks (unless `--skip-checks`)

Detect which tools are available and run the appropriate checks:

1. **Lint/format:**
   - `package.json` → `npm run lint` or `bun run lint` (check `scripts` key)
   - `Makefile` with `lint` target → `make lint`
   - `pyproject.toml` / `setup.cfg` → `ruff check .` or `flake8`
   - `.eslintrc*` / `eslint.config.*` → `npx eslint .`
   - Skip if none detected — don't fail on missing linter

2. **Type check:**
   - `tsconfig.json` → `npx tsc --noEmit` or `bun run typecheck`
   - `pyproject.toml` with mypy/pyright config → `mypy .` / `pyright`
   - Skip if none detected

3. **Tests:**
   - `package.json` → `npm test` or `bun test` (check `scripts.test`)
   - `Makefile` with `test` target → `make test`
   - `pyproject.toml` → `pytest`
   - `Cargo.toml` → `cargo test`
   - `go.mod` → `go test ./...`
   - Skip if none detected — don't fail on missing tests

Run lint and type check in parallel where possible. Tests run after
both pass.

**On failure:** stop, show the error output, and tell the user what
failed. Do NOT continue to commit/push. Offer to fix the issue or
re-run with `--skip-checks`.

### 3. Stage and commit

- Run `git status --porcelain` to see what changed.
- If there are no changes (staged or unstaged) and no unpushed commits,
  check if a PR already exists for this branch. If so, report its URL
  and stop. If not but the branch has commits beyond the target, skip
  to step 4 (push + PR).
- If there are changes:
  1. Show a summary of what will be committed (`git diff --stat`)
  2. Exclude files that look like secrets (`.env`, `*.pem`, `id_rsa`,
     `credentials.json`) — warn the user if any are present
  3. Stage all non-secret changes: `git add` specific files by name
  4. Generate a conventional commit message from the diff (or use the
     user-provided message). Follow the repo's recent commit style
     (`git log --oneline -10`). Include the standard Co-Authored-By
     footer
  5. Commit via HEREDOC

### 4. Push

- If upstream exists: `git push`
- If no upstream: `git push -u origin <branch>`
- On push failure (e.g., diverged): stop and report. Do NOT force-push.

### 5. Create or update the PR

- Check for an existing open PR: `gh pr list --head <branch> --state open --json url --limit 1`
- If a PR exists: report its URL. If the push added new commits, the PR
  is already updated.
- If no PR exists:
  1. Generate a PR title from the branch name (strip prefix, un-kebab,
     sentence-case) or from the commit message if only one commit
  2. Generate a PR body:
     - `## Summary` with 1-3 bullet points derived from `git log --oneline <target>..<branch>`
     - `## Test plan` with a checklist based on what changed
     - `## Preflight` noting which checks passed (lint, typecheck, tests)
     - Standard Claude Code footer
  3. Create with `gh pr create --title "..." --body "$(cat <<'EOF' ... EOF)" --base <target>`
  4. Add `--draft` if the user passed `--draft`

### 6. Report

One-line summary:

```
Shipped: <commit-sha-short> → PR #<n> (<url>) — lint ✓ typecheck ✓ tests ✓
```

Or if checks were skipped:

```
Shipped: <commit-sha-short> → PR #<n> (<url>) — checks skipped
```

## Hard rules

- **Never** force-push, `git push --force`, `git reset --hard`, or
  `git push --delete`.
- **Never** push to the target/base branch directly.
- **Never** commit secrets. If detected, warn and exclude them.
- **Never** merge the PR, flip it out of draft, or assign a reviewer —
  that's `/merge`'s job (or `/ship_and_merge`'s, for the opt-in full
  auto-merge pipeline).
- **Never** skip preflight checks silently. If skipping, it must be
  because the user passed `--skip-checks`.
- PR creation uses `gh pr create`, not the GitHub API directly.
- If the branch has no commits beyond the target and no local changes,
  there's nothing to ship — say so and stop.

---

## How to improve this skill

This file is a cached copy of `claude-skills/commands/ship.md` in
[beyond-scale-group/bsg-stack](https://github.com/beyond-scale-group/bsg-stack).
That repo is the single source of truth — `~/.claude/commands/ship.md` is
overwritten every time the BSG install flow runs.

If the user asks you to improve, fix, or extend this skill, do **not** edit
the local file. Instead:

1. `gh repo clone beyond-scale-group/bsg-stack` (or work in an existing clone)
2. Edit `claude-skills/commands/ship.md` on a feature branch
3. Open a pull request against `main`

Bug reports and ideas without a fix → open an issue on the same repo.
