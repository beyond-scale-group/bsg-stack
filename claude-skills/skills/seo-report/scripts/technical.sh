#!/usr/bin/env bash
# technical.sh — sitemap / robots / canonical consistency checks.

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
  .sitemap as $sm
  | .robots  as $rb
  | (.pages // []) as $pages
  | (
      # Normalize sitemap URLs to just the path (strip scheme+host).
      ($sm.urls // [])
      | map(sub("^https?://[^/]+"; ""))
      | map(sub("/$"; ""))
    ) as $sitemapPaths
  | [ $pages[]
      | (.route | sub("/$"; "")) as $r
      | select(($sitemapPaths | index($r)) == null)
      | { page: .route, path: .file }
    ] as $notInSitemap
  | (
      # Canonical-host distribution
      ($pages | map(.canonical) | map(select(. != null)) | map(split("/")[0:3] | join("/"))
        | group_by(.) | map({ host: .[0], count: length })
        | sort_by(-.count))
    ) as $canonicalHosts
  | {
      sitemapFound: ($sm.path != null),
      sitemapPath: $sm.path,
      sitemapUrlCount: ($sm.urls | length),
      robotsFound: ($rb.path != null),
      robotsPath: $rb.path,
      robotsBlanketDisallow: $rb.blanketDisallow,
      pagesNotInSitemap: (if $sm.path == null then [] else $notInSitemap end),
      canonicalHosts: $canonicalHosts,
      canonicalInconsistent: (($canonicalHosts | length) > 1)
    }
' "$SNAPSHOT"
