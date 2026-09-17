#!/usr/bin/env bash
# session-state.sh — emit one JSON object per live Claude Code session.
#
# The single source of truth for "what is this session, and may it be
# reaped". Consumers filter the `verdict` field; none re-derives the
# rules. Strictly read-only: it signals nothing and mutates nothing.
#
# Process enumeration is injectable so tests never touch a live session:
#   BSG_SESSION_PROVIDER  executable printing one TAB-separated row per
#                         session: pid, ppid, cwd, rss_mb, age_seconds
#   BSG_SESSION_SELF_PID  pid to classify as keep:self (default: $PPID)
#
# Run locally:
#   bash claude-skills/scripts/session-state.sh | jq .
#
# Exits 0 with no output when no session is found.

set -euo pipefail

MIN_AGE_SECONDS=300
SELF_PID="${BSG_SESSION_SELF_PID:-$PPID}"

# Default enumerator: live `claude` processes with a resolvable cwd.
default_provider() {
  local pid ppid cwd rss age
  for pid in $(pgrep -f '^claude|/claude ' 2>/dev/null || true); do
    cwd="$(lsof -a -p "$pid" -d cwd -Fn 2>/dev/null | sed -n 's/^n//p' | head -1)"
    [ -n "$cwd" ] || continue
    ppid="$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ')"
    rss="$(ps -o rss= -p "$pid" 2>/dev/null | tr -d ' ')"
    age="$(ps -o etimes= -p "$pid" 2>/dev/null | tr -d ' ')"
    [ -n "$rss" ] || continue
    printf '%s\t%s\t%s\t%s\t%s\n' \
      "$pid" "${ppid:-1}" "$cwd" "$((rss / 1024))" "${age:-0}"
  done
}

rows="$(if [ -n "${BSG_SESSION_PROVIDER:-}" ]; then
  "$BSG_SESSION_PROVIDER"
else
  default_provider
fi)"

[ -n "$rows" ] || exit 0

# Collapse wrapper/child pairs: when a row's pid is another row's ppid and
# both share a cwd, THIS row is the launcher shell — drop it and keep the
# child, which is the real session holding the memory.
collapsed="$(awk -F'\t' '
  NR == FNR { child_cwd[$2] = $3; next }
  { if (($1 in child_cwd) && child_cwd[$1] == $3) next; print }
' <(printf '%s\n' "$rows") <(printf '%s\n' "$rows"))"

verdict_for() {
  local pid="$1" age="$2"
  if [ "$pid" = "$SELF_PID" ]; then echo "keep:self"; return; fi
  if [ "$age" -lt "$MIN_AGE_SECONDS" ]; then echo "keep:too-young"; return; fi
  echo "unknown"
}

printf '%s\n' "$collapsed" | while IFS=$'\t' read -r pid ppid cwd rss age; do
  [ -n "$pid" ] || continue
  jq -nc \
    --argjson pid "$pid" \
    --argjson ppid "$ppid" \
    --arg cwd "$cwd" \
    --argjson rss_mb "$rss" \
    --argjson age_seconds "$age" \
    --arg verdict "$(verdict_for "$pid" "$age")" \
    '{pid: $pid, ppid: $ppid, cwd: $cwd, rss_mb: $rss_mb,
      age_seconds: $age_seconds, verdict: $verdict}'
done
