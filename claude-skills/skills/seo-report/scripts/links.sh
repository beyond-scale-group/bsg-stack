#!/usr/bin/env bash
# links.sh — internal link graph orphan / broken detector.

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
  | ([ $pages[].route ] | unique) as $routes
  | (
      reduce $pages[] as $p ({};
        reduce (($p.internalLinks // [])[]) as $t (.;
          # Normalize trailing slashes, drop query/hash.
          ($t | split("?")[0] | split("#")[0] | sub("/$"; "")) as $norm
          | .[$norm] = ((.[$norm] // []) + [$p.route])
        )
      )
    ) as $inbound
  |
  [ $pages[]
    | ($inbound[.route] // []) as $links
    | { route: .route, file: .file, inbound: ($links | length) }
  ] as $withInbound
  |
  [ $withInbound[] | select(.inbound == 0) | { page: .route, path: .file } ] as $orphans
  |
  (
    # Broken links: a link target that is not any known route.
    # Cheap heuristic — may false-positive on dynamic routes.
    [ $pages[] as $p
      | ($p.internalLinks // [])[] as $t
      | ($t | split("?")[0] | split("#")[0] | sub("/$"; "")) as $norm
      | select(($routes | index($norm)) == null and ($norm | test("^/\\[") | not))
      | { from: $p.file, target: $t }
    ]
  ) as $broken
  |
  ($pages | length) as $total
  | ($withInbound | map(.inbound) | add // 0) as $inboundSum
  |
  {
    summary: {
      totalPages: $total,
      orphanCount: ($orphans | length),
      brokenCount: ($broken | length),
      avgInboundLinks: (if $total == 0 then 0 else ($inboundSum * 1.0 / $total * 100 | floor / 100) end)
    },
    orphanPages: $orphans,
    brokenLinks: $broken,
    underLinked: [ $withInbound[] | select(.inbound > 0 and .inbound <= 1) | { page: .route, inbound: .inbound } ]
  }
' "$SNAPSHOT"
