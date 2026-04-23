#!/usr/bin/env bash
# file-issue.sh — wrap `gh issue create` with the BSG review-label convention.
#
# Every BSG agent that files a GitHub issue should use this helper instead
# of calling `gh issue create` directly. The wrapper:
#
#   1. Ensures the `needs-human-review` label exists on the target repo
#      (creates it once if missing), so the convention propagates to any
#      BSG-consuming repo without manual setup.
#   2. Adds `needs-human-review` to the `--label` list automatically.
#   3. Forwards every other flag to `gh issue create` unchanged, so the
#      caller's existing `--title`, `--body`, `--label bug`, `--assignee`,
#      etc. all keep working.
#
# The label is never removed automatically — humans own the transition out
# of "needs review" by merging, closing, or relabeling the issue.
#
# Usage (drop-in replacement for `gh issue create`):
#   file-issue.sh --title "..." --body "..."
#   file-issue.sh --title "..." --label "bug" --body "..."
#   file-issue.sh --repo owner/name --title "..." --body "..."
#
# Exits with the issue URL on stdout. Exits non-zero on any real failure.

set -euo pipefail

REVIEW_LABEL="needs-human-review"
REVIEW_COLOR="fbca04"
REVIEW_DESC="Awaiting a human decision (triage, merge, or scope)"

# Target repo is whatever `gh` resolves (explicit --repo wins, else the cwd).
repo_flag=()
args=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo)
      repo_flag=(--repo "$2")
      args+=(--repo "$2")
      shift 2
      ;;
    *)
      args+=("$1")
      shift
      ;;
  esac
done

# Idempotently ensure the label exists on the target repo. `gh label create`
# exits non-zero if the label already exists, so swallow that specific case.
if ! gh label list "${repo_flag[@]}" --json name \
     --jq '.[] | select(.name == "'"$REVIEW_LABEL"'") | .name' \
     2>/dev/null | grep -qx "$REVIEW_LABEL"; then
  gh label create "$REVIEW_LABEL" \
    "${repo_flag[@]}" \
    --color "$REVIEW_COLOR" \
    --description "$REVIEW_DESC" \
    >/dev/null 2>&1 || true
fi

# Weave `needs-human-review` into `--label`. `gh issue create --label` accepts
# either a comma-separated list or multiple flags — we normalise to one
# `--label` flag with the review label appended to whatever was passed.
final_args=()
label_merged=0
i=0
while [[ $i -lt ${#args[@]} ]]; do
  arg="${args[$i]}"
  if [[ "$arg" == "--label" ]]; then
    existing="${args[$((i+1))]}"
    final_args+=(--label "${existing},${REVIEW_LABEL}")
    label_merged=1
    i=$((i+2))
  else
    final_args+=("$arg")
    i=$((i+1))
  fi
done
if [[ $label_merged -eq 0 ]]; then
  final_args+=(--label "$REVIEW_LABEL")
fi

exec gh issue create "${final_args[@]}"
