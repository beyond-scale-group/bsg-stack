#!/usr/bin/env bash
# prune-agent-worktrees.sh — clean up stale .claude/worktrees/agent-* worktrees.
#
# Runs at the tail of /tick-all (and on demand) to remove worktrees the
# Agent runtime left behind because their working tree wasn't clean. In
# practice these are locked report worktrees whose PR has already landed:
# the Agent runtime preserves them for inspection, which is correct per
# run but accumulates across sweeps.
#
# Criteria for removal — all three must hold:
#   1. Path is under <repo-root>/.claude/worktrees/agent-*
#   2. Branch is one of:
#      - worktree-agent-*  (pure scratch branch created by the runtime;
#        never gets a PR)
#      - reports/*         AND the matching PR is MERGED or CLOSED
#   3. Removal succeeds (unlock first, then `git worktree remove --force`)
#
# Anything else — live branches, dirty trees with unrecognized branch
# names, main, sibling worktrees outside .claude/worktrees/ — is left
# alone. The script is safe to run anytime and emits a one-line summary.
#
# After the worktree pass, the script also deletes orphaned local
# branches matching `worktree-agent-*` whose backing worktree is gone
# (the runtime never deletes them, so they accumulate — see #363).
# `git branch -D` is used because these scratch branches don't get
# pushed and the standard `git branch -d` would refuse "not fully
# merged" branches.
#
# Usage:
#   bash claude-skills/scripts/prune-agent-worktrees.sh
#
# Exits 0 on success (even if nothing was pruned). Exits non-zero only
# on unrecoverable git failures.

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
cd "$REPO_ROOT"

pruned=0
kept=0

# Cache merged/closed PR head refs in one gh call to avoid per-worktree
# lookups. Degrade gracefully if gh is not available or not authed —
# we still prune scratch branches without network help.
merged_refs=""
if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
  merged_refs=$(gh pr list --state all --limit 200 \
    --json headRefName,state \
    --jq '.[] | select(.state == "MERGED" or .state == "CLOSED") | .headRefName' \
    2>/dev/null || true)
fi

is_merged_or_closed_ref() {
  [ -z "$merged_refs" ] && return 1
  grep -Fxq "$1" <<<"$merged_refs"
}

process_worktree() {
  local path="$1"
  local branch="$2"
  case "$path" in
    */.claude/worktrees/agent-*) ;;
    *) return ;;
  esac

  local remove=0
  case "$branch" in
    worktree-agent-*)
      remove=1
      ;;
    reports/*)
      if is_merged_or_closed_ref "$branch"; then
        remove=1
      fi
      ;;
  esac

  if [ "$remove" -eq 1 ]; then
    git worktree unlock "$path" 2>/dev/null || true
    if git worktree remove --force "$path" 2>/dev/null; then
      pruned=$((pruned + 1))
      return
    fi
  fi
  kept=$((kept + 1))
}

path=""
branch=""
while IFS= read -r line; do
  case "$line" in
    worktree\ *)
      [ -n "$path" ] && process_worktree "$path" "$branch"
      path="${line#worktree }"
      branch=""
      ;;
    branch\ refs/heads/*)
      branch="${line#branch refs/heads/}"
      ;;
    "")
      [ -n "$path" ] && process_worktree "$path" "$branch"
      path=""
      branch=""
      ;;
  esac
done < <(git worktree list --porcelain; echo)

git worktree prune

# After pruning the worktrees, sweep orphaned worktree-agent-* branches
# whose backing worktree is gone (#363). Build a set of branches still
# referenced by an active worktree, then delete every other
# worktree-agent-* local branch.
active_branches=$(git worktree list --porcelain \
  | awk '$1 == "branch" {sub("^refs/heads/", "", $2); print $2}')
branch_pruned=0
while IFS= read -r br; do
  [[ -z "$br" ]] && continue
  if grep -Fxq "$br" <<<"$active_branches"; then
    continue
  fi
  if git branch -D "$br" >/dev/null 2>&1; then
    branch_pruned=$((branch_pruned + 1))
  fi
done < <(git for-each-ref --format='%(refname:short)' 'refs/heads/worktree-agent-*')

echo "prune-agent-worktrees: pruned=${pruned} kept=${kept} branches-pruned=${branch_pruned}"
