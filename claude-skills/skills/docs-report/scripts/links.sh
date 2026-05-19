#!/usr/bin/env bash
# links.sh — broken markdown links from the docs-report snapshot.
#
# A link is "broken" when its target is a relative path AND the file
# does not exist in the working tree. HTTP(S), mailto:, and bare
# fragments are out of scope.

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
SNAPSHOT=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --snapshot) SNAPSHOT="$2"; shift 2 ;;
    *) echo "links.sh: unknown arg $1" >&2; exit 2 ;;
  esac
done

if [ -z "$SNAPSHOT" ]; then
  SNAPSHOT=$(mktemp -t docs-snap.XXXXXX.json)
  trap 'rm -f "$SNAPSHOT"' EXIT
  bash "$SCRIPT_DIR/collect.sh" > "$SNAPSHOT"
fi

REPO_ROOT=$(jq -r '.repoRoot' "$SNAPSHOT")
cd "$REPO_ROOT"

# Stream every (sourceFile, linkTarget) pair and filter to broken
# relative-path targets. We resolve each target relative to its
# source's directory so links like ../foo.md work as expected.
BROKEN='[]'
while IFS=$'\t' read -r src target; do
  [ -z "$src" ] && continue
  [ -z "$target" ] && continue
  case "$target" in
    http://*|https://*|mailto:*|tel:*) continue ;;
    /*) candidate="$target" ;;          # absolute repo path
    *) candidate="$(dirname "$src")/$target" ;;
  esac
  # Normalize ./, ../ — portable: rely on python if installed, fall
  # back to cd-and-pwd. Either way we end up with a repo-relative path.
  if [ -e "$candidate" ]; then
    continue
  fi
  BROKEN=$(jq --arg src "$src" --arg target "$target" \
    '. + [{source: $src, target: $target}]' <<<"$BROKEN")
done < <(jq -r '.markdownFiles[] | .path as $p | .links[] | [$p, .] | @tsv' "$SNAPSHOT")

jq -n \
  --argjson brokenLinks "$BROKEN" \
  '{
    summary: { brokenLinks: ($brokenLinks | length) },
    brokenLinks: $brokenLinks
  }'
