#!/usr/bin/env bash
# mark-reviewed.sh — atomically merge a PR and flip its review labels.
#
# The `needs-human-review` / `human-reviewed` convention requires three
# separate actions when a human approves a PR:
#
#   1. Merge the PR
#   2. Add `human-reviewed`
#   3. Remove `needs-human-review`
#
# Doing those by hand is error-prone — during the 2026-04-23 session, 11
# items ended up with both labels because step 3 was skipped. This helper
# does all three in one call so the review transition is atomic in
# practice.
#
# Only call this on a PR you have actually reviewed. The label semantics
# are convention-only — this script does not verify the review happened,
# it just reflects your decision.
#
# Usage:
#   mark-reviewed.sh <pr-number> [--squash|--merge|--rebase] [--repo OWNER/NAME]
#
# Defaults to --squash, matching the house merge style. If the PR is
# already merged, the helper only fixes the labels (idempotent).
#
# Exits 0 on success, non-zero on any real failure.

set -euo pipefail

PR_NUMBER=""
MERGE_FLAG="--squash"
REPO_FLAG=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --squash|--merge|--rebase)
      MERGE_FLAG="$1"
      shift
      ;;
    --repo)
      REPO_FLAG=(--repo "$2")
      shift 2
      ;;
    -h|--help)
      sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    -*)
      echo "mark-reviewed.sh: unknown flag: $1" >&2
      exit 2
      ;;
    *)
      if [[ -n "$PR_NUMBER" ]]; then
        echo "mark-reviewed.sh: unexpected extra arg: $1" >&2
        exit 2
      fi
      PR_NUMBER="$1"
      shift
      ;;
  esac
done

if [[ -z "$PR_NUMBER" ]]; then
  echo "usage: mark-reviewed.sh <pr-number> [--squash|--merge|--rebase] [--repo OWNER/NAME]" >&2
  exit 2
fi

# Is the PR already merged? If so, skip the merge step.
pr_state=$(gh pr view "$PR_NUMBER" "${REPO_FLAG[@]}" --json state --jq '.state')

case "$pr_state" in
  OPEN)
    echo "mark-reviewed: merging #${PR_NUMBER} (${MERGE_FLAG})..."
    if ! gh pr merge "$PR_NUMBER" "${REPO_FLAG[@]}" "$MERGE_FLAG" --delete-branch >/dev/null 2>&1; then
      echo "mark-reviewed: merge failed for #${PR_NUMBER}" >&2
      exit 1
    fi
    ;;
  MERGED)
    echo "mark-reviewed: #${PR_NUMBER} already MERGED — fixing labels only"
    ;;
  CLOSED)
    echo "mark-reviewed: #${PR_NUMBER} is CLOSED (not merged) — refusing to label as reviewed" >&2
    exit 1
    ;;
  *)
    echo "mark-reviewed: unexpected PR state '${pr_state}' for #${PR_NUMBER}" >&2
    exit 1
    ;;
esac

# Atomic-ish label swap. `gh pr edit` accepts both --add-label and
# --remove-label in one call — if it fails, we surface that rather than
# leaving the labels half-migrated.
gh pr edit "$PR_NUMBER" "${REPO_FLAG[@]}" \
  --add-label "human-reviewed" \
  --remove-label "needs-human-review" >/dev/null

echo "mark-reviewed: #${PR_NUMBER} ← human-reviewed, ← ¬needs-human-review"
