#!/usr/bin/env bash
# reconcile-milestones.sh — assign GitHub milestones from po/PLAN.md bindings
#
# Closes #288 (phase 2c). Replaces reconcile-labels.sh which created/applied
# epic:* labels. This script reads [milestone:Slug] or [epic:#N] bindings
# from po/PLAN.md via parse-plan.sh and assigns the corresponding GitHub
# milestone to every bound issue/PR.
#
# What it does, idempotently, on every run:
#
#   1. Parse po/PLAN.md via parse-plan.sh --typed. If the plan is missing
#      or unparseable, skip (no milestone churn on drift).
#   2. For each "Epic" item (a bullet under ## Epics):
#      a. Extract the milestone slug from the epic line. Supported formats:
#         - [milestone:E1-tick-hygiene]
#         - Inferred from epic title: "**E1 tick-hygiene**" → E1-tick-hygiene
#      b. Ensure the GitHub milestone with that title exists (create if absent)
#      c. Assign that milestone to every bound issue/PR (by .bindings.epics
#         and .bindings.milestones)
#   3. For every OPEN issue/PR with no milestone: add `scope-creep` label.
#      For every OPEN issue/PR that now has a milestone: remove `scope-creep`.
#   4. Never touch `needs-human-review` / `human-reviewed` / bus labels —
#      those have their own owners.
#
# Usage:
#   bash claude-skills/skills/po/scripts/reconcile-milestones.sh [--repo OWNER/NAME]
#
# Exit 0 on success (including silent skip on drift). Non-zero on real
# GitHub errors; per-item failures are logged and the script continues.

set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"

REPO_FLAG=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) REPO_FLAG=(--repo "$2"); shift 2 ;;
    -h|--help)
      sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *) echo "reconcile-milestones.sh: unknown arg: $1" >&2; exit 2 ;;
  esac
done

SCOPE_CREEP_COLOR="d4c5f9"
SCOPE_CREEP_LABEL="scope-creep"
MILESTONE_COLOR="0075ca"

ensure_label() {
  local name="$1" color="$2" desc="$3"
  gh label create "$name" "${REPO_FLAG[@]}" \
    --color "$color" --description "$desc" >/dev/null 2>&1 || true
}

# Ensure a milestone exists; return its node_id (unused) and number via echo.
ensure_milestone() {
  local title="$1"
  # Try to get existing milestone number
  local number
  number=$(gh api "repos/{owner}/{repo}/milestones" "${REPO_FLAG[@]/#--repo/--jq}" \
    --jq ".[] | select(.title == \"$title\") | .number" 2>/dev/null || true)
  if [[ -z "$number" ]]; then
    number=$(gh api "repos/{owner}/{repo}/milestones" "${REPO_FLAG[@]/#--repo/--jq}" \
      -X POST -f "title=$title" -f "state=open" \
      --jq '.number' 2>/dev/null || echo "")
  fi
  echo "$number"
}

# Assign a milestone number to an issue or PR.
assign_milestone() {
  local kind="$1" number="$2" milestone_number="$3"
  gh api "repos/{owner}/{repo}/issues/$number" "${REPO_FLAG[@]/#--repo/--repo}" \
    -X PATCH -f "milestone=$milestone_number" >/dev/null 2>&1 \
    || echo "  warn: $kind #$number — couldn't assign milestone $milestone_number"
}

plan_envelope=$(bash "$HERE/parse-plan.sh" --typed)
plan_status=$(jq -r '.status' <<<"$plan_envelope")

if [[ "$plan_status" != "ok" ]]; then
  echo "reconcile-milestones: plan status = ${plan_status}, skipping"
  exit 0
fi

ensure_label "$SCOPE_CREEP_LABEL" "$SCOPE_CREEP_COLOR" \
  "Open issue/PR not bound to any po/PLAN.md epic — PO needs to triage"

