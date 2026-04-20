#!/usr/bin/env bash
# events.sh — classify PR-worthy events.

set -euo pipefail

SNAPSHOT=""
while [[ $# -gt 0 ]]; do
  case $1 in
    --snapshot) SNAPSHOT="$2"; shift 2 ;;
    *) shift ;;
  esac
done

if [[ -z "$SNAPSHOT" ]]; then
  SNAPSHOT=$(mktemp -t comms-snap.XXXXXX.json)
  trap 'rm -f "$SNAPSHOT"' EXIT
  SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
  bash "$SCRIPT_DIR/collect.sh" > "$SNAPSHOT"
fi

jq '
  def classifyVersion(tag):
    tag
    | sub("^v"; "")
    | split(".")
    | [ .[]? | try (tonumber) catch 0 ]
    | if length < 3 then "unknown"
      elif .[2] != 0 then "patch"
      elif .[1] != 0 then "minor"
      else "major"
      end;

  def isAnnounced(tag; announced):
    [ announced[] | select(. == tag or . == "v" + (tag | sub("^v"; ""))) ]
    | length > 0;

  (.releases // []) as $releases
  | (.milestones // []) as $milestones
  | (.securityAdvisories // []) as $advisories
  | (.announced // []) as $announced
  | (.existingDrafts // []) as $drafts
  | (.contributors // 0) as $contribs
  | (.prsMerged // 0) as $prs
  |
  # Classify + filter releases.
  (
    [ $releases[] as $r
      | classifyVersion($r.tag) as $k
      | {
          release: $r.tag,
          title: $r.title,
          publishedAt: $r.publishedAt,
          kind: $k,
          announcedInLog: isAnnounced($r.tag; $announced),
          draftExists: ([ $drafts[] | select(.release == $r.tag or (.file | contains($r.tag))) ] | length > 0)
        }
    ]
  ) as $rel
  |
  # Unannounced major/minor = not in ANNOUNCED.md AND no existing press-release draft.
  (
    [ $rel[]
      | select(.kind == "major" or .kind == "minor")
      | select(.announcedInLog == false and .draftExists == false)
      | {
          release, title, publishedAt,
          type: .kind,
          priority: (if .kind == "major" then "high" else "medium" end)
        }
    ]
  ) as $unMajor
  |
  # Unannounced milestones = closed, not referenced in ANNOUNCED.md.
  (
    [ $milestones[]
      | select(.state == "closed" and .closedAt != null)
      | select(
          [ $announced[] | select(. == ("milestone #" + (.number | tostring))) ] | length == 0
        )
      | { milestone: .title, number, closedAt }
    ]
  ) as $unMilestone
  |
  # Community milestones at canonical thresholds: 100, 500, 1000 for each of contributors / PRs merged.
  ([ 100, 500, 1000 ]) as $thresholds
  | (
      [ $thresholds[] as $t
        | (if $contribs >= $t then { kind: "contributors", count: $t, hitAt: $contribs } else empty end)
      ] +
      [ $thresholds[] as $t
        | (if $prs >= $t then { kind: "prsMerged", count: $t, hitAt: $prs } else empty end)
      ]
    ) as $community
  |
  {
    summary: {
      total: (($rel | length) + ($unMilestone | length) + ($advisories | length)),
      unannouncedMajor: ($unMajor | length),
      unannouncedMilestone: ($unMilestone | length),
      securityAdvisories: ($advisories | length),
      communityMilestones: ($community | length),
      patchesSkipped: ([$rel[] | select(.kind == "patch")] | length)
    },
    unannouncedMajor: $unMajor,
    unannouncedMilestone: $unMilestone,
    securityAdvisories: $advisories,
    communityMilestones: $community,
    allReleases: $rel
  }
' "$SNAPSHOT"
