#!/usr/bin/env bash
# meta.sh — per-page meta tag coverage.

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
  (.pages // []) as $pages
  | [ $pages[] | select(.title == null)       | { page: .route, file: .file } ] as $noTitle
  | [ $pages[] | select(.description == null) | { page: .route, file: .file } ] as $noDesc
  | [ $pages[] | select(.canonical == null)   | { page: .route, file: .file } ] as $noCanonical
  | [ $pages[] | select((.og.title + .og.description + .og.image) | tostring | test("true"))
              | select([.og.title, .og.description, .og.image] | all | not)
              | { page: .route,
                  have: ([
                    (if .og.title then "title" else empty end),
                    (if .og.description then "description" else empty end),
                    (if .og.image then "image" else empty end)
                  ]),
                  missing: ([
                    (if .og.title then empty else "title" end),
                    (if .og.description then empty else "description" end),
                    (if .og.image then empty else "image" end)
                  ])
                }
    ] as $ogPartial
  | {
      summary: {
        pagesScanned: ($pages | length),
        missingTitle: ($noTitle | length),
        missingDescription: ($noDesc | length),
        missingCanonical: ($noCanonical | length),
        ogCoverage: {
          full:    ([$pages[] | select(.og.title and .og.description and .og.image)] | length),
          partial: ($ogPartial | length),
          none:    ([$pages[] | select((.og.title or .og.description or .og.image) | not)] | length)
        }
      },
      missingTitle: $noTitle,
      missingDescription: $noDesc,
      missingCanonical: $noCanonical,
      ogPartial: $ogPartial
    }
' "$SNAPSHOT"