# Build a map: milestone-slug -> csv of bound issue numbers.
# Supports both [milestone:Slug] bindings and inferred slug from epic title.
# Fix #657: parse-plan.sh already strips [tag:...] brackets out of
# `raw` and resolves the slug into `.bindings.milestones[]` — re-deriving
# it via a regex capture() against `.raw` never matches anymore, so the
# explicit-tag path is read straight from `.bindings.milestones[0]`.
#
# Independently: never bind a possibly-zero-output generator (like a
# non-matching capture()) via `EXPR as $var | BODY` — in jq, BODY runs
# once per *output* of EXPR, so a non-match means BODY (and any fallback
# it contains) never runs at all. Wrapping in `[EXPR][0]` collapses the
# generator to exactly one output (null on no match) before the `as`
# binding, so the fallback chain below always executes.
mapfile -t epic_lines < <(
  jq -r '
    .items[]
    | select(.section == "Epics")
    | .bindings.epics as $nums
    | ($nums | map(tostring) | join(",")) as $nums_csv
    | .raw as $raw
    | (.bindings.milestones[0]) as $explicit_ms
    | ([$raw | capture("^\\*\\*(?<ep>E[0-9]+) (?<name>[a-z0-9-]+)\\*\\*")][0]) as $cap
    | ($cap | if . then "\(.ep)-\(.name)" else null end) as $inferred_ms
    | ($explicit_ms // $inferred_ms) as $slug
    | if $slug then "\($slug)\t\($nums_csv)" else empty end
  ' <<<"$plan_envelope"
)

all_bound=()
declare -A slug_to_nums
# Touch the array with a sentinel key so bash 5.x considers it "set" under
# set -u before the loop runs. Without this, referencing ${#slug_to_nums[@]}
# or ${!slug_to_nums[@]} on a never-populated associative array aborts the
# script with "slug_to_nums: unbound variable" when epic_lines is empty.
# The sentinel is immediately removed so it has no effect on the map contents.
# Fixes #546. Matches the ${epic_lines[@]:-} pattern already used below.
slug_to_nums["__init__"]=""
unset 'slug_to_nums[__init__]'
# Guard the loop body: when the plan parses but yields no epics,
# `epic_lines` is an empty array and indexing `epic_lines[@]` under
# `set -u` errors with "unbound variable" on older bash. The
# `${epic_lines[@]:-}` expansion treats an unset/empty array as empty
# without aborting the script. See #363 fix #6.
for line in "${epic_lines[@]:-}"; do
  [[ -z "$line" ]] && continue
  slug="${line%%$'\t'*}"
  nums="${line##*$'\t'}"
  slug_to_nums["$slug"]="$nums"
  IFS=',' read -r -a arr <<<"$nums"
  # The `read -a` call may leave `arr` empty when `nums` itself is
  # empty (no bindings on this epic). Guard the append with the same
  # `${arr[@]:-}` defensive expansion so set -u stays happy.
  all_bound+=("${arr[@]:-}")
done

echo "reconcile-milestones: ${#slug_to_nums[@]} epics parsed from plan"

# Short-circuit: if no epic slugs were parsed, there's nothing to
# reconcile. Skip the assign / scope-creep loops cleanly rather than
# letting `${!slug_to_nums[@]}` iterate over an empty associative
# array under set -u.
if [[ "${#slug_to_nums[@]}" -eq 0 ]]; then
  echo "reconcile-milestones: no epics with bindings — nothing to reconcile"
  exit 0
fi

# Step 2: ensure milestones exist and assign to bound issues/PRs.
declare -A slug_to_milestone_num
for slug in "${!slug_to_nums[@]}"; do
  ms_number=$(ensure_milestone "$slug")
  if [[ -z "$ms_number" ]]; then
    echo "  warn: could not ensure milestone '$slug', skipping"
    continue
  fi
  slug_to_milestone_num["$slug"]="$ms_number"

  nums="${slug_to_nums[$slug]}"
  IFS=',' read -r -a bound_nums <<<"$nums"
  for n in "${bound_nums[@]}"; do
    [[ -z "$n" ]] && continue
    assign_milestone issue "$n" "$ms_number"
  done
done

# Step 3: scope-creep / un-scope-creep every open item.
declare -A bound_set
for n in "${all_bound[@]}"; do
  [[ -n "$n" ]] && bound_set["$n"]=1
done

apply_scope_creep() {
  local kind="$1"
  while IFS=$'\t' read -r number has_creep has_milestone; do
    if [[ -n "${bound_set[$number]:-}" ]] || [[ "$has_milestone" == "true" ]]; then
      if [[ "$has_creep" == "true" ]]; then
        gh "$kind" edit "$number" "${REPO_FLAG[@]}" --remove-label "$SCOPE_CREEP_LABEL" >/dev/null 2>&1 \
          || echo "  warn: $kind #$number — couldn't remove $SCOPE_CREEP_LABEL"
      fi
    else
      if [[ "$has_creep" != "true" ]]; then
        gh "$kind" edit "$number" "${REPO_FLAG[@]}" --add-label "$SCOPE_CREEP_LABEL" >/dev/null 2>&1 \
          || echo "  warn: $kind #$number — couldn't add $SCOPE_CREEP_LABEL"
      fi
    fi
  done
}

echo "reconcile-milestones: reconciling scope-creep on open issues..."
gh issue list "${REPO_FLAG[@]}" --state open --limit 200 \
  --json number,labels,milestone \
  --jq '.[] | [.number,
               (any(.labels[]; .name == "scope-creep") | tostring),
               ((.milestone // {}) | (.title // "") != "" | tostring)] | @tsv' \
  | apply_scope_creep issue

echo "reconcile-milestones: reconciling scope-creep on open PRs..."
gh pr list "${REPO_FLAG[@]}" --state open --limit 200 \
  --json number,labels,milestone \
  --jq '.[] | [.number,
               (any(.labels[]; .name == "scope-creep") | tostring),
               ((.milestone // {}) | (.title // "") != "" | tostring)] | @tsv' \
  | apply_scope_creep pr

echo "reconcile-milestones: done"
