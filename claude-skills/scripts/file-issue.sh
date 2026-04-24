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
#   file-issue.sh --agent security --title "..." --body "..."
#   file-issue.sh --agent qa --filed-by qa --title "..." --body "..."
#
# With `--agent NAME`, the issue also carries the agent's bus label
# (from `claude-skills/agents/registry.json`) so every ticket can be
# filtered by ownership. Without it, the helper falls back to the
# generic review-label behaviour above.
#
# With `--filed-by NAME`, the issue also carries a `filed-by:<name>`
# label for traceability — distinguishing agent-filed issues from
# human-filed ones (#222 full autonomy).
#
# With `--dedup FINGERPRINT`, the script checks for an existing open
# issue with the same fingerprint in its body. If found, exits 0 with
# no output (idempotent). The fingerprint is appended to the body as
# a hidden HTML comment: `<!-- bsg-dedup:FINGERPRINT -->`.
#
# Exits with the issue URL on stdout. Exits non-zero on any real failure.

set -euo pipefail

REVIEW_LABEL="needs-human-review"
REVIEW_COLOR="fbca04"
REVIEW_DESC="Awaiting a human decision (triage, merge, or scope)"
BUS_LABEL=""
FILED_BY=""
DEDUP_FINGERPRINT=""

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
    --agent)
      agent_name="$2"
      registry="$(git rev-parse --show-toplevel 2>/dev/null)/claude-skills/agents/registry.json"
      if [[ -f "$registry" ]]; then
        BUS_LABEL="$(jq -r --arg n "$agent_name" '.agents[] | select(.name == $n) | .bus_label' "$registry" 2>/dev/null || true)"
      fi
      shift 2
      ;;
    --filed-by)
      FILED_BY="$2"
      shift 2
      ;;
    --dedup)
      DEDUP_FINGERPRINT="$2"
      shift 2
      ;;
    *)
      args+=("$1")
      shift
      ;;
  esac
done

# Dedup: if a fingerprint was provided, check for existing open issues
# that carry the same fingerprint in their body.
if [[ -n "$DEDUP_FINGERPRINT" ]]; then
  dedup_marker="bsg-dedup:${DEDUP_FINGERPRINT}"
  existing=$(gh issue list "${repo_flag[@]}" \
    --state open \
    --search "$dedup_marker in:body" \
    --json number \
    --limit 1 2>/dev/null | jq 'length' 2>/dev/null || echo "0")
  if [[ "$existing" -gt 0 ]]; then
    exit 0
  fi
fi

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

# Labels we always ensure are on the issue: needs-human-review + (optional)
# the bus label that pins ownership to a specific agent + (optional)
# filed-by:<agent> for traceability.
extra_labels="$REVIEW_LABEL"
if [[ -n "$BUS_LABEL" ]]; then
  extra_labels="${extra_labels},${BUS_LABEL}"
fi
if [[ -n "$FILED_BY" ]]; then
  filed_label="filed-by:${FILED_BY}"
  # Ensure the filed-by label exists.
  if ! gh label list "${repo_flag[@]}" --json name \
       --jq '.[] | select(.name == "'"$filed_label"'") | .name' \
       2>/dev/null | grep -qxF "$filed_label"; then
    gh label create "$filed_label" \
      "${repo_flag[@]}" \
      --color "bfdadc" \
      --description "Issue filed automatically by the $FILED_BY agent (#222)" \
      >/dev/null 2>&1 || true
  fi
  extra_labels="${extra_labels},${filed_label}"
fi

# `gh issue create --label` accepts either a comma-separated list or
# multiple flags — we normalise to one `--label` flag with $extra_labels
# appended to whatever was passed. If --dedup was used, inject the
# fingerprint as a hidden HTML comment into --body.
final_args=()
label_merged=0
body_injected=0
i=0
while [[ $i -lt ${#args[@]} ]]; do
  arg="${args[$i]}"
  if [[ "$arg" == "--label" ]]; then
    existing="${args[$((i+1))]}"
    final_args+=(--label "${existing},${extra_labels}")
    label_merged=1
    i=$((i+2))
  elif [[ "$arg" == "--body" && -n "$DEDUP_FINGERPRINT" ]]; then
    existing_body="${args[$((i+1))]}"
    final_args+=(--body "${existing_body}

<!-- bsg-dedup:${DEDUP_FINGERPRINT} -->")
    body_injected=1
    i=$((i+2))
  else
    final_args+=("$arg")
    i=$((i+1))
  fi
done
if [[ $label_merged -eq 0 ]]; then
  final_args+=(--label "$extra_labels")
fi

exec gh issue create "${final_args[@]}"
