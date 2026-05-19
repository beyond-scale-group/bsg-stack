#!/usr/bin/env bash
# commands.sh — stale README commands from the docs-report snapshot.
#
# Scans every README in the snapshot for shell-command patterns that
# reference a named target (`npm run X`, `pnpm X`, `yarn X`, `make X`)
# and flags any X that is no longer present in package.json scripts
# or Makefile targets.

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
SNAPSHOT=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --snapshot) SNAPSHOT="$2"; shift 2 ;;
    *) echo "commands.sh: unknown arg $1" >&2; exit 2 ;;
  esac
done

if [ -z "$SNAPSHOT" ]; then
  SNAPSHOT=$(mktemp -t docs-snap.XXXXXX.json)
  trap 'rm -f "$SNAPSHOT"' EXIT
  bash "$SCRIPT_DIR/collect.sh" > "$SNAPSHOT"
fi

REPO_ROOT=$(jq -r '.repoRoot' "$SNAPSHOT")
cd "$REPO_ROOT"

PKG=$(jq -r '.packageScripts | join(" ")' "$SNAPSHOT")
MAKE=$(jq -r '.makefileTargets | join(" ")' "$SNAPSHOT")

# Match shell-style invocations. We're deliberately conservative: only
# flag `npm run NAME` / `make NAME` patterns where NAME is alphanum +
# `-_:.` and is followed by whitespace, a backtick, or end-of-line.
extract_cmds() {
  local file="$1" tool="$2" pattern="$3"
  grep -oE "$pattern" "$file" 2>/dev/null \
    | sed -E "s/.*$tool[[:space:]]+([a-zA-Z0-9_:.-]+).*/\1/" \
    | sort -u || true
}

STALE='[]'
while IFS= read -r readme; do
  [ -z "$readme" ] && continue
  [ -f "$readme" ] || continue

  # npm run X / pnpm X / yarn X — all map to package.json scripts
  for tool in 'npm run' 'pnpm run' 'yarn run' 'pnpm' 'yarn'; do
    PATTERN="${tool}[[:space:]]+[a-zA-Z0-9_:.-]+"
    while IFS= read -r cmd; do
      [ -z "$cmd" ] && continue
      # Skip reserved verbs that aren't user-defined scripts.
      case "$cmd" in install|add|remove|update|outdated|audit|init|create|exec|publish|info|list|ls|test|start|run) ;; esac
      # `npm run test` is fine even if package.json doesn't define it
      # (npm has a built-in). Be conservative: only flag when the
      # package has a scripts block at all.
      [ "$PKG" = "" ] && continue
      if ! echo " $PKG " | grep -q " $cmd "; then
        STALE=$(jq --arg readme "$readme" --arg tool "$tool" --arg cmd "$cmd" \
          '. + [{readme: $readme, tool: $tool, command: $cmd}]' <<<"$STALE")
      fi
    done < <(extract_cmds "$readme" "$tool" "$PATTERN")
  done

  # make X — Makefile targets
  if [ -n "$MAKE" ]; then
    PATTERN='make[[:space:]]+[a-zA-Z0-9_.-]+'
    while IFS= read -r cmd; do
      [ -z "$cmd" ] && continue
      if ! echo " $MAKE " | grep -q " $cmd "; then
        STALE=$(jq --arg readme "$readme" --arg cmd "$cmd" \
          '. + [{readme: $readme, tool: "make", command: $cmd}]' <<<"$STALE")
      fi
    done < <(extract_cmds "$readme" "make" "$PATTERN")
  fi
done < <(jq -r '.readmes[]' "$SNAPSHOT")

jq -n \
  --argjson staleCommands "$STALE" \
  '{
    summary: { staleCommands: ($staleCommands | length) },
    staleCommands: $staleCommands
  }'
