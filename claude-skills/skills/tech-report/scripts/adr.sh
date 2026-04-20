#!/usr/bin/env bash
# adr.sh — ADR index + gap detector.

set -euo pipefail

SNAPSHOT=""
while [[ $# -gt 0 ]]; do
  case $1 in
    --snapshot) SNAPSHOT="$2"; shift 2 ;;
    *) shift ;;
  esac
done

if [[ -z "$SNAPSHOT" ]]; then
  SNAPSHOT=$(mktemp -t tech-snap.XXXXXX.json)
  trap 'rm -f "$SNAPSHOT"' EXIT
  SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
  bash "$SCRIPT_DIR/collect.sh" > "$SNAPSHOT"
fi

# An added dependency is "undocumented" if no ADR file contains its
# name (case-insensitive substring match) in its path or title.
jq '
  (.adr.entries // []) as $adrs
  | (.newDeps // []) as $newDeps
  | ($adrs | map(.title + " " + .path | ascii_downcase)) as $adrIndex
  | [ $newDeps[] as $d
      | ($d.dependency | ascii_downcase) as $name
      | if ([$adrIndex[] | select(contains($name))] | length == 0) then
          $d + { reason: "new top-level dep with no matching ADR" }
        else empty end
    ] as $gaps
  |
  {
    dir: .adr.dir,
    index: $adrs,
    undocumentedDecisions: $gaps
  }
' "$SNAPSHOT"
