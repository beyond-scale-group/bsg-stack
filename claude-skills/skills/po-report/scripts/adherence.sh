#!/usr/bin/env bash
# adherence.sh — join PLAN.md items with the snapshot; emit matrix + drift.
#
# For each plan item (from parse-plan.sh), look up every GitHub
# binding in the snapshot (from collect.sh) and compute a status:
#
#   done         — every binding is fully closed
#   at_risk      — any milestone binding has the at_risk / overdue flag
#   in_progress  — at least one binding has mixed open/closed
#   not_started  — every binding has zero matching items
#   abandoned    — not_started AND (milestone overdue OR no activity ever)
#
# Also emits three drift classes:
#   scopeCreep        — open non-draft PRs / issues matching no plan binding
#   abandonedItems    — plan items where status resolved to "abandoned"
#   offCourse         — plan items bound to an overdue milestone with 0 open
#
# Usage:
#   bash adherence.sh                              # auto plan + snapshot
#   bash adherence.sh --snapshot /tmp/snap.json    # reuse snapshot
#   bash adherence.sh --plan /tmp/PLAN.md          # custom plan path
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"

PLAN_PATH=""
snapshot_path=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --plan) PLAN_PATH="$2"; shift 2 ;;
    --snapshot) snapshot_path="$2"; shift 2 ;;
    *) echo "adherence.sh: unknown arg: $1" >&2; exit 2 ;;
  esac
done

# --- snapshot ---
snapshot=""
if [[ -n "$snapshot_path" ]]; then
  snapshot=$(cat "$snapshot_path")
elif [[ ! -t 0 ]]; then
  snapshot=$(cat)
fi
if [[ -z "$snapshot" ]]; then
  snapshot=$(bash "$HERE/collect.sh")
fi

# --- plan items ---
if [[ -z "$PLAN_PATH" ]]; then
  plan_args=()
else
  plan_args=(--plan "$PLAN_PATH")
fi
plan_json=$(bash "$HERE/parse-plan.sh" "${plan_args[@]}")

# --- milestone risk flags (reuse existing script) ---
milestones_json=$(printf '%s' "$snapshot" | bash "$HERE/milestone-progress.sh")

