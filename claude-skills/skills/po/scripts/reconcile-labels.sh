#!/usr/bin/env bash
# reconcile-labels.sh — apply epic:<slug> and scope-creep labels from po/PLAN.md
#
# Closes #180. po/PLAN.md carries inline [epic:#N] bindings but nothing on
# GitHub's side reflects them. This script turns those bindings into
# actual labels so the triage queue can be filtered by epic
# (label:epic:E1-tick-hygiene = "all E1 work") and unbound items
# surface with a scope-creep label.
#
# What it does, idempotently, on every run:
#
#   1. Parse po/PLAN.md via parse-plan.sh --typed. If the plan is missing
#      or unparseable, skip (no labels churn on drift).
#   2. For each "Epic" item (a bullet under ## Epics):
#      a. Extract a slug from the raw text: "**E1 tick-hygiene**" → E1-tick-hygiene
#      b. Ensure the label `epic:<slug>` exists on the repo
#      c. Apply `epic:<slug>` to every bound issue/PR (by .bindings.epics)
#      d. Remove `epic:<slug>` from any item that has it but is no
#         longer bound (plan has drifted)
#   3. For every OPEN issue/PR: add `scope-creep` if it has no epic
#      label, remove `scope-creep` if it does.
#   4. Never touch `needs-human-review` / `human-reviewed` / bus labels —
#      those have their own owners.
#
# Usage:
#   bash claude-skills/skills/po/scripts/reconcile-labels.sh [--repo OWNER/NAME]
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
    *) echo "reconcile-labels.sh: unknown arg: $1" >&2; exit 2 ;;
  esac
done

EPIC_COLOR="1d76db"
SCOPE_CREEP_COLOR="d4c5f9"
SCOPE_CREEP_LABEL="scope-creep"

ensure_label() {
  local name="$1" color="$2" desc="$3"
  gh label create "$name" "${REPO_FLAG[@]}" \
    --color "$color" --description "$desc" >/dev/null 2>&1 || true
}

plan_envelope=$(bash "$HERE/parse-plan.sh" --typed)
plan_status=$(jq -r '.status' <<<"$plan_envelope")

if [[ "$plan_status" != "ok" ]]; then
  echo "reconcile-labels: plan status = ${plan_status}, skipping"
  exit 0
fi

ensure_label "$SCOPE_CREEP_LABEL" "$SCOPE_CREEP_COLOR" \
  "Open issue/PR not bound to any po/PLAN.md epic — PO needs to triage"

# Build a map: slug -> jsonarray of issue numbers it binds to.
# Also collect the union of all bound numbers for the scope-creep pass.
mapfile -t epic_lines < <(
  jq -r '
    .items[]
    | select(.section == "Epics")
    | .bindings.epics as $nums
    | ($nums | map(tostring) | join(",")) as $nums_csv
    | .raw
    | capture("^\\*\\*(?<ep>E[0-9]+) (?<name>[a-z0-9-]+)\\*\\*")
    | "\(.ep)-\(.name)\t\($nums_csv)"
  ' <<<"$plan_envelope"
)

all_bound=()
declare -A slug_to_nums
for line in "${epic_lines[@]}"; do
  slug="${line%%$'\t'*}"
  nums="${line##*$'\t'}"
  slug_to_nums["$slug"]="$nums"
  IFS=',' read -r -a arr <<<"$nums"
  all_bound+=("${arr[@]}")
done

echo "reconcile-labels: ${#slug_to_nums[@]} epics parsed from plan"

# Step 2: apply epic:<slug> labels.
for slug in "${!slug_to_nums[@]}"; do
  label="epic:${slug}"
  nums="${slug_to_nums[$slug]}"
  ensure_label "$label" "$EPIC_COLOR" \
    "Plan epic ${slug} — bound in po/PLAN.md"

  IFS=',' read -r -a bound_nums <<<"$nums"
  for n in "${bound_nums[@]}"; do
    [[ -z "$n" ]] && continue
    # Apply to issues and PRs alike — bindings can target either.
    gh issue edit "$n" "${REPO_FLAG[@]}" --add-label "$label" >/dev/null 2>&1 \
      || gh pr edit "$n" "${REPO_FLAG[@]}" --add-label "$label" >/dev/null 2>&1 \
      || echo "  warn: #$n — couldn't apply $label"
  done
done

# Step 3: scope-creep / un-scope-creep every open item.
# Build a set of bound numbers for O(1) lookup.
declare -A bound_set
for n in "${all_bound[@]}"; do
  [[ -n "$n" ]] && bound_set["$n"]=1
done

apply_scope_creep() {
  local kind="$1"
  while IFS=$'\t' read -r number has_creep; do
    if [[ -n "${bound_set[$number]:-}" ]]; then
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

echo "reconcile-labels: reconciling scope-creep on open issues..."
gh issue list "${REPO_FLAG[@]}" --state open --limit 200 \
  --json number,labels \
  --jq '.[] | [.number, (any(.labels[]; .name == "scope-creep") | tostring)] | @tsv' \
  | apply_scope_creep issue

echo "reconcile-labels: reconciling scope-creep on open PRs..."
gh pr list "${REPO_FLAG[@]}" --state open --limit 200 \
  --json number,labels \
  --jq '.[] | [.number, (any(.labels[]; .name == "scope-creep") | tostring)] | @tsv' \
  | apply_scope_creep pr

echo "reconcile-labels: done"
