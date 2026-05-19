#!/usr/bin/env bash
# bsg-docs.sh — `.bsg/` doc freshness from the docs-report snapshot.
#
# Walks `.bsg/*.md` (excluding `.bsg/adr/` — tech-report owns that),
# extracts path-like tokens (backtick-wrapped strings that look like
# file paths), and checks each for existence. Emits `deadReferences[]`
# and a (best-effort, currently empty) `contradictions[]` placeholder
# for future iterations.

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
SNAPSHOT=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --snapshot) SNAPSHOT="$2"; shift 2 ;;
    *) echo "bsg-docs.sh: unknown arg $1" >&2; exit 2 ;;
  esac
done

if [ -z "$SNAPSHOT" ]; then
  SNAPSHOT=$(mktemp -t docs-snap.XXXXXX.json)
  trap 'rm -f "$SNAPSHOT"' EXIT
  bash "$SCRIPT_DIR/collect.sh" > "$SNAPSHOT"
fi

REPO_ROOT=$(jq -r '.repoRoot' "$SNAPSHOT")
cd "$REPO_ROOT"

DEAD='[]'
STALE='[]'

while IFS= read -r doc; do
  [ -z "$doc" ] && continue
  [ -f "$doc" ] || continue

  # Extract backtick-wrapped path-like tokens. We only consider tokens
  # with a path separator or a recognizable extension to avoid noise
  # from inline command names (e.g. `npm`, `jq`).
  while IFS= read -r token; do
    [ -z "$token" ] && continue
    case "$token" in
      */* | *.md | *.sh | *.py | *.js | *.ts | *.json | *.yml | *.yaml | *.toml) ;;
      *) continue ;;
    esac
    # Strip backticks already done by the grep. Strip a trailing punctuation.
    cleaned=$(echo "$token" | sed -E 's/[.,;:]+$//')
    # Skip http(s) and absolute external paths.
    case "$cleaned" in
      http://*|https://*) continue ;;
    esac
    # Resolve absolute paths as repo-relative.
    if [ "${cleaned#/}" != "$cleaned" ]; then
      candidate=".${cleaned}"
    else
      candidate="$cleaned"
    fi
    if [ -e "$candidate" ]; then
      continue
    fi
    DEAD=$(jq --arg doc "$doc" --arg ref "$cleaned" \
      '. + [{doc: $doc, reference: $ref}]' <<<"$DEAD")
  done < <(grep -oE '`[^`]+`' "$doc" 2>/dev/null | sed -E 's/^`(.*)`$/\1/' | sort -u)

  # Stale-since-bump signal: doc untouched since the most recent git tag.
  LAST_MOD=$(git log -1 --format=%ct -- "$doc" 2>/dev/null || echo "0")
  LATEST_TAG_TIME=$(git for-each-ref --sort=-taggerdate --format='%(taggerdate:unix)' refs/tags 2>/dev/null \
    | head -1)
  LATEST_TAG_TIME=${LATEST_TAG_TIME:-0}
  if [ "$LATEST_TAG_TIME" -gt 0 ] && [ "$LAST_MOD" -lt "$LATEST_TAG_TIME" ]; then
    STALE=$(jq --arg doc "$doc" \
      '. + [{doc: $doc, reason: "unedited since latest tag"}]' <<<"$STALE")
  fi
done < <(jq -r '.bsgDocs[]' "$SNAPSHOT")

# Contradictions: best-effort placeholder. Detecting "doc A says X,
# doc B says not-X" requires semantic parsing beyond what bash+jq does
# well. Emit an empty array so downstream consumers have the shape
# they expect; future iterations may use embeddings or a model call.
jq -n \
  --argjson deadReferences "$DEAD" \
  --argjson staleSinceBump "$STALE" \
  '{
    summary: {
      deadReferences: ($deadReferences | length),
      staleSinceBump: ($staleSinceBump | length),
      contradictions: 0
    },
    deadReferences: $deadReferences,
    staleSinceBump: $staleSinceBump,
    contradictions: []
  }'
