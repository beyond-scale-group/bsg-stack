#!/usr/bin/env bash
# bootstrap-plan.sh — propose a starter PLAN.md from a snapshot.
#
# Emits a draft markdown plan on stdout, seeded from the repo's open
# milestones and top labels. The caller writes it to
# `po/drafts/PLAN-suggested-<date>.md` for a human to review and
# rename to `po/PLAN.md`. This script never touches the filesystem.
#
# Usage:
#   bash bootstrap-plan.sh                      # auto-collect snapshot
#   bash bootstrap-plan.sh --snapshot <path>    # reuse one
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"

snapshot_path=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --snapshot) snapshot_path="$2"; shift 2 ;;
    *) echo "bootstrap-plan.sh: unknown arg: $1" >&2; exit 2 ;;
  esac
done

snapshot=""
if [[ -n "$snapshot_path" ]]; then
  snapshot=$(cat "$snapshot_path")
elif [[ ! -t 0 ]]; then
  snapshot=$(cat)
fi
if [[ -z "$snapshot" ]]; then
  snapshot=$(bash "$HERE/collect.sh")
fi

repo=$(printf '%s' "$snapshot" | jq -r '.repo')
today=$(date -u +%F)

cat <<HEAD
# Big plan — ${repo}

_Draft bootstrapped ${today}. Review, edit, and \`git mv\` this file to \`po/PLAN.md\` to activate adherence reporting._

## Objectives

_Replace the bootstrapped suggestions below with your real objectives.
Each bullet should carry at least one \`[milestone:...]\`, \`[epic:#N]\`,
or \`[label:...]\` binding — see \`references/plan-schema.md\`._

HEAD

# Open milestones become seed objectives. If none exist we leave a
# placeholder so the human knows to author objectives by hand.
printf '%s' "$snapshot" | jq -r '
  [.milestones[] | select(.state == "open")] as $open
  | if ($open | length) == 0 then
      "- _No open milestones in this repo yet — author objectives here manually, adding bindings like `[milestone:...]` or `[epic:#N]`._"
    else
      $open | map("- \(.title) — due \(.dueOn // "TBD")    [milestone:\(.title)]") | join("\n")
    end
'

cat <<MID

## Milestones

MID

printf '%s' "$snapshot" | jq -r '
  [.milestones[] | select(.state == "open")] as $open
  | if ($open | length) == 0 then "- _None defined yet._"
    else $open | map("- \(.title)    [milestone:\(.title)]") | join("\n")
    end
'

cat <<'EPICS'

## Epics

_List parent issues that aggregate smaller work. Tag each one with `[epic:#N]`._

EPICS

# Infer epic candidates: issues that are referenced by >= 2 closing PRs
# are likely parents of sub-work. Fall back to issues with sub-issue
# labels (`epic`, `type:epic`) if any exist.
printf '%s' "$snapshot" | jq -r '
  ([.pullRequests[].closingIssues[]] | group_by(.) | map({num: .[0], refs: length}) | map(select(.refs >= 2))) as $by_refs
  | ([.issues[] | select(.labels | index("epic") or index("type:epic"))] | map({num: .number, title: .title})) as $by_label
  | ($by_refs | map(.num) | map(. as $n | (.[$n] // null))) as $_skip
  | ($by_refs | map("- #\(.num) (referenced by \(.refs) PRs)    [epic:#\(.num)]")) as $lines_refs
  | ($by_label | map("- \(.title)    [epic:#\(.num)]")) as $lines_label
  | ($lines_refs + $lines_label)
  | if (. | length) == 0 then "- _No epic candidates detected. Add parent issues manually._"
    else (. | join("\n"))
    end
'

cat <<'LABELS'

## Cross-cutting work (by label)

_Use these for initiatives that span multiple milestones/epics. Tag each bullet with `[label:...]`._

LABELS

# Top 5 labels across open issues become label-binding suggestions.
printf '%s' "$snapshot" | jq -r '
  ([.issues[] | select(.state == "OPEN") | .labels[]]
   | group_by(.) | map({name: .[0], count: length}) | sort_by(-.count) | .[0:5])
  | if (. | length) == 0 then "- _No labels in active use on open issues._"
    else (. | map("- \(.name) (used on \(.count) open issue(s))    [label:\(.name)]") | join("\n"))
    end
'

cat <<'TAIL'

## Decision log

_Append dated decisions here so they survive in git history. Tag with `[tag:decision]`._

- _No decisions logged yet._

## Tracked risks

_List known risks with `[tag:risk]`. Adherence reports will keep them visible every run._

- _No risks logged yet._
TAIL
