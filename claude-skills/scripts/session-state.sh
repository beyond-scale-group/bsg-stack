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
#   BSG_SESSION_SELF_PID  pid to classify as keep:self (default: resolved
#                         by walking up from $PPID to the nearest `claude`
#                         ancestor — see resolve_self_pid)
#
# Run locally:
#   bash claude-skills/scripts/session-state.sh | jq .
#
# Exits 0 with no output when no session is found.

set -euo pipefail

MIN_AGE_SECONDS=300

# Process-tree accessors, kept as one-line indirections so tests can stub
# them and drive resolve_self_pid over a synthetic ancestry.
_cmd_of()  { ps -o command= -p "$1" 2>/dev/null || true; }
_ppid_of() { ps -o ppid= -p "$1" 2>/dev/null | tr -d ' ' || true; }

# resolve_self_pid [start-pid] — the pid of the Claude session this janitor
# is running inside, found by walking up to the nearest Claude ancestor.
#
# $PPID alone is wrong: invoked as `bash session-state.sh` the parent is the
# calling shell, not the session, and each extra hop (a wrapper script, a
# tool harness) adds another. Getting this wrong means the janitor fails to
# recognise itself — and a later lot's `reap` could kill the very session
# running it. Falls back to the starting pid when no Claude ancestor is
# found, so an unrecognised environment errs toward protecting something
# rather than nothing.
resolve_self_pid() {
  local pid="${1:-$PPID}" start="${1:-$PPID}" cmd hops=0
  while [ -n "$pid" ] && [ "$pid" != "1" ] && [ "$hops" -lt 12 ]; do
    cmd="$(_cmd_of "$pid")"
    case "$cmd" in
      claude|claude\ *|*/claude|*/claude\ *) printf '%s\n' "$pid"; return 0 ;;
    esac
    pid="$(_ppid_of "$pid")"
    hops=$((hops + 1))
  done
  printf '%s\n' "$start"
}

SELF_PID="${BSG_SESSION_SELF_PID:-$(resolve_self_pid)}"

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

# claude_pids_from_ps — read `ps -Ao pid=,command=` on stdin, print the pid
# of every Claude session. Pure, so it is unit-testable with synthetic input.
#
# Why not pgrep: macOS pgrep excludes the calling process AND ALL ITS
# ANCESTORS unless given -a ("By default, the current pgrep or pkill process
# and all of its ancestors are excluded"). A janitor run from inside a Claude
# session is always a descendant of one, so pgrep hides precisely the session
# doing the looking — verified: 31 pids found, the caller's own session absent.
# `-a` is not an option either: on Linux procps it means --list-full.
claude_pids_from_ps() {
  awk '{ pid = $1; $1 = ""; sub(/^ /, "");
         if ($0 ~ /^claude/ || $0 ~ /\/claude /) print pid }'
}

