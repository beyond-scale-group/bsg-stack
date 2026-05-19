#!/usr/bin/env bash
# changelog.sh — CHANGELOG gap analysis from the docs-report snapshot.
#
# Parses CHANGELOG.md for version-bearing headings (e.g. `## [v1.0.0]`,
# `## 1.2.3`, `## v0.4.0 - 2024-01-15`) and compares the set with
# `git tag --list`. Tags present in git but absent from CHANGELOG are
# emitted as `missingTags[]`.

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
SNAPSHOT=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --snapshot) SNAPSHOT="$2"; shift 2 ;;
    *) echo "changelog.sh: unknown arg $1" >&2; exit 2 ;;
  esac
done

if [ -z "$SNAPSHOT" ]; then
  SNAPSHOT=$(mktemp -t docs-snap.XXXXXX.json)
  trap 'rm -f "$SNAPSHOT"' EXIT
  bash "$SCRIPT_DIR/collect.sh" > "$SNAPSHOT"
fi

CHANGELOG=$(jq -r '.changelog // ""' "$SNAPSHOT")
TAGS_JSON=$(jq -c '.gitTags' "$SNAPSHOT")

if [ -z "$CHANGELOG" ] || [ ! -f "$CHANGELOG" ]; then
  # No CHANGELOG → can't compute a gap. Emit empty result.
  jq -n --argjson tags "$TAGS_JSON" '{
    summary: { changelogFound: false, missingTags: ($tags | length) },
    changelogFound: false,
    missingTags: $tags
  }'
  exit 0
fi

# Extract version-like tokens from heading lines. We accept any of:
#   ## [1.0.0]
#   ## v1.0.0
#   ## 1.0.0 - 2024-01-15
#   # [v1.2.3] - 2024-...
LOGGED_VERSIONS=$( { grep -E '^#{1,3} ' "$CHANGELOG" 2>/dev/null || true; } \
  | { grep -oE 'v?[0-9]+\.[0-9]+\.[0-9]+[a-zA-Z0-9.-]*' || true; } \
  | sort -u \
  | jq -R -s -c 'split("\n") | map(select(length > 0))')

# Normalize: strip leading "v" so v1.0.0 == 1.0.0 for comparison.
MISSING=$(jq -c -n \
  --argjson tags "$TAGS_JSON" \
  --argjson logged "$LOGGED_VERSIONS" \
  '
    ($tags | map({raw: ., norm: (ltrimstr("v"))})) as $tags_n
    | ($logged | map(ltrimstr("v"))) as $logged_n
    | [$tags_n[] | select(.norm as $t | $logged_n | index($t) | not) | .raw]
  ')

jq -n \
  --arg changelog "$CHANGELOG" \
  --argjson missingTags "$MISSING" \
  --argjson loggedVersions "$LOGGED_VERSIONS" \
  '{
    summary: {
      changelogFound: true,
      loggedVersions: ($loggedVersions | length),
      missingTags: ($missingTags | length)
    },
    changelogFound: true,
    changelogPath: $changelog,
    loggedVersions: $loggedVersions,
    missingTags: $missingTags
  }'
