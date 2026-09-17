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

etime_to_seconds() {
  printf '%s\n' "$1" | awk -F'[-:]' '{
    n = NF
    s = $n + 0
    m = (n >= 2) ? $(n-1) + 0 : 0
    h = (n >= 3) ? $(n-2) + 0 : 0
    d = (n >= 4) ? $(n-3) + 0 : 0
    print ((d * 24 + h) * 60 + m) * 60 + s
  }'
}

# Default enumerator: live `claude` processes with a resolvable cwd.
default_provider() {
  local pid ppid cwd rss etime age
  for pid in $(pgrep -f '^claude|/claude ' 2>/dev/null || true); do
    cwd="$(lsof -a -p "$pid" -d cwd -Fn 2>/dev/null | sed -n 's/^n//p' | head -1)"
    [ -n "$cwd" ] || continue
    ppid="$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ')"
    rss="$(ps -o rss= -p "$pid" 2>/dev/null | tr -d ' ')"
    etime="$(ps -o etime= -p "$pid" 2>/dev/null | tr -d ' ')"
    [ -n "$rss" ] || continue
    age="$([ -n "$etime" ] && etime_to_seconds "$etime" || echo 0)"
    printf '%s\t%s\t%s\t%s\t%s\n' \
      "$pid" "${ppid:-1}" "$cwd" "$((rss / 1024))" "$age"
  done
}

# git_field <cwd> <what> — echo one piece of git state, empty when absent.
# All branches are guarded to return empty on git failure, never abort caller.
git_field() {
  local cwd="$1" what="$2"
  git -C "$cwd" rev-parse --git-dir >/dev/null 2>&1 || return 0
  case "$what" in
    repo)
      # owner/name from https, ssh and scp-style remotes alike. No
      # non-greedy quantifiers — POSIX ERE has none.
      (git -C "$cwd" remote get-url origin 2>/dev/null || echo "") | \
        sed -E 's#\.git$##; s#^git@[^:]+:##; s#^[a-z]+://[^/]+/##'
      ;;
    branch)   (git -C "$cwd" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "") ;;
    upstream) (git -C "$cwd" rev-parse --abbrev-ref '@{u}' 2>/dev/null || echo "") ;;
    dirty)    (git -C "$cwd" status --porcelain 2>/dev/null || echo "") | wc -l | tr -d ' ' ;;
  esac
}

# base_ref <cwd> — the remote base branch, defaulting to main.
# Guarded to never abort: git failure on origin/HEAD yields empty, defaults to main.
base_ref() {
  local cwd="$1" b
  b="$( (git -C "$cwd" symbolic-ref refs/remotes/origin/HEAD 2>/dev/null || echo "") | \
       sed 's#.*origin/##' )"
  printf '%s\n' "${b:-main}"
}

# unpushed_count <cwd> <upstream> — commits not on the upstream. With no
# upstream every commit ahead of the base counts (PRD-009 §5.4.2).
unpushed_count() {
  local cwd="$1" upstream="$2" base
  git -C "$cwd" rev-parse --git-dir >/dev/null 2>&1 || { echo 0; return; }
  if [ -n "$upstream" ]; then
    git -C "$cwd" rev-list --count "$upstream..HEAD" 2>/dev/null || echo 0
  else
    base="origin/$(base_ref "$cwd")"
    git -C "$cwd" rev-list --count "$base..HEAD" 2>/dev/null || echo 0
  fi
}

# merged_into_base <cwd> — true when HEAD is already an ancestor of base.
merged_into_base() {
  local cwd="$1"
  git -C "$cwd" rev-parse --git-dir >/dev/null 2>&1 || { echo false; return; }
  if git -C "$cwd" merge-base --is-ancestor HEAD "origin/$(base_ref "$cwd")" 2>/dev/null
  then echo true; else echo false; fi
}

verdict_for() {
  local pid="$1" age="$2" dirty="$3" unpushed="$4" merged="$5" is_repo="$6"
  if [ "$pid" = "$SELF_PID" ];        then echo "keep:self";      return; fi
  if [ "$age" -lt "$MIN_AGE_SECONDS" ]; then echo "keep:too-young"; return; fi
  if [ "$is_repo" != "true" ];        then echo "unknown";        return; fi
  if [ "$dirty" -gt 0 ];              then echo "keep:dirty";     return; fi
  if [ "$unpushed" -gt 0 ];           then echo "keep:unpushed";  return; fi
  if [ "$merged" = "true" ];          then echo "reapable";       return; fi
  echo "unknown"
}

main() {
  local rows collapsed pid ppid cwd rss age is_repo repo branch upstream dirty unpushed merged

  rows="$(if [ -n "${BSG_SESSION_PROVIDER:-}" ]; then
    "$BSG_SESSION_PROVIDER"
  else
    default_provider
  fi)"

  [ -n "$rows" ] || return 0

  # Collapse wrapper/child pairs: when a row's pid is another row's ppid and
  # both share a cwd, THIS row is the launcher shell — drop it and keep the
  # child, which is the real session holding the memory.
  collapsed="$(awk -F'\t' '
    NR == FNR { child_cwd[$2] = $3; next }
    { if (($1 in child_cwd) && child_cwd[$1] == $3) next; print }
  ' <(printf '%s\n' "$rows") <(printf '%s\n' "$rows"))"

  printf '%s\n' "$collapsed" | while IFS=$'\t' read -r pid ppid cwd rss age; do
    [ -n "$pid" ] || continue
    is_repo=false
    git -C "$cwd" rev-parse --git-dir >/dev/null 2>&1 && is_repo=true
    repo="$(git_field "$cwd" repo)"
    branch="$(git_field "$cwd" branch)"
    upstream="$(git_field "$cwd" upstream)"
    dirty="$(git_field "$cwd" dirty)"; dirty="${dirty:-0}"
    unpushed="$(unpushed_count "$cwd" "$upstream")"
    merged="$(merged_into_base "$cwd")"
    jq -nc \
      --argjson pid "$pid" \
      --argjson ppid "$ppid" \
      --arg cwd "$cwd" \
      --argjson rss_mb "$rss" \
      --argjson age_seconds "$age" \
      --arg repo "$repo" \
      --arg branch "$branch" \
      --arg upstream "$upstream" \
      --argjson dirty "$dirty" \
      --argjson unpushed "$unpushed" \
      --argjson merged_into_base "$merged" \
      --arg verdict "$(verdict_for "$pid" "$age" "$dirty" "$unpushed" "$merged" "$is_repo")" \
      '{pid: $pid, ppid: $ppid, cwd: $cwd, rss_mb: $rss_mb,
        age_seconds: $age_seconds,
        repo: (if $repo == "" then null else $repo end),
        branch: (if $branch == "" then null else $branch end),
        upstream: (if $upstream == "" then null else $upstream end),
        dirty: $dirty, unpushed: $unpushed,
        merged_into_base: $merged_into_base, verdict: $verdict}'
  done
}

# Run only when executed. Sourcing this file defines the helpers without
# emitting anything, so the pure functions above can be unit-tested directly.
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  main "$@"
fi
