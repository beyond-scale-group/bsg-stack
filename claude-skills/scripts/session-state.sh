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
#   BSG_SESSION_SELF_PPID parent of the above, also kept (PRD-009 §5.4.8).
#                         Default: `ps` on SELF_PID.
#   BSG_SESSION_DEV_SERVER_CMD
#                         executable printing one listening-server pid per
#                         line, given <session-pid> <worktree>.
#
# Run locally:
#   bash claude-skills/scripts/session-state.sh | jq .
#
# Exits 0 with no output when no session is found.
#
# ── The one rule every git call in this file obeys ─────────────────────
# Capture output ONLY on success:
#
#     out="$(git … 2>/dev/null)" || out=""
#
# never `$(git … || echo "")`. Several git plumbing commands print a
# literal placeholder to STDOUT *and* exit non-zero: `rev-parse
# --abbrev-ref '@{u}'` prints `@{u}` and exits 128 when the branch has
# branch.X.remote/merge configured but the tracking ref is gone (the
# ordinary state after a squash-merge deletes the remote branch and you
# `fetch --prune`), and `rev-parse --abbrev-ref HEAD` prints `HEAD` and
# exits 128 on an unborn HEAD. With `|| echo ""` the guard never fires —
# the placeholder is already on stdout — so `upstream` came out as the
# string "@{u}", `rev-list --count '@{u}..HEAD'` then failed, `unpushed`
# fell back to 0, and a session holding a commit that exists nowhere
# else was classified `reapable`. Two of 31 live sessions were in
# exactly that state.
#
# The `dirty` case in git_field is the one exception, and it is
# deliberately fail-CLOSED, not fail-open — see the comment there.

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
# PRD-009 §5.4.8 excludes the caller AND its parent. When SELF_PID is
# injected by a test, `ps` finds no such process and this stays empty,
# which the verdict ladder reads as "no parent to protect".
SELF_PPID="${BSG_SESSION_SELF_PPID:-$(_ppid_of "$SELF_PID")}"

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

