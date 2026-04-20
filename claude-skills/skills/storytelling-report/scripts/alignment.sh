#!/usr/bin/env bash
# alignment.sh — key-message + positioning alignment checker.

set -euo pipefail

SNAPSHOT=""
while [[ $# -gt 0 ]]; do
  case $1 in
    --snapshot) SNAPSHOT="$2"; shift 2 ;;
    *) shift ;;
  esac
done

if [[ -z "$SNAPSHOT" ]]; then
  SNAPSHOT=$(mktemp -t brand-snap.XXXXXX.json)
  trap 'rm -f "$SNAPSHOT"' EXIT
  SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
  bash "$SCRIPT_DIR/collect.sh" > "$SNAPSHOT"
fi

REPO_ROOT=$(jq -r '.repoRoot' "$SNAPSHOT")
cd "$REPO_ROOT"

# Build a per-asset lowercase body map for substring checks.
BODY_MAP_TMP=$(mktemp); trap 'rm -f "$BODY_MAP_TMP"' EXIT
while IFS= read -r f; do
  [[ -f "$f" ]] || continue
  # Lowercase body, one blob per file. Use | as separator.
  body=$(tr '[:upper:]' '[:lower:]' < "$f" | tr '\n' ' ')
  # shellcheck disable=SC2016
  printf '%s\t%s\n' "$f" "$body" >> "$BODY_MAP_TMP"
done < <(jq -r '.assets[].file' "$SNAPSHOT")

# For each key message, list which asset files contain it.
jq --rawfile bodies "$BODY_MAP_TMP" '
  ($bodies | split("\n") | map(split("\t"))
    | map(select(length == 2))
    | map({ file: .[0], body: .[1] })
  ) as $assets
  |
  (.narrative.keyMessages // []) as $messages
  | (.narrative.positioning.featureAnchors // []) as $anchors
  |
  [ $messages[] as $m
    | ($m | ascii_downcase) as $ml
    | {
        message: $m,
        inREADME:    ([$assets[] | select(.file == "README.md") | select(.body | contains($ml))] | length > 0),
        assetHits:   [$assets[] | select(.body | contains($ml)) | .file]
      }
  ] as $coverage
  |
  [ $coverage[] | select(.inREADME == false) | { message } ] as $missingInREADME
  |
  [ $anchors[] as $a
    | ($a | ascii_downcase) as $al
    | ($assets | map(select(.body | contains($al))) | length) as $hits
    | if $hits == 0 then
        { anchor: $a, reason: "no asset in this repo references this phrase" }
      else empty end
  ] as $stale
  |
  {
    summary: {
      messagesChecked: ($messages | length),
      messagesInREADME: ([$coverage[] | select(.inREADME)] | length),
      missingInREADME: ($missingInREADME | length),
      staleAnchors: ($stale | length)
    },
    coverage: $coverage,
    missingMessagesInREADME: $missingInREADME,
    positioning: .narrative.positioning,
    stalePositioning: $stale
  }
' "$SNAPSHOT"
