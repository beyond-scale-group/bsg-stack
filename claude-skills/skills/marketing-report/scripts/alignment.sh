#!/usr/bin/env bash
# alignment.sh — shipped-vs-marketed parity.

set -euo pipefail

SNAPSHOT=""
while [[ $# -gt 0 ]]; do
  case $1 in
    --snapshot) SNAPSHOT="$2"; shift 2 ;;
    *) shift ;;
  esac
done

if [[ -z "$SNAPSHOT" ]]; then
  SNAPSHOT=$(mktemp -t mkt-snap.XXXXXX.json)
  trap 'rm -f "$SNAPSHOT"' EXIT
  SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
  bash "$SCRIPT_DIR/collect.sh" > "$SNAPSHOT"
fi

jq '
  (.releases // []) as $releases
  | (.marketed // []) as $marketed
  | ([ $marketed[].claims[] ] | map(ascii_downcase)) as $claims
  |
  # For each shipped feature, find marketing files whose claims
  # contain the feature title as a substring (case-insensitive).
  (
    [ $releases[]
      | (.title // .tag) as $t
      | ($t | ascii_downcase) as $tl
      | ([ $marketed[] | select(.claims | map(ascii_downcase) | any(contains($tl))) | .file ]) as $hits
      | {
          feature: $t,
          release: .tag,
          releasedAt: .releasedAt,
          marketedIn: $hits,
          aligned: (($hits | length) > 0)
        }
    ]
  ) as $matrix
  |
  # Marketed claims that reference a specific version that did not ship.
  # We keep this list narrow: only flag H1/H2 lines that look like product
  # claims (> 2 words, not generic docs nav like "Overview" or "Table of
  # contents").
  (
    [ $marketed[] as $m
      | $m.claims[]
      | select((split(" ") | length) > 2)
      | select(ascii_downcase | test("(overview|table of contents|introduction|getting started)") | not)
      | ascii_downcase as $c
      | select([ $releases[] | (.title // .tag) | ascii_downcase | (. as $t | $c | contains($t)) ] | any | not)
      | { claim: ., foundIn: [$m.file] }
    ]
    | group_by(.claim)
    | map({ claim: .[0].claim, foundIn: (map(.foundIn) | add | unique) })
  ) as $unshipped
  |
  {
    summary: {
      shippedCount: ($releases | length),
      marketedCount: ($marketed | length),
      unmarketed: ([$matrix[] | select(.aligned | not)] | length),
      unshipped:  ($unshipped | length),
      aligned:    ([$matrix[] | select(.aligned)] | length)
    },
    aligned:    [$matrix[] | select(.aligned)],
    unmarketed: [$matrix[] | select(.aligned | not) | { feature, release, releasedAt }],
    unshipped: $unshipped
  }
' "$SNAPSHOT"