# path_within <path> <root> — true when <path> is <root> or lies beneath it.
#
# Replaces `grep -q "^$cwd"`, which was wrong twice over: the needle was
# interpreted as a regex (`.` matches any character, and a worktree path
# full of dots is the common case), and a bare prefix match has no path
# boundary, so `/a/repo-old` counted as inside `/a/repo`. Both errors
# inflate `dev_servers`, and an inflated `dev_servers` silences every
# rung of the verdict ladder below it.
path_within() {
  local path="$1" root="${2%/}"
  [ -n "$path" ] || return 1
  [ -n "$root" ] || return 1
  case "$path" in
    "$root")   return 0 ;;
    "$root"/*) return 0 ;;
    *)         return 1 ;;
  esac
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

# descendants_from_ps <root-pid> — read `ps -Ao pid=,ppid=` on stdin and
# print every descendant of <root-pid>, at any depth, excluding the root.
# Pure, so it is unit-testable with synthetic input.
#
# One `ps` for the whole machine instead of one `pgrep -P` per node, and
# the full depth rather than direct children only: a dev server is
# usually a grandchild (`npm run dev` → node), so a one-level walk misses
# the founding case.
descendants_from_ps() {
  awk -v root="$1" '
    { kid[NR] = $1; par[NR] = $2; n = NR }
    END {
      seen[root] = 1
      changed = 1
      passes = 0
      while (changed && passes <= n) {
        changed = 0; passes++
        for (i = 1; i <= n; i++) {
          if (!seen[kid[i]] && seen[par[i]]) { seen[kid[i]] = 1; changed = 1 }
        }
      }
      for (i = 1; i <= n; i++) if (seen[kid[i]] && kid[i] != root) print kid[i]
    }'
}

# Default enumerator: live `claude` processes with a resolvable cwd.
default_provider() {
  local pid ppid cwd rss etime age ps_out
  ps_out="$(ps -Ao pid=,command= 2>/dev/null)" || ps_out=""
  [ -n "$ps_out" ] || return 0
  for pid in $(printf '%s\n' "$ps_out" | claude_pids_from_ps); do
    cwd="$(lsof -a -p "$pid" -d cwd -Fn 2>/dev/null | sed -n 's/^n//p' | head -1)" || cwd=""
    [ -n "$cwd" ] || continue
    ppid="$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ')" || ppid=""
    rss="$(ps -o rss= -p "$pid" 2>/dev/null | tr -d ' ')" || rss=""
    etime="$(ps -o etime= -p "$pid" 2>/dev/null | tr -d ' ')" || etime=""
    [ -n "$rss" ] || continue
    if [ -n "$etime" ]; then age="$(etime_to_seconds "$etime")"; else age=0; fi
    printf '%s\t%s\t%s\t%s\t%s\n' \
      "$pid" "${ppid:-1}" "$cwd" "$((rss / 1024))" "${age:-0}"
  done
}

# git_field <cwd> <what> — echo one piece of git state, empty when absent.
# Every branch captures on success only (see the header note); a git
# failure yields the empty string and never aborts the caller.
git_field() {
  local cwd="$1" what="$2" out
  git -C "$cwd" rev-parse --git-dir >/dev/null 2>&1 || return 0
  case "$what" in
    repo)
      # owner/name from https, ssh and scp-style remotes alike. No
      # non-greedy quantifiers — POSIX ERE has none.
      out="$(git -C "$cwd" remote get-url origin 2>/dev/null)" || out=""
      [ -n "$out" ] || return 0
      printf '%s\n' "$out" | sed -E 's#\.git$##; s#^git@[^:]+:##; s#^[a-z]+://[^/]+/##'
      ;;
    branch)
      # Prints "HEAD" and exits 128 on an unborn HEAD — capture on success only.
      out="$(git -C "$cwd" rev-parse --abbrev-ref HEAD 2>/dev/null)" || out=""
      printf '%s\n' "$out"
      ;;
    upstream)
      # Prints "@{u}" and exits 128 when the tracking ref is gone — same rule.
      out="$(git -C "$cwd" rev-parse --abbrev-ref '@{u}' 2>/dev/null)" || out=""
      printf '%s\n' "$out"
      ;;
    dirty)
      # The one field in this file that does NOT follow the header rule
      # above. Every other git call here fails OPEN (empty on failure)
      # because the danger for those fields is a placeholder string
      # mistaken for real data. `dirty` is different: it gates keep:dirty,
      # the rung that stops a worktree with real uncommitted work from
      # being destroyed. If `git status --porcelain` fails (for example
      # an unreadable `.git/index`), we cannot know the tree is clean —
      # so failure must count as dirty, not clean. Do not "fix" this to
      # match the capture-on-success pattern above; that reintroduces a
      # fail-open path straight into the reaper's most safety-critical
      # rung.
      if out="$(git -C "$cwd" status --porcelain 2>/dev/null)"; then
        if [ -z "$out" ]; then printf '0\n'
        else printf '%s\n' "$out" | wc -l | tr -d ' '; fi
      else
        printf '1\n'
      fi
      ;;
  esac
}

# base_ref <cwd> — the remote base branch, defaulting to main.
base_ref() {
  local cwd="$1" out b
  out="$(git -C "$cwd" symbolic-ref refs/remotes/origin/HEAD 2>/dev/null)" || out=""
  b="$(printf '%s\n' "$out" | sed 's#.*origin/##')"
  printf '%s\n' "${b:-main}"
}

# unpushed_count <cwd> <upstream> — commits not on the upstream. With no
# upstream every commit ahead of origin/<base> counts, and the branch is
# keep:unpushed exactly when it holds commits the base does not
# (PRD-009 §5.4.2). Always prints a non-negative integer.
unpushed_count() {
  local cwd="$1" upstream="$2" base out
  git -C "$cwd" rev-parse --git-dir >/dev/null 2>&1 || { echo 0; return; }
  if [ -n "$upstream" ]; then
    out="$(git -C "$cwd" rev-list --count "$upstream..HEAD" 2>/dev/null)" || out=""
  else
    base="origin/$(base_ref "$cwd")"
    out="$(git -C "$cwd" rev-list --count "$base..HEAD" 2>/dev/null)" || out=""
  fi
  case "$out" in
    ''|*[!0-9]*) echo 0 ;;
    *)           printf '%s\n' "$out" ;;
  esac
}

# merged_into_base <cwd> — true when HEAD is already an ancestor of base.
merged_into_base() {
  local cwd="$1"
  git -C "$cwd" rev-parse --git-dir >/dev/null 2>&1 || { echo false; return; }
  if git -C "$cwd" merge-base --is-ancestor HEAD "origin/$(base_ref "$cwd")" 2>/dev/null
  then echo true; else echo false; fi
}

# pr_json <repo> <branch> — {"number":N,"state":"..."} or empty.
#
# `--repo` is load-bearing. Without it `gh` resolves the repository from
# the JANITOR's own working directory, not the session's: 0 of 31 live
# sessions resolved a PR, so keep:pr-open could never fire for a session
# outside the janitor's repo, and a same-named branch with a MERGED PR in
# the janitor's repo would have marked a foreign session reapable.
pr_json() {
  local repo="$1" branch="$2" out
  [ -n "$repo" ] || return 0
  [ -n "$branch" ] || return 0
  command -v gh >/dev/null 2>&1 || return 0
  out="$(gh pr view "$branch" --repo "$repo" --json number,state 2>/dev/null)" || return 0
  [ -n "$out" ] || return 0
  # `|| true`: under `set -e` a jq failure on empty or malformed input
  # would abort the whole run. A missing PR is normal, not an error.
  printf '%s' "$out" | jq -c 'select(.number != null) | {number, state}' 2>/dev/null || true
}

# issue_for <cwd> — the linked ticket, from the registry first.
issue_for() {
  local cwd="$1" reg="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/bsg-sessions.json"
  [ -f "$reg" ] || return 0
  # `|| true`: bsg-sessions.json is external data written by a later lot.
  # A malformed registry must not abort the whole run.
  jq -r --arg k "$cwd" '.[$k].issue // empty' "$reg" 2>/dev/null || true
}

# transcript_dir <cwd> — the Claude projects directory for a worktree.
#
# Claude Code encodes a project path into a directory name. The strict
# encoding below (`/`, `.`, `+` → `-`) was verified against 60+ real
# project directories, but Claude Code's own encoder replaces other
# non-alphanumerics too and no local path exercises `_` or a space. A
# silent divergence would make `busy` always false and keep:busy never
# fire — the unsafe direction, since an actively working session could
# then be reaped. So: try strict, fall back to a permissive encoding
# that maps every non-alphanumeric to `-`, and use whichever directory
# actually exists.
transcript_dir() {
  local cwd="$1" cfg strict loose
  cfg="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
  strict="$(printf '%s' "$cwd" | tr '/.+' '---')"
  if [ -d "$cfg/projects/$strict" ]; then
    printf '%s\n' "$cfg/projects/$strict"
    return 0
  fi
  loose="$(printf '%s' "$cwd" | sed 's/[^A-Za-z0-9]/-/g')"
  if [ -d "$cfg/projects/$loose" ]; then
    printf '%s\n' "$cfg/projects/$loose"
    return 0
  fi
  return 0
}

# is_busy <cwd> — true when the transcript changed within the age floor.
is_busy() {
  local cwd="$1" dir newest now mtime
  dir="$(transcript_dir "$cwd")"
  [ -n "$dir" ] || { echo false; return; }
  # `|| true`: an unmatched glob makes `ls` exit non-zero even though
  # "no transcript yet" is a normal, expected state, not an error.
  newest="$(ls -t "$dir"/*.jsonl 2>/dev/null | head -1 || true)"
  [ -n "$newest" ] || { echo false; return; }
  now="$(date +%s)"
  # `|| true`: a TOCTOU race (file removed between ls and stat) must not abort.
  #
  # GNU form FIRST, then BSD: `stat -c %Y` is rejected outright by BSD
  # stat, so macOS still falls through to the second branch correctly.
  # The reverse order is the actual portability trap and must never come
  # back: `stat -f %m` cannot be used as a "does this fail on Linux?"
  # probe, because it does not fail. On GNU coreutils `-f` means
  # `--file-system` and takes NO argument, so `%m` is parsed as a FILE
  # operand — `stat` reports the filesystem of $newest, exits 0, and
  # prints a multi-line block whose first line starts with `  File: `.
  # mtime then holds that text and poisons the arithmetic below.
  mtime="$(stat -c %Y "$newest" 2>/dev/null || stat -f %m "$newest" 2>/dev/null || true)"
  # Trust neither form's success: validate mtime is a bare run of digits
  # before using it in arithmetic. Order alone is not a fix — it just
  # moves the same landmine to whatever platform runs the fallback branch.
  case "$mtime" in
    ''|*[!0-9]*) echo false; return ;;
  esac
  if [ $((now - mtime)) -lt "$MIN_AGE_SECONDS" ]; then echo true; else echo false; fi
}

# listening_pids — every pid holding a LISTENing TCP socket, space-padded,
# resolved once per run and cached. One `lsof` for the machine instead of
# one per candidate process keeps the sweep inside its time budget
# (PRD-009 §13: under 15 s for 35 sessions).
_LISTEN_PIDS=""
_LISTEN_LOADED=""
listening_pids() {
  local out
  if [ -z "$_LISTEN_LOADED" ]; then
    _LISTEN_LOADED=1
    out=""
    if command -v lsof >/dev/null 2>&1; then
      out="$(lsof -nP -iTCP -sTCP:LISTEN 2>/dev/null | awk 'NR > 1 { print $2 }' | sort -u)" || out=""
    fi
    _LISTEN_PIDS=" $(printf '%s' "$out" | tr '\n' ' ') "
  fi
  printf '%s' "$_LISTEN_PIDS"
}

# dev_servers <pid> <cwd> — descendants of the session, rooted in the
# worktree, that are LISTENING ON A TCP PORT (PRD-009 §5.4.6).
#
# "Any child process with that cwd" is not a dev server: every Claude
# session spawns MCP stdio helpers under its worktree (`npm exec
# @upstash/context7-mcp`, `npm exec @playwright/mcp`), which made 27 of
# 31 live sessions keep:dev-servers and drove `reapable` to zero — the
# git rungs below it became dead code and the printed reason was false.
# Listening on a port is what the founding case actually was: three Vite
# servers on 5173-5175. MCP stdio helpers do not listen.
#
# Guarded end to end: a failure anywhere yields "no dev servers found"
# for that one session rather than aborting the batch.
dev_servers() {
  local pid="$1" cwd="$2" child ccwd ps_out
  if [ -n "${BSG_SESSION_DEV_SERVER_CMD:-}" ]; then
    # `|| true` then `return 0`: a failing injected command must not
    # propagate its exit status and abort the whole run.
    "$BSG_SESSION_DEV_SERVER_CMD" "$pid" "$cwd" || true
    return 0
  fi
  command -v lsof >/dev/null 2>&1 || return 0
  ps_out="$(ps -Ao pid=,ppid= 2>/dev/null)" || ps_out=""
  [ -n "$ps_out" ] || return 0
  for child in $(printf '%s\n' "$ps_out" | descendants_from_ps "$pid"); do
    # Cheap test first: most descendants listen on nothing, so this skips
    # the per-process `lsof` for the cwd in the overwhelmingly common case.
    case "$(listening_pids)" in
      *" $child "*) : ;;
      *) continue ;;
    esac
    ccwd="$(lsof -a -p "$child" -d cwd -Fn 2>/dev/null | sed -n 's/^n//p' | head -1)" || ccwd=""
    if path_within "$ccwd" "$cwd"; then printf '%s\n' "$child"; fi
  done
  return 0
}

# is_self <pid> — the caller's own session, or its parent (PRD-009 §5.4.8).
is_self() {
  local pid="$1"
  [ "$pid" = "$SELF_PID" ] && return 0
  if [ -n "${SELF_PPID:-}" ] && [ "$pid" = "$SELF_PPID" ]; then return 0; fi
  return 1
}

verdict_for() {
  local pid="$1" age="$2" dirty="$3" unpushed="$4" merged="$5" \
        is_repo="$6" busy="$7" servers="$8" pr_state="$9"
  if is_self "$pid";                    then echo "keep:self";        return; fi
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
        pr pr_state issue busy servers servers_json verdict

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
    pr="$(pr_json "$repo" "$branch")"
    # `pr` lands in --argjson, where malformed JSON is a jq *invocation*
    # error the filter cannot catch and the whole row would be lost.
    if [ -n "$pr" ] && ! printf '%s' "$pr" | jq -e . >/dev/null 2>&1; then pr=""; fi
    pr_state="$(printf '%s' "$pr" | jq -r '.state // empty' 2>/dev/null)" || pr_state=""
    issue="$(issue_for "$cwd")" || issue=""
    busy="$(is_busy "$cwd")"
    servers="$(dev_servers "$pid" "$cwd" | tr '\n' ' ')" || servers=""
    # `tonumber? // empty`, not `tonumber`: a non-numeric token from an
    # injected dev-server command must drop that token, not the row.
    servers_json="$(printf '%s' "$servers" | tr ' ' '\n' \
      | jq -Rn '[inputs | select(length > 0) | (tonumber? // empty)]' 2>/dev/null)" \
      || servers_json="[]"
    [ -n "$servers_json" ] || servers_json="[]"
    verdict="$(verdict_for "$pid" "$age" "$dirty" "$unpushed" "$merged" \
               "$is_repo" "$busy" "$servers" "$pr_state")"
    # Everything numeric crosses as --arg (a string) and is converted
    # inside the filter with `tonumber? // <default>`. --argjson parses
    # eagerly, and a parse failure kills jq before the program runs —
    # which under `set -e` in this subshell loses EVERY REMAINING ROW.
    # One registry entry reading "PROJ-42" used to empty the scorecard,
    # and references/doctor.md redirects stdout to a file, so the user
    # saw a blank table rather than an error. Degrade one field on one
    # row; never lose a row, never lose the batch.
    if ! jq -nc \
      --arg pid "$pid" \
      --arg ppid "$ppid" \
      --arg cwd "$cwd" \
      --arg rss_mb "$rss" \
      --arg age_seconds "$age" \
      --arg repo "$repo" \
      --arg branch "$branch" \
      --arg upstream "$upstream" \
      --arg dirty "$dirty" \
      --arg unpushed "$unpushed" \
      --arg merged_into_base "$merged" \
      --argjson pr "${pr:-null}" \
      --arg issue "$issue" \
      --arg busy "$busy" \
      --argjson dev_servers "$servers_json" \
      --arg verdict "$verdict" \
      '{pid: (($pid | tonumber?) // 0),
        ppid: (($ppid | tonumber?) // 0),
        cwd: $cwd,
        rss_mb: (($rss_mb | tonumber?) // 0),
        age_seconds: (($age_seconds | tonumber?) // 0),
        repo: (if $repo == "" then null else $repo end),
        branch: (if $branch == "" then null else $branch end),
        upstream: (if $upstream == "" then null else $upstream end),
        dirty: (($dirty | tonumber?) // 0),
        unpushed: (($unpushed | tonumber?) // 0),
        merged_into_base: ($merged_into_base == "true"),
        pr: $pr,
        issue: (if $issue == "" then null else (($issue | tonumber?) // null) end),
        busy: ($busy == "true"),
        dev_servers: $dev_servers,
        verdict: $verdict}' 2>/dev/null
    then
      # Last resort: a row the emitter could not build is still a live
      # session, and a missing row is exactly the silence PRD-009 §5.4
      # calls a bug. Emit it rather than drop it.
      jq -nc --arg pid "$pid" --arg cwd "$cwd" --arg verdict "$verdict" \
        '{pid: (($pid | tonumber?) // 0), ppid: 0, cwd: $cwd, rss_mb: 0,
          age_seconds: 0, repo: null, branch: null, upstream: null,
          dirty: 0, unpushed: 0, merged_into_base: false, pr: null,
          issue: null, busy: false, dev_servers: [],
          verdict: (if $verdict == "" then "unknown" else $verdict end)}' \
        2>/dev/null || true
    fi
  done
}

# Run only when executed. Sourcing this file defines the helpers without
# emitting anything, so the pure functions above can be unit-tested directly.
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  main "$@"
fi