# Default enumerator: live `claude` processes with a resolvable cwd.
default_provider() {
  local pid ppid cwd rss etime age
  for pid in $(ps -Ao pid=,command= 2>/dev/null | claude_pids_from_ps || true); do
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

# pr_json <cwd> <branch> — {"number":N,"state":"..."} or empty.
pr_json() {
  local cwd="$1" branch="$2" out
  [ -n "$branch" ] || return 0
  command -v gh >/dev/null 2>&1 || return 0
  out="$(gh pr view "$branch" --json number,state 2>/dev/null)" || return 0
  # `|| true`: under `set -e` a jq failure on empty or malformed input
  # would abort the whole run. A missing PR is normal, not an error.
  printf '%s' "$out" | jq -c 'select(.number != null) | {number, state}' 2>/dev/null || true
}

# issue_for <cwd> — the linked ticket, from the registry first.
issue_for() {
  local cwd="$1" reg="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/bsg-sessions.json"
  [ -f "$reg" ] || return 0
  # `|| true`: a malformed registry file must not abort the whole run.
  jq -r --arg k "$cwd" '.[$k].issue // empty' "$reg" 2>/dev/null || true
}

# is_busy <cwd> — true when the transcript changed within the age floor.
is_busy() {
  local cwd="$1" cfg enc dir newest now mtime
  cfg="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
  enc="$(printf '%s' "$cwd" | tr '/.+' '---')"
  dir="$cfg/projects/$enc"
  [ -d "$dir" ] || { echo false; return; }
  # `|| true`: an unmatched glob makes `ls` exit non-zero even though
  # "no transcript yet" is a normal, expected state, not an error.
  newest="$(ls -t "$dir"/*.jsonl 2>/dev/null | head -1 || true)"
  [ -n "$newest" ] || { echo false; return; }
  now="$(date +%s)"
  # `|| true`: a TOCTOU race (file removed between ls and stat) must not abort.
  mtime="$(stat -f %m "$newest" 2>/dev/null || stat -c %Y "$newest" 2>/dev/null || true)"
  [ -n "$mtime" ] || { echo false; return; }
  if [ $((now - mtime)) -lt "$MIN_AGE_SECONDS" ]; then echo true; else echo false; fi
}

# dev_servers <pid> <cwd> — pids of live servers rooted in the worktree.
dev_servers() {
  local pid="$1" cwd="$2"
  if [ -n "${BSG_SESSION_DEV_SERVER_CMD:-}" ]; then
    # `return 0`, not a bare `return`: a failing injected command must
    # not propagate its exit status and abort the whole run.
    "$BSG_SESSION_DEV_SERVER_CMD" "$pid" "$cwd"
    return 0
  fi
  pgrep -P "$pid" 2>/dev/null | while read -r child; do
    lsof -a -p "$child" -d cwd -Fn 2>/dev/null \
      | sed -n 's/^n//p' | grep -q "^$cwd" && echo "$child"
  done
  return 0
}

verdict_for() {
  local pid="$1" age="$2" dirty="$3" unpushed="$4" merged="$5" \
        is_repo="$6" busy="$7" servers="$8" pr_state="$9"
  if [ "$pid" = "$SELF_PID" ];          then echo "keep:self";        return; fi
  if [ "$age" -lt "$MIN_AGE_SECONDS" ]; then echo "keep:too-young";   return; fi
  if [ "$busy" = "true" ];              then echo "keep:busy";        return; fi
  if [ -n "$servers" ];                 then echo "keep:dev-servers"; return; fi
  if [ "$is_repo" != "true" ];          then echo "unknown";          return; fi
  if [ "$dirty" -gt 0 ];                then echo "keep:dirty";       return; fi
  if [ "$unpushed" -gt 0 ];             then echo "keep:unpushed";    return; fi
  if [ "$pr_state" = "OPEN" ];          then echo "keep:pr-open";     return; fi
  if [ "$merged" = "true" ] || [ "$pr_state" = "MERGED" ] \
     || [ "$pr_state" = "CLOSED" ];     then echo "reapable";         return; fi
  echo "unknown"
}

main() {
  local rows collapsed pid ppid cwd rss age is_repo repo branch upstream dirty unpushed merged \
        pr pr_state issue busy servers servers_json

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
    pr="$(pr_json "$cwd" "$branch")"
    pr_state="$(printf '%s' "$pr" | jq -r '.state // empty' 2>/dev/null)"
    issue="$(issue_for "$cwd")"
    busy="$(is_busy "$cwd")"
    servers="$(dev_servers "$pid" "$cwd" | tr '\n' ' ')"
    servers_json="$(printf '%s' "$servers" | tr ' ' '\n' \
      | jq -Rn '[inputs | select(length > 0) | tonumber]')"
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
      --argjson pr "${pr:-null}" \
      --arg issue "$issue" \
      --argjson busy "$busy" \
      --argjson dev_servers "$servers_json" \
      --arg verdict "$(verdict_for "$pid" "$age" "$dirty" "$unpushed" "$merged" \
                       "$is_repo" "$busy" "$servers" "$pr_state")" \
      '{pid: $pid, ppid: $ppid, cwd: $cwd, rss_mb: $rss_mb,
        age_seconds: $age_seconds,
        repo: (if $repo == "" then null else $repo end),
        branch: (if $branch == "" then null else $branch end),
        upstream: (if $upstream == "" then null else $upstream end),
        dirty: $dirty, unpushed: $unpushed,
        merged_into_base: $merged_into_base,
        pr: $pr,
        issue: (if $issue == "" then null else ($issue | tonumber) end),
        busy: $busy, dev_servers: $dev_servers,
        verdict: $verdict}'
  done
}

# Run only when executed. Sourcing this file defines the helpers without
# emitting anything, so the pure functions above can be unit-tested directly.
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  main "$@"
fi
