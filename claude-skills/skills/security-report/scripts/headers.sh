#!/usr/bin/env bash
# headers.sh — audit HTTP security headers configured in the repo.
#
# Reads the server kind from the snapshot, applies a static catalog of
# required headers, and emits found[] / missing[] / weak[] lists. Returns
# `{"applicable": false}` for non-HTTP-serving repos.

set -euo pipefail

SNAPSHOT=""
while [[ $# -gt 0 ]]; do
  case $1 in
    --snapshot) SNAPSHOT="$2"; shift 2 ;;
    *) shift ;;
  esac
done

if [[ -z "$SNAPSHOT" ]]; then
  SNAPSHOT=$(mktemp -t security-snap.XXXXXX.json)
  trap 'rm -f "$SNAPSHOT"' EXIT
  SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
  bash "$SCRIPT_DIR/collect.sh" > "$SNAPSHOT"
fi

APPLICABLE=$(jq -r '.server.applicable' "$SNAPSHOT")
if [[ "$APPLICABLE" != "true" ]]; then
  echo '{"applicable": false}'
  exit 0
fi

SERVER_KIND=$(jq -r '.server.kind' "$SNAPSHOT")
REPO_ROOT=$(jq -r '.repoRoot' "$SNAPSHOT")
cd "$REPO_ROOT"

# Required headers + severity.
REQUIRED=(
  "Content-Security-Policy|critical"
  "Strict-Transport-Security|critical"
  "X-Content-Type-Options|high"
  "X-Frame-Options|high"
  "Referrer-Policy|moderate"
  "Permissions-Policy|moderate"
)

# Grep across likely config/source files. The heuristic is coarse on
# purpose — we're looking for "is this header mentioned anywhere" rather
# than "is it set correctly at runtime."
SEARCH_FILES=$(git ls-files '*.conf' '*.js' '*.ts' '*.py' '*.toml' '*.json' '*.yaml' '*.yml' '.htaccess' Caddyfile 2>/dev/null | tr '\n' ' ')

FOUND='[]'
MISSING='[]'
WEAK='[]'

for entry in "${REQUIRED[@]}"; do
  header="${entry%%|*}"
  severity="${entry#*|}"

  # Case-insensitive grep for the header name.
  if [[ -n "$SEARCH_FILES" ]] && grep -IliE "\b${header}\b" $SEARCH_FILES 2>/dev/null | head -1 | grep -q . ; then
    FOUND=$(jq --arg h "$header" '. + [$h]' <<<"$FOUND")

    # Soft heuristics for weakness.
    case "$header" in
      "Content-Security-Policy")
        if grep -IliE "Content-Security-Policy.*(unsafe-inline|unsafe-eval|\*)" $SEARCH_FILES 2>/dev/null | head -1 | grep -q . ; then
          WEAK=$(jq --arg h "$header" --arg s "$severity" --arg r "uses unsafe-inline / unsafe-eval / wildcard source" \
            '. + [{header: $h, severity: $s, reason: $r}]' <<<"$WEAK")
        fi
        ;;
      "Strict-Transport-Security")
        if ! grep -IliE "Strict-Transport-Security.*max-age=[3-9][0-9]{7,}" $SEARCH_FILES 2>/dev/null | head -1 | grep -q . ; then
          WEAK=$(jq --arg h "$header" --arg s "$severity" --arg r "max-age < 1 year or missing" \
            '. + [{header: $h, severity: $s, reason: $r}]' <<<"$WEAK")
        fi
        ;;
    esac
  else
    MISSING=$(jq --arg h "$header" --arg s "$severity" \
      '. + [{header: $h, severity: $s}]' <<<"$MISSING")
  fi
done

jq -n \
  --arg kind "$SERVER_KIND" \
  --argjson found "$FOUND" \
  --argjson missing "$MISSING" \
  --argjson weak "$WEAK" \
  '{
    applicable: true,
    serverKind: $kind,
    found: $found,
    missing: $missing,
    weak: $weak
  }'
