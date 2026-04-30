#!/usr/bin/env bash
# audit-labels.sh — verify BSG label-convention compliance on a repo.
#
# Rules every open item must satisfy:
#
#   1. Carry exactly one "bus label" from `claude-skills/agents/registry.json`
#      (po, security, qa, tech, seo, marketing, storytelling, pr-comms).
#      Two bus labels on the same item = ambiguous ownership → fail.
#
# What is NOT enforced here (yet):
#
#   - The `needs-human-review` / `human-reviewed` binary was dropped
#     in E10 (#286): the repo-level autopilot opt-in is now the gate,
#     and `human-reviewed` becomes a post-merge stamp posted by
#     `auto-merge-or-flag.sh` rather than a triage marker.
#   - PRs are audited the same way as issues; report PRs opened by
#     `open-report-pr.sh` auto-merge so quickly they rarely linger open
#     long enough to fail the audit in practice.
#   - Epic labels (from issue #180) — the audit stays silent on them
#     until that ticket lands.
#
# Usage:
#   bash claude-skills/scripts/audit-labels.sh [--repo OWNER/NAME]
#
# Exits 0 if all open items are compliant, 1 otherwise. Prints a
# per-item diagnosis on non-compliance. Safe to run repeatedly.

set -euo pipefail

REPO_FLAG=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo)
      REPO_FLAG=(--repo "$2")
      shift 2
      ;;
    -h|--help)
      sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      echo "audit-labels.sh: unknown arg: $1" >&2
      exit 2
      ;;
  esac
done

REGISTRY="$(git rev-parse --show-toplevel)/claude-skills/agents/registry.json"
if [[ ! -f "$REGISTRY" ]]; then
  echo "audit-labels.sh: cannot find registry at $REGISTRY" >&2
  exit 2
fi

mapfile -t BUS_LABELS < <(jq -r '.agents[].bus_label' "$REGISTRY")

fail=0
report_item() {
  local kind="$1" number="$2" reason="$3"
  echo "  ${kind} #${number}: ${reason}"
  fail=1
}

check_item() {
  local kind="$1" number="$2" labels_json="$3"

  local bus_count=0
  for lbl in "${BUS_LABELS[@]}"; do
    if jq -e --arg l "$lbl" '.[] | select(.name == $l)' <<<"$labels_json" >/dev/null; then
      bus_count=$((bus_count + 1))
    fi
  done
  case $bus_count in
    0) report_item "$kind" "$number" "missing bus label (expected one of: ${BUS_LABELS[*]})" ;;
    1) ;;
    *) report_item "$kind" "$number" "carries ${bus_count} bus labels (ambiguous ownership)" ;;
  esac
}

echo "Auditing open issues..."
while IFS=$'\t' read -r number labels; do
  check_item "issue" "$number" "$labels"
done < <(gh issue list "${REPO_FLAG[@]}" --state open --limit 200 \
          --json number,labels --jq '.[] | [.number, (.labels | tojson)] | @tsv')

echo "Auditing open PRs..."
while IFS=$'\t' read -r number labels; do
  check_item "PR" "$number" "$labels"
done < <(gh pr list "${REPO_FLAG[@]}" --state open --limit 200 \
          --json number,labels --jq '.[] | [.number, (.labels | tojson)] | @tsv')

if [[ "$fail" -eq 0 ]]; then
  echo "audit-labels: PASS"
  exit 0
else
  echo
  echo "audit-labels: FAIL — fix the items above, then re-run."
  exit 1
fi
