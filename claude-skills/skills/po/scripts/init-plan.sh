#!/usr/bin/env bash
# init-plan.sh — generate a draft PLAN.md from repo scan.
#
# Part of #237 (per-agent --init contract): scans the repo's open
# milestones, open issues, top labels, and README headings, then emits
# a draft `.bsg/PLAN.md` to stdout with milestone/epic/label binding
# tags (see po/references/plan-schema.md). The orchestrator
# (`/bsg-stack init`) captures stdout and opens a PR for human review —
# this script never writes to disk and never reads stdin.
#
# This is the contract-compliant `--init` entry point for the
# po-manager agent. The richer `bootstrap-plan.sh` is kept for the
# interactive "propose a starter plan" flow (it pulls a full snapshot
# via collect.sh); init-plan.sh is the lightweight, dependency-tolerant
# variant the bootstrap orchestrator can run unattended on a fresh repo.
#
# Usage:
#   bash init-plan.sh                 # auto-scan current repo
#   bash init-plan.sh --repo OWNER/NAME
#
# Exit 0 + content on stdout: success (always non-empty — a fresh repo
#   still gets a skeleton plan with placeholders to author by hand)
# Exit 1: error (missing required tool)

set -euo pipefail

REPO_FLAG=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) REPO_FLAG=(--repo "$2"); shift 2 ;;
    -h|--help) sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "init-plan.sh: unknown arg: $1" >&2; exit 2 ;;
  esac
done

command -v jq >/dev/null 2>&1 || { echo "init-plan.sh: jq is required" >&2; exit 1; }

REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
cd "$REPO_ROOT"

today=$(date -u +%F)

# ----------------------------------------------- signal collection

repo_name="unknown"
milestones_json='[]'
labels_json='[]'
epics_json='[]'
if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
  meta=$(gh repo view "${REPO_FLAG[@]}" --json name 2>/dev/null || echo '{}')
  repo_name=$(jq -r '.name // "unknown"' <<<"$meta")

  milestones_json=$(gh api "${REPO_FLAG[@]}" \
    'repos/{owner}/{repo}/milestones?state=open&per_page=50' 2>/dev/null \
    | jq '[.[] | {title: .title, dueOn: .due_on}]' 2>/dev/null || echo '[]')

  issues=$(gh issue list "${REPO_FLAG[@]}" --state open \
    --json number,title,labels --limit 200 2>/dev/null || echo '[]')

  labels_json=$(jq '
    [.[].labels[]?.name]
    | group_by(.) | map({name: .[0], count: length})
    | sort_by(-.count) | .[0:5]
  ' <<<"$issues" 2>/dev/null || echo '[]')

  epics_json=$(jq '
    [.[] | select(.labels | any(.[]?.name; . == "epic" or . == "type:epic"))
         | {num: .number, title: .title}]
    | .[0:8]
  ' <<<"$issues" 2>/dev/null || echo '[]')
fi

headings_json='[]'
if [[ -f README.md ]]; then
  headings_json=$(grep -E '^#{1,2} ' README.md 2>/dev/null \
    | sed -E 's/^#+[[:space:]]*//' \
    | head -8 \
    | jq -Rn '[inputs | select(length > 0)]' 2>/dev/null || echo '[]')
fi

# ----------------------------------------------- emit

cat <<HEAD
# Big plan — ${repo_name}

_Draft bootstrapped ${today}. Review, edit, and commit this file to
\`.bsg/PLAN.md\` to activate adherence reporting. The po-manager agent
reads it every tick and never writes back — see
\`po/references/plan-schema.md\` for the binding-tag grammar._

## Objectives

_Replace the seeded suggestions below with your real objectives. Each
bullet should carry at least one \`[milestone:...]\`, \`[epic:#N]\`, or
\`[label:...]\` binding._

HEAD

jq -r '
  if (. | length) == 0 then
    "- _No open milestones yet — author objectives here manually, adding bindings like `[milestone:...]` or `[epic:#N]`._"
  else
    map("- \(.title) — due \(.dueOn // "TBD")    [milestone:\(.title)]") | join("\n")
  end
' <<<"$milestones_json"

cat <<'MID'

## Milestones

MID

jq -r '
  if (. | length) == 0 then "- _None defined yet._"
  else map("- \(.title)    [milestone:\(.title)]") | join("\n")
  end
' <<<"$milestones_json"

cat <<'EPICS'

## Epics

_List parent issues that aggregate smaller work. Tag each with `[epic:#N]`._

EPICS

jq -r '
  if (. | length) == 0 then
    "- _No epic candidates detected. Add parent issues manually._"
  else
    map("- \(.title)    [epic:#\(.num)]") | join("\n")
  end
' <<<"$epics_json"

cat <<'LABELS'

## Cross-cutting work (by label)

_Use these for initiatives that span multiple milestones/epics. Tag each
bullet with `[label:...]`._

LABELS

jq -r '
  if (. | length) == 0 then "- _No labels in active use on open issues._"
  else map("- \(.name) (used on \(.count) open issue(s))    [label:\(.name)]") | join("\n")
  end
' <<<"$labels_json"

if [[ "$headings_json" != '[]' ]]; then
  cat <<'CTX'

## Context (seeded from README)

_README headings, for reference while authoring objectives. Delete once
the plan above is filled in._

CTX
  jq -r 'map("- \(.)") | join("\n")' <<<"$headings_json"
fi

cat <<'TAIL'

## Decision log

_Append dated decisions here so they survive in git history. Tag with
`[tag:decision]`._

- _No decisions logged yet._

## Tracked risks

_List known risks with `[tag:risk]`. Adherence reports keep them visible
every run._

- _No risks logged yet._
TAIL
