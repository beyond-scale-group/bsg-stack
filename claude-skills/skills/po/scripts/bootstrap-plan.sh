#!/usr/bin/env bash
# bootstrap-plan.sh — propose a starter PLAN.md from a snapshot.
#
# Emits a draft markdown plan on stdout, seeded from the repo's open
# milestones and top labels. This script never touches the filesystem;
# `init.sh` (sibling) wraps it with the file-write + safety-check
# plumbing for `@po-manager init`. Direct callers can pipe this to a
# review file under `.bsg/drafts/`.
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

_Draft bootstrapped ${today}. Review and edit; once committed to \`.bsg/PLAN.md\` (legacy fallback: \`po/PLAN.md\`), adherence reporting activates on the next po-manager tick._

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
# When neither exists and >= 3 open issues are present, cluster by title
# token similarity and emit auto-suggested epics (issue #115).
printf '%s' "$snapshot" | jq -r '
  ["feat","fix","add","the","and","for","with","from","into","that","this","when",
   "page","flow","base","data","query","adds","sets","gets","puts","runs","make",
   "move","also","both","each","some","upon","have","been","will",
   "were","more","than","then","back","like","such","only"] as $stops
  | [.issues[] | select(.state == "OPEN")] as $open
  | ([.pullRequests[].closingIssues[]] | group_by(.) | map({num: .[0], refs: length}) | map(select(.refs >= 2))) as $by_refs
  | ([.issues[] | select(.labels | (type == "array") and any(.[]; . == "epic" or . == "type:epic"))] | map({num: .number, title: .title})) as $by_label
  | ($by_refs | map("- #\(.num) (referenced by \(.refs) PRs)    [epic:#\(.num)]")) as $lines_refs
  | ($by_label | map("- \(.title)    [epic:#\(.num)]")) as $lines_label
  | ($lines_refs + $lines_label) as $traditional
  | if ($traditional | length) > 0 then
      ($traditional | join("\n"))
    elif ($open | length) >= 3 then
      (($open | map({
          num: .number,
          title: .title,
          tokens: (.title | ascii_downcase | gsub("[^a-z0-9]"; " ") | split(" ")
                   | map(select(length >= 4))
                   | map(select(. as $t | $stops | any(.[]; . == $t) | not)))
        })) as $tagged
      | ([$tagged[].tokens[]] | group_by(.) | map({tok: .[0], cnt: length})
         | map(select(.cnt >= 2)) | sort_by(-.cnt)) as $hot_toks
      | ($hot_toks | map(.tok as $tok | {
          label: $tok,
          issues: [$tagged[] | select(.tokens | any(.[]; . == $tok)) | {num: .num, title: .title}]
        }) | map(select((.issues | length) >= 2))) as $clusters
      | if ($clusters | length) == 0 then
          "- _No epic candidates detected. Add parent issues manually._"
        else
          (["_Auto-suggested epic clusters based on title similarity. Review wording before committing._"] +
           ($clusters | map(
             "### E-\(.label) _auto-suggested, review wording_\n\n" +
             "> Scope: _set this_\n\n" +
             "**Binds:** \(.issues | map("#" + (.num | tostring)) | join(", "))\n" +
             "**Done when:** _set this_\n" +
             (.issues | map("- #\(.num) \(.title)    [epic:#\(.num)]") | join("\n"))
           ))) | join("\n\n")
        end)
    else
      "- _No epic candidates detected. Add parent issues manually._"
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
