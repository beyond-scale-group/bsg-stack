#!/usr/bin/env bash
# content.sh — keyword coverage against seo/KEYWORDS.md.

set -euo pipefail

SNAPSHOT=""
while [[ $# -gt 0 ]]; do
  case $1 in
    --snapshot) SNAPSHOT="$2"; shift 2 ;;
    *) shift ;;
  esac
done

if [[ -z "$SNAPSHOT" ]]; then
  SNAPSHOT=$(mktemp -t seo-snap.XXXXXX.json)
  trap 'rm -f "$SNAPSHOT"' EXIT
  SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
  bash "$SCRIPT_DIR/collect.sh" > "$SNAPSHOT"
fi

jq '
  (.keywords // null) as $kws
  | if $kws == null then
      { keywordsFound: false,
        summary: { total: 0, covered: 0, uncovered: 0 },
        coverage: [],
        uncoveredKeywords: [] }
    else
      (.pages // []) as $pages
      | [ $kws[] as $k
          | ($k | ascii_downcase) as $kl
          | ( [ $pages[]
                | select(
                    ((.title // "") | ascii_downcase | contains($kl))
                    or ((.description // "") | ascii_downcase | contains($kl))
                  )
                | .route
              ] | first // null
            ) as $match
          | { keyword: $k,
              status: (if $match == null then "uncovered" else "covered" end),
              page: $match }
        ] as $coverage
      | {
          keywordsFound: true,
          summary: {
            total: ($coverage | length),
            covered:   ([$coverage[] | select(.status == "covered")]   | length),
            uncovered: ([$coverage[] | select(.status == "uncovered")] | length)
          },
          coverage: $coverage,
          uncoveredKeywords: [ $coverage[] | select(.status == "uncovered") | { keyword } ]
        }
    end
' "$SNAPSHOT"