# --- derive adherence ---
# One big jq program. --argjson passes pre-parsed JSON; --arg passes the
# resolved plan path for the report metadata.
printf '%s' "$snapshot" | jq \
  --argjson plan "$plan_json" \
  --argjson milestones "$milestones_json" \
  --arg planPath "${PLAN_PATH:-po/PLAN.md}" '
  . as $snap
  | $plan as $planItems
  | ($planItems | length > 0) as $planFound

  # --- per-item status --------------------------------------------------
  | ($planItems | map(
      . as $item
      # --- evidence per binding kind -----------------------------------
      | ([$milestones[] | select(.title as $t | $item.bindings.milestones | index($t))]) as $msEv
      # Epic bindings match issues by number AND PRs directly referenced
      # by number (so `[#21]` works whether #21 is an issue or a PR).
      | ([$snap.issues[] | select(.number as $n | $item.bindings.epics | index($n))]) as $epicIssueEv
      | ([$snap.pullRequests[] | select(.number as $n | $item.bindings.epics | index($n))]) as $epicDirectPrEv
      | ([$snap.issues[]
           | select(.labels as $l
                    | any($item.bindings.labels[]; . as $needle | $l | index($needle))
                    )]) as $labelIssueEv
      | ([$snap.pullRequests[]
           | select(.labels as $l
                    | any($item.bindings.labels[]; . as $needle | $l | index($needle))
                    )]) as $labelPrEv
      # PRs closing into an epic issue count as epic activity too.
      | ([$snap.pullRequests[]
           | select(.closingIssues as $ci
                    | any($item.bindings.epics[]; . as $needle | $ci | index($needle))
                   )]) as $epicPrEv
      | ($epicIssueEv) as $epicEv
      | ($labelIssueEv) as $labelEv

      # --- counts per binding kind -------------------------------------
      | {
          openIssues:   (([$epicEv[], $labelEv[]] | map(select(.state == "OPEN"))   | length)),
          closedIssues: (([$epicEv[], $labelEv[]] | map(select(.state == "CLOSED")) | length)),
          openPrs:      (([$epicDirectPrEv[], $labelPrEv[], $epicPrEv[]] | unique_by(.number) | map(select(.state == "OPEN")) | length)),
          mergedPrs:    (([$epicDirectPrEv[], $labelPrEv[], $epicPrEv[]] | unique_by(.number) | map(select(.state == "MERGED")) | length)),
          milestoneOpen:   ([$msEv[].openIssues]   | add // 0),
          milestoneClosed: ([$msEv[].closedIssues] | add // 0),
          anyAtRisk:    ([$msEv[] | select(.flags.at_risk or .flags.overdue)] | length > 0),
          anyOverdue:   ([$msEv[] | select(.flags.overdue)] | length > 0),
          anyBindings:  (($item.bindings.milestones + ($item.bindings.epics|map(tostring)) + $item.bindings.labels) | length > 0)
        } as $counts

      | (
          if ($counts.anyBindings | not) then "not_started"
          elif ($counts.openIssues + $counts.closedIssues + $counts.milestoneOpen + $counts.milestoneClosed + $counts.openPrs + $counts.mergedPrs) == 0 then "not_started"
          elif $counts.anyAtRisk then "at_risk"
          elif ($counts.openIssues == 0 and $counts.milestoneOpen == 0 and $counts.openPrs == 0) and
               ($counts.closedIssues > 0 or $counts.milestoneClosed > 0 or $counts.mergedPrs > 0) then "done"
          else "in_progress"
          end
        ) as $status

      | $item + {
          status: $status,
          counts: $counts,
          evidence: {
            milestones: ($msEv | map({title, percentComplete, dueOn, daysRemaining, flags})),
            issues:     ($epicEv + $labelEv | map({number, title, state, url, assignees, labels}) | unique_by(.number)),
            pullRequests: (($epicDirectPrEv + $labelPrEv + $epicPrEv) | unique_by(.number) | map({number, title, state, url, closingIssues}))
          }
        }
    )) as $scored

  # --- drift: scope creep ----------------------------------------------
  # Hoist the "bound" sets to top level so both issue + PR scope-creep
  # checks can see them.
  | [$planItems[].bindings.milestones[]] as $boundMilestones
  | [$planItems[].bindings.epics[]]      as $boundEpics
  | [$planItems[].bindings.labels[]]     as $boundLabels

  | [$snap.issues[]
      | select(.state == "OPEN")
      | . as $issue
      | ($issue.number) as $num
      | ($issue.milestone.title // null) as $mtitle
      | ($issue.labels) as $labs
      | select(
          ($mtitle == null or ($boundMilestones | index($mtitle)) == null)
          and ($boundEpics | index($num)) == null
          and (any($boundLabels[]; . as $n | $labs | index($n))) == false
        )
      | {number, title, url, labels, assignees}
    ] as $unplannedIssues

  | [$snap.pullRequests[]
      | select(.state == "OPEN" and (.isDraft | not))
      | . as $pr
      | ($pr.number) as $num
      | ($pr.closingIssues) as $ci
      | ($pr.labels) as $labs
      | select(
          ($boundEpics | index($num)) == null
          and (any($boundEpics[]; . as $n | $ci | index($n))) == false
          and (any($boundLabels[]; . as $n | $labs | index($n))) == false
        )
      | {number, title, url, labels}
    ] as $unplannedPrs

  | {
      planPath: $planPath,
      planFound: $planFound,
      generatedAt: $snap.generatedAt,
      repo: $snap.repo,
      items: $scored,
      drift: {
        scopeCreep: {
          issues: $unplannedIssues,
          pullRequests: $unplannedPrs
        },
        abandonedItems: [$scored[]
          | select(.status == "not_started")
          | select(.counts.anyBindings)
          | {raw, section, bindings, line}
        ],
        offCourse: [$scored[]
          | select(.counts.anyOverdue and .counts.openIssues == 0 and .counts.milestoneOpen == 0)
          | {raw, section, bindings, line}
        ]
      },
      summary: (
        ($scored | group_by(.status) | map({key: .[0].status, value: length}) | from_entries) as $byStatus
        | {
            totalPlanItems: ($scored | length),
            notStarted:  ($byStatus.not_started // 0),
            inProgress:  ($byStatus.in_progress // 0),
            done:        ($byStatus.done        // 0),
            atRisk:      ($byStatus.at_risk     // 0),
            scopeCreep:  (($unplannedIssues | length) + ($unplannedPrs | length))
          }
      )
    }
'
