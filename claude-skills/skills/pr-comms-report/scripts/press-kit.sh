#!/usr/bin/env bash
# press-kit.sh — freshness audit of comms/press-kit/.

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
  (.pressKit // {}) as $pk
  | ["boilerplate.md", "fact-sheet.md", "leadership.md",
     "milestones.md", "faq.md", "contact.md"] as $recommended
  | (if $pk.present then
      ([ $recommended[] as $r | select([$pk.assets[] | .file] | index($r) == null) | $r ])
     else [] end) as $missing
  | (if $pk.present then
      [ $pk.assets[] | select(.ageDays > 90) ]
     else [] end) as $stale
  |
  {
    present: ($pk.present // false),
    directory: $pk.directory,
    assets: ($pk.assets // []) | map(. + { stale: (.ageDays > 90) }),
    staleAssets: $stale,
    missingRecommended: $missing
  }
' "$SNAPSHOT"
