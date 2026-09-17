#!/usr/bin/env bash
# test_session_state.sh — unit tests for session-state.sh.
#
# Process enumeration is injected via BSG_SESSION_PROVIDER so almost no
# test inspects or signals a real Claude session. The exception is §20,
# the LIVE-PATH test, which runs the resolver with NOTHING stubbed —
# every serious defect found in the final review of this lot lived in
# code reachable only when nothing is injected, and the suite never went
# there. It is still read-only: it emits a scorecard and signals nothing.
#
# Run locally:
#   bash claude-skills/tests/test_session_state.sh
#
# Exit 0 = all pass, exit 1 = failure.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SUT="$REPO_ROOT/claude-skills/scripts/session-state.sh"

PASS=0
FAIL=0

assert_eq() {
  local label="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    echo "FAIL: $label"
    echo "  expected: $expected"
    echo "  actual:   $actual"
  fi
}

# line_count <text> — number of lines, 0 for the empty string.
#
# `printf '%s\n' "$x" | wc -l` returns 1 for empty $x, so every
# "a row was emitted" assertion written that way passed even when
# nothing at all was emitted. That is how a broken unborn-HEAD path
# shipped green.
line_count() {
  if [ -z "$1" ]; then printf '0\n'; else printf '%s\n' "$1" | wc -l | tr -d ' '; fi
}

# Self-test of the harness itself: an assertion helper that cannot fail
# is worse than no assertion.
assert_eq "line_count of empty is 0" "0" "$(line_count "")"
assert_eq "line_count of one line is 1" "1" "$(line_count "a")"
assert_eq "line_count of two lines is 2" "2" "$(line_count "$(printf 'a\nb')")"

# make_provider <file> <lines...> — write a fake enumerator.
make_provider() {
  local path="$1"; shift
  {
    echo '#!/usr/bin/env bash'
    local line
    for line in "$@"; do
      printf 'printf "%%s\\n" %q\n' "$line"
    done
  } > "$path"
  chmod +x "$path"
}

# `pwd -P`: on macOS $TMPDIR lives under /var, which is a symlink to
# /private/var. `lsof` always reports the physical path, so a fixture
# root spelled the symlinked way would never match a child's cwd and the
# real dev-server tests below would silently find nothing.
WORK="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/session-state-test.XXXXXX")" && pwd -P)"
FIXTURE_PIDS=""

cleanup() {
  local p
  # Only pids this test itself spawned as fixtures, captured from `$!`.
  # The lot under test signals nothing; this is the harness tidying up
  # after its own listeners.
  for p in $FIXTURE_PIDS; do kill "$p" 2>/dev/null || true; done
  rm -rf "$WORK"
}
trap cleanup EXIT

# 1. One plain session round-trips its fields.
prov="$WORK/p1.sh"
make_provider "$prov" "4242	1	$WORK/none	142	60000"
out="$(BSG_SESSION_PROVIDER="$prov" BSG_SESSION_SELF_PID=999 bash "$SUT")"
assert_eq "one row emitted" "1" "$(line_count "$out")"
assert_eq "pid parsed"      "4242" "$(printf '%s' "$out" | jq -r '.pid')"
assert_eq "rss parsed"      "142"  "$(printf '%s' "$out" | jq -r '.rss_mb')"
assert_eq "age parsed"      "60000" "$(printf '%s' "$out" | jq -r '.age_seconds')"

# 2. The calling session is excluded by verdict, not by omission.
prov="$WORK/p2.sh"
make_provider "$prov" "555	1	$WORK/none	100	60000"
out="$(BSG_SESSION_PROVIDER="$prov" BSG_SESSION_SELF_PID=555 bash "$SUT")"
assert_eq "self is kept" "keep:self" "$(printf '%s' "$out" | jq -r '.verdict')"

# 2b. PRD-009 §5.4.8 excludes the caller AND its parent. A row whose pid
# is the caller's parent is keep:self too, and an unrelated pid is not.
prov="$WORK/p2b.sh"
make_provider "$prov" \
  "555	1	$WORK/none	100	60000" \
  "556	1	$WORK/other	100	60000" \
  "557	1	$WORK/third	100	60000"
out="$(BSG_SESSION_PROVIDER="$prov" BSG_SESSION_SELF_PID=557 \
  BSG_SESSION_SELF_PPID=555 bash "$SUT")"
assert_eq "caller's parent is keep:self" "keep:self" \
  "$(printf '%s\n' "$out" | jq -r 'select(.pid == 555) | .verdict')"
assert_eq "caller itself is keep:self" "keep:self" \
  "$(printf '%s\n' "$out" | jq -r 'select(.pid == 557) | .verdict')"
assert_eq "an unrelated pid is not keep:self" "unknown" \
  "$(printf '%s\n' "$out" | jq -r 'select(.pid == 556) | .verdict')"
assert_eq "exactly two keep:self rows" "2" \
  "$(line_count "$(printf '%s\n' "$out" | jq -r 'select(.verdict == "keep:self") | .pid')")"

# 3. A wrapper/child pair sharing a cwd collapses to the child.
prov="$WORK/p3.sh"
make_provider "$prov" \
  "700	1	$WORK/shared	0	5000" \
  "701	700	$WORK/shared	208	5000"
out="$(BSG_SESSION_PROVIDER="$prov" BSG_SESSION_SELF_PID=999 bash "$SUT")"
assert_eq "wrapper collapsed" "1" "$(line_count "$out")"
assert_eq "child survives"    "701" "$(printf '%s' "$out" | jq -r '.pid')"

# 4. A session younger than the age floor is kept.
prov="$WORK/p4.sh"
make_provider "$prov" "800	1	$WORK/none	100	120"
out="$(BSG_SESSION_PROVIDER="$prov" BSG_SESSION_SELF_PID=999 bash "$SUT")"
assert_eq "too young" "keep:too-young" "$(printf '%s' "$out" | jq -r '.verdict')"

# 4b. etime parsing. macOS ps has no `etimes` keyword, so the default
# enumerator reads POSIX `etime` ([[dd-]hh:]mm:ss) and converts it. Sourcing
# the script defines the helpers without running main.
source "$SUT"
assert_eq "etime mm:ss"       "0"      "$(etime_to_seconds '00:00')"
assert_eq "etime mm:ss again" "330"    "$(etime_to_seconds '05:30')"
assert_eq "etime hh:mm:ss"    "5025"   "$(etime_to_seconds '01:23:45')"
assert_eq "etime dd-hh:mm:ss" "183845" "$(etime_to_seconds '2-03:04:05')"
assert_eq "etime leading zeros not octal" "489" "$(etime_to_seconds '08:09')"

# 4c. claude_pids_from_ps: pure pid extraction from `ps -Ao pid=,command=`
# shaped lines, replacing pgrep entirely (macOS pgrep hides the calling
# session and all its ancestors by default — see the helper's own comment).
assert_eq "bare claude line matches" "42" \
  "$(printf '   42 claude --dangerously-skip-permissions\n' | claude_pids_from_ps)"
assert_eq "absolute-path claude line matches" "43" \
  "$(printf '   43 /Users/x/.local/bin/claude --resume abc123\n' | claude_pids_from_ps)"
assert_eq "dotfile .claude/ path does not match" "" \
  "$(printf '   44 bash /Users/x/.claude/scripts/session-state.sh\n' | claude_pids_from_ps)"
assert_eq "prefix false positive faithfully preserved from old pgrep pattern" "45" \
  "$(printf '   45 claude-mock-server --port 1234\n' | claude_pids_from_ps)"
assert_eq "mixed batch returns exact pid list" "$(printf '42\n43\n45')" \
  "$(printf '   42 claude --dangerously-skip-permissions\n   43 /Users/x/.local/bin/claude --resume abc123\n   44 bash /Users/x/.claude/scripts/session-state.sh\n   45 claude-mock-server --port 1234\n' | claude_pids_from_ps)"

# 4d. resolve_self_pid: walks the process tree to the nearest `claude`
# ancestor, so keep:self can't silently point at a wrapper shell instead of
# the actual session. Each case redefines _cmd_of/_ppid_of inside a
# $(...) command substitution, which is its own subshell — the stubs never
# leak into later tests.

# a. A Claude session sits two hops up the chain: 100 -> 200 (claude) -> 300 -> 1.
assert_eq "resolve_self_pid finds a claude ancestor" "200" "$(
  _cmd_of()  { case "$1" in
                 100) echo "bash foo.sh" ;;
                 200) echo "claude --dangerously-skip-permissions" ;;
                 300) echo "-zsh" ;;
               esac; }
  _ppid_of() { case "$1" in
                 100) echo 200 ;;
                 200) echo 300 ;;
                 300) echo 1 ;;
               esac; }
  resolve_self_pid 100
)"

# b. No Claude ancestor anywhere in the chain: falls back to the start pid,
# never to empty and never to the init pid the walk terminated on.
assert_eq "resolve_self_pid falls back to start pid, not empty or 1" "400" "$(
  _cmd_of()  { case "$1" in
                 400) echo "bash foo.sh" ;;
                 401) echo "-zsh" ;;
               esac; }
  _ppid_of() { case "$1" in
                 400) echo 401 ;;
                 401) echo 1 ;;
               esac; }
  resolve_self_pid 400
)"

# c. A cycle (ppid always points back to the same pid) must terminate via
# the 12-hop cap rather than spin, and still fall back to the start pid.
assert_eq "resolve_self_pid terminates on a cycle via the hop cap" "500" "$(
  _cmd_of()  { echo "bash loop.sh"; }
  _ppid_of() { echo 500; }
  resolve_self_pid 500
)"

# d. An absolute-path session command matches; a non-session command that
# merely contains the literal word "claude" in a dotfile path does not.
assert_eq "absolute-path claude command matches" "600" "$(
  _cmd_of()  { case "$1" in
                 600) echo "/Users/x/.local/bin/claude --resume abc123" ;;
               esac; }
  _ppid_of() { echo 1; }
  resolve_self_pid 600
)"
assert_eq "dotfile .claude/ path is not mistaken for a session" "700" "$(
  _cmd_of()  { case "$1" in
                 700) echo "bash /Users/x/.claude/scripts/session-state.sh" ;;
               esac; }
  _ppid_of() { echo 1; }
  resolve_self_pid 700
)"

# 4e. path_within: literal, boundary-aware containment. `grep -q "^$cwd"`
# was a regex match with no path boundary — `.` was a wildcard and
# /a/repo matched /a/repo-old. Both directions inflate dev_servers, and
# an inflated dev_servers silences every rung of the ladder below it.
path_within_says() { if path_within "$1" "$2"; then echo yes; else echo no; fi; }
assert_eq "path_within: identical paths"   "yes" "$(path_within_says /a/repo /a/repo)"
assert_eq "path_within: child path"        "yes" "$(path_within_says /a/repo/src /a/repo)"
assert_eq "path_within: sibling prefix"    "no"  "$(path_within_says /a/repo-old /a/repo)"
assert_eq "path_within: dot is not a wildcard" "no" \
  "$(path_within_says /a/bXrepo /a/b.repo)"
assert_eq "path_within: dotted path still contains itself" "yes" \
  "$(path_within_says /a/b.repo/src /a/b.repo)"
assert_eq "path_within: unrelated path"    "no"  "$(path_within_says /b/other /a/repo)"
assert_eq "path_within: empty path"        "no"  "$(path_within_says "" /a/repo)"
assert_eq "path_within: empty root"        "no"  "$(path_within_says /a/repo "")"
assert_eq "path_within: trailing slash on root" "yes" \
  "$(path_within_says /a/repo/src /a/repo/)"
assert_eq "path_within: parent is not within child" "no" \
  "$(path_within_says /a /a/repo)"

# 4f. descendants_from_ps: full-depth descendant walk from one `ps` read.
# A dev server is usually a grandchild (`npm run dev` -> node), so a
# one-level walk misses the founding case.
ps_fixture="$(printf '%s\n' \
  '  10    1' \
  '  20   10' \
  '  30   20' \
  '  40   30' \
  '  50    1' \
  '  60   50')"
assert_eq "descendants_from_ps walks to full depth" "$(printf '20\n30\n40')" \
  "$(printf '%s\n' "$ps_fixture" | descendants_from_ps 10)"
assert_eq "descendants_from_ps excludes the root itself" "" \
  "$(printf '%s\n' "$ps_fixture" | descendants_from_ps 40)"
assert_eq "descendants_from_ps keeps unrelated trees out" "$(printf '60')" \
  "$(printf '%s\n' "$ps_fixture" | descendants_from_ps 50)"
assert_eq "descendants_from_ps on an unknown pid is empty" "" \
  "$(printf '%s\n' "$ps_fixture" | descendants_from_ps 999)"

# make_repo <path> <state> — build a fixture repo in a known state.
make_repo() {
  local path="$1" state="$2"
  mkdir -p "$path"
  git -C "$path" init -q -b main
  git -C "$path" config user.email t@t.t
  git -C "$path" config user.name t
  git -C "$path" remote add origin https://github.com/acme/widget.git
  echo base > "$path/f.txt"
  git -C "$path" add f.txt
  git -C "$path" commit -qm base
  git -C "$path" update-ref refs/remotes/origin/main HEAD
  git -C "$path" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main
  case "$state" in
    clean) : ;;
    dirty) echo changed > "$path/f.txt" ;;
    unpushed)
      git -C "$path" checkout -qb feature
      echo more > "$path/g.txt"
      git -C "$path" add g.txt
      git -C "$path" commit -qm "local only"
      ;;
    # A branch whose upstream CONFIG survives but whose tracking ref does
    # not — the ordinary state after a squash-merge deletes the remote
    # branch, you `fetch --prune`, then commit again.
    orphan-upstream)
      git -C "$path" checkout -qb feature
      git -C "$path" config branch.feature.remote origin
      git -C "$path" config branch.feature.merge refs/heads/feature
      echo more > "$path/g.txt"
      git -C "$path" add g.txt
      git -C "$path" commit -qm "exists nowhere else"
      ;;
    # No upstream, no commits the base lacks — PRD-009 §5.4.2 as corrected.
    no-upstream-merged)
      git -C "$path" checkout -qb feature
      ;;
  esac
}

# 5. A clean repo whose HEAD is in origin/main is reapable.
make_repo "$WORK/clean" clean
prov="$WORK/p5.sh"
make_provider "$prov" "900	1	$WORK/clean	100	60000"
out="$(BSG_SESSION_PROVIDER="$prov" BSG_SESSION_SELF_PID=999 bash "$SUT")"
assert_eq "repo parsed"    "acme/widget" "$(printf '%s' "$out" | jq -r '.repo')"
assert_eq "clean is 0"     "0"    "$(printf '%s' "$out" | jq -r '.dirty')"
assert_eq "merged is true" "true" "$(printf '%s' "$out" | jq -r '.merged_into_base')"
assert_eq "clean+merged reapable" "reapable" "$(printf '%s' "$out" | jq -r '.verdict')"

# 5b. PRD-009 §5.4.2 as corrected: "no upstream" is NOT by itself a
# keep. A branch with no upstream whose HEAD the base already contains
# holds nothing that exists nowhere else, so it is reapable. The earlier
# draft clause ("a branch with no upstream is never reapable, whatever
# its commit count") would have kept all nine sessions the §1 audit
# actually reaped. Test 7 is the other half of the same clause.
make_repo "$WORK/nomergedup" no-upstream-merged
prov="$WORK/p5b.sh"
make_provider "$prov" "910	1	$WORK/nomergedup	100	60000"
out="$(BSG_SESSION_PROVIDER="$prov" BSG_SESSION_SELF_PID=999 bash "$SUT")"
assert_eq "no-upstream branch reports null upstream" "null" \
  "$(printf '%s' "$out" | jq -r '.upstream')"
assert_eq "no-upstream branch ahead of base by 0" "0" \
  "$(printf '%s' "$out" | jq -r '.unpushed')"
assert_eq "no upstream is not itself a keep" "reapable" \
  "$(printf '%s' "$out" | jq -r '.verdict')"

# 6. A dirty tree is kept — the build+socle-v0 case from PRD-009 §1.
make_repo "$WORK/dirty" dirty
prov="$WORK/p6.sh"
make_provider "$prov" "901	1	$WORK/dirty	100	60000"
out="$(BSG_SESSION_PROVIDER="$prov" BSG_SESSION_SELF_PID=999 bash "$SUT")"
assert_eq "dirty counted" "1" "$(printf '%s' "$out" | jq -r '.dirty')"
assert_eq "dirty is kept"  "keep:dirty" "$(printf '%s' "$out" | jq -r '.verdict')"

# 6b. REGRESSION: a repo with real uncommitted AND untracked changes
# whose `.git/index` cannot be read (replaced by a directory, the
# reviewer's reproduction — index.lock and a broken core.fsmonitor do
# NOT trigger it, only an unreadable index does) must still be kept.
# `git status --porcelain` fails in this state; the capture-on-success
# pattern used everywhere else in git_field would map that failure to
# `dirty:0` and this worktree — holding real work — would be classified
# reapable, and a later lot would SIGTERM it. dirty must fail CLOSED.
make_repo "$WORK/dirty-unreadable" dirty
echo untracked > "$WORK/dirty-unreadable/u.txt"
rm -f "$WORK/dirty-unreadable/.git/index"
mkdir "$WORK/dirty-unreadable/.git/index"
prov="$WORK/p6b.sh"
make_provider "$prov" "903	1	$WORK/dirty-unreadable	100	60000"
out="$(BSG_SESSION_PROVIDER="$prov" BSG_SESSION_SELF_PID=999 bash "$SUT")"
assert_eq "unreadable git status: dirty is non-zero" "yes" \
  "$(printf '%s' "$out" | jq -r 'if (.dirty // 0) > 0 then "yes" else "no" end')"
assert_eq "unreadable git status: kept, not reaped" "keep:dirty" \
  "$(printf '%s' "$out" | jq -r '.verdict')"

# 7. Commits with no upstream are kept — the clear-harbor-6a62 case.
make_repo "$WORK/unpushed" unpushed
prov="$WORK/p7.sh"
make_provider "$prov" "902	1	$WORK/unpushed	100	60000"
out="$(BSG_SESSION_PROVIDER="$prov" BSG_SESSION_SELF_PID=999 bash "$SUT")"
assert_eq "no upstream"  "null" "$(printf '%s' "$out" | jq -r '.upstream')"
assert_eq "unpushed > 0" "1"    "$(printf '%s' "$out" | jq -r '.unpushed')"
assert_eq "unpushed kept" "keep:unpushed" "$(printf '%s' "$out" | jq -r '.verdict')"

# 7b. THE CRITICAL REGRESSION. `git rev-parse --abbrev-ref '@{u}'` prints
# the literal string "@{u}" to STDOUT while exiting 128 when the branch
# has branch.X.remote/merge configured but the tracking ref no longer
# exists. `$(git … || echo "")` never fires — the placeholder is already
# on stdout — so `upstream` became the string "@{u}", the follow-up
# `rev-list --count '@{u}..HEAD'` failed, unpushed fell back to 0, and a
# session holding a commit that exists nowhere else came out `reapable`.
# Two of 31 live sessions were in exactly this state.
make_repo "$WORK/orphanup" orphan-upstream
prov="$WORK/p7b.sh"
make_provider "$prov" "903	1	$WORK/orphanup	100	60000"
out="$(BSG_SESSION_PROVIDER="$prov" BSG_SESSION_SELF_PID=999 bash "$SUT")"
assert_eq "dead tracking ref does not leak the literal @{u}" "null" \
  "$(printf '%s' "$out" | jq -r '.upstream')"
assert_eq "dead tracking ref still counts the commit" "1" \
  "$(printf '%s' "$out" | jq -r '.unpushed')"
assert_eq "dead tracking ref is NOT reapable" "keep:unpushed" \
  "$(printf '%s' "$out" | jq -r '.verdict')"

# 8. A cwd that is not a git repo yields nulls, never a crash.
mkdir -p "$WORK/plain"
prov="$WORK/p8.sh"
make_provider "$prov" "904	1	$WORK/plain	100	60000"
out="$(BSG_SESSION_PROVIDER="$prov" BSG_SESSION_SELF_PID=999 bash "$SUT")"
assert_eq "non-repo has null repo" "null" "$(printf '%s' "$out" | jq -r '.repo')"
assert_eq "non-repo is unknown" "unknown" "$(printf '%s' "$out" | jq -r '.verdict')"

# 9. A repo with no origin remote still emits a row, repo field is null.
mkdir -p "$WORK/no-origin"
git -C "$WORK/no-origin" init -q -b main
git -C "$WORK/no-origin" config user.email t@t.t
git -C "$WORK/no-origin" config user.name t
echo base > "$WORK/no-origin/f.txt"
git -C "$WORK/no-origin" add f.txt
git -C "$WORK/no-origin" commit -qm base
prov="$WORK/p9.sh"
make_provider "$prov" "905	1	$WORK/no-origin	100	60000"
rc=0
out="$(BSG_SESSION_PROVIDER="$prov" BSG_SESSION_SELF_PID=999 bash "$SUT")" || rc=$?
assert_eq "no-origin script exits 0" "0" "$rc"
assert_eq "no-origin repo is null" "null" "$(printf '%s' "$out" | jq -r '.repo')"
assert_eq "no-origin row emitted" "1" "$(line_count "$out")"

# 10. A fresh git init with no commits (unborn HEAD) still emits a row.
#
# `rev-parse --abbrev-ref HEAD` prints "HEAD" and exits 128 here — the
# same STDOUT-plus-failure shape as @{u} above — so `branch` must come
# out null, not the string "HEAD".
#
# The exit-status assertion used to read `"$?"` AFTER an assert_eq call,
# which is always 0, and the row-count assertion used `wc -l` on a
# possibly-empty string, which is always >= 1. Both passed against a
# completely broken unborn-HEAD path.
mkdir -p "$WORK/unborn"
git -C "$WORK/unborn" init -q -b main
git -C "$WORK/unborn" config user.email t@t.t
git -C "$WORK/unborn" config user.name t
git -C "$WORK/unborn" remote add origin https://github.com/acme/widget.git
prov="$WORK/p10.sh"
make_provider "$prov" "906	1	$WORK/unborn	100	60000"
rc=0
out="$(BSG_SESSION_PROVIDER="$prov" BSG_SESSION_SELF_PID=999 bash "$SUT")" || rc=$?
assert_eq "unborn script exits 0" "0" "$rc"
assert_eq "unborn row emitted" "1" "$(line_count "$out")"
assert_eq "unborn branch is null, not the string HEAD" "null" \
  "$(printf '%s' "$out" | jq -r '.branch')"
assert_eq "unborn upstream is null" "null" "$(printf '%s' "$out" | jq -r '.upstream')"
assert_eq "unborn unpushed is 0" "0" "$(printf '%s' "$out" | jq -r '.unpushed')"
assert_eq "unborn is not reapable" "unknown" "$(printf '%s' "$out" | jq -r '.verdict')"

# 11. Batch of two sessions where first is broken repo, second is normal clean repo.
# This is the critical regression test: if first session kills the script, second never
# emits and the verdict is lost. The batch must emit both rows.
make_repo "$WORK/clean2" clean
prov="$WORK/p11.sh"
{
  echo '#!/usr/bin/env bash'
  printf 'printf "%%s\\n" %q\n' "907	1	$WORK/no-origin	100	60000"
  printf 'printf "%%s\\n" %q\n' "908	1	$WORK/clean2	100	60000"
} > "$prov"
chmod +x "$prov"
out="$(BSG_SESSION_PROVIDER="$prov" BSG_SESSION_SELF_PID=999 bash "$SUT")"
assert_eq "batch emits both rows" "2" "$(line_count "$out")"
assert_eq "batch: second row is reapable" "reapable" \
  "$(printf '%s\n' "$out" | tail -1 | jq -r '.verdict')"

# stub_gh <dir> <json> [argv-log] — a fake `gh` on PATH returning fixed
# JSON and, when given a log path, appending every argv it was called
# with. The old stub ignored both cwd and argv, which is exactly why the
# suite never noticed that `gh pr view` was resolving the repository from
# the JANITOR's working directory instead of the session's.
stub_gh() {
  local dir="$1" json="$2" log="${3:-}"
  mkdir -p "$dir"
  {
    echo '#!/usr/bin/env bash'
    if [ -n "$log" ]; then
      printf 'printf "%%s\\n" "$*" >> %q\n' "$log"
    fi
    printf 'printf "%%s" %q\n' "$json"
  } > "$dir/gh"
  chmod +x "$dir/gh"
}

# gh_arg_after <log> <flag> — the value the stub saw after <flag>.
gh_arg_after() {
  awk -v flag="$2" '{ for (i = 1; i <= NF; i++) if ($i == flag) print $(i + 1) }' "$1" \
    | head -1
}

# 12. An open PR outranks a clean, merged tree — AND the lookup is made
# against the SESSION's repository, not the janitor's.
make_repo "$WORK/propen" clean
gh_log="$WORK/gh_open.log"
stub_gh "$WORK/bin_open" '{"number":2816,"state":"OPEN"}' "$gh_log"
prov="$WORK/p12.sh"
make_provider "$prov" "909	1	$WORK/propen	100	60000"
out="$(PATH="$WORK/bin_open:$PATH" BSG_SESSION_PROVIDER="$prov" \
  BSG_SESSION_SELF_PID=999 bash "$SUT")"
assert_eq "pr number" "2816" "$(printf '%s' "$out" | jq -r '.pr.number')"
assert_eq "open pr kept" "keep:pr-open" "$(printf '%s' "$out" | jq -r '.verdict')"
assert_eq "gh was actually invoked" "1" "$(line_count "$(cat "$gh_log")")"
assert_eq "gh queried the session's repository" "acme/widget" \
  "$(gh_arg_after "$gh_log" --repo)"
assert_eq "gh queried the session's branch" "main" \
  "$(awk 'NR == 1 { print $3 }' "$gh_log")"
# The janitor is being run from inside bsg-stack; the fixture's repo is
# acme/widget. Passing no --repo would have resolved the former.
janitor_repo="$(git -C "$REPO_ROOT" remote get-url origin 2>/dev/null \
  | sed -E 's#\.git$##; s#^git@[^:]+:##; s#^[a-z]+://[^/]+/##')" || janitor_repo=""
if [ -n "$janitor_repo" ]; then
  if [ "$(gh_arg_after "$gh_log" --repo)" = "$janitor_repo" ]; then
    assert_eq "gh did NOT query the janitor's own repository" "different" "same"
  else
    assert_eq "gh did NOT query the janitor's own repository" "different" "different"
  fi
fi

# 12b. With no resolvable repository there is nothing to query, so gh is
# not called at all rather than called against whatever repo the janitor
# happens to be standing in.
gh_log_noorigin="$WORK/gh_noorigin.log"
stub_gh "$WORK/bin_noorigin" '{"number":1,"state":"MERGED"}' "$gh_log_noorigin"
prov="$WORK/p12b.sh"
make_provider "$prov" "911	1	$WORK/no-origin	100	60000"
out="$(PATH="$WORK/bin_noorigin:$PATH" BSG_SESSION_PROVIDER="$prov" \
  BSG_SESSION_SELF_PID=999 bash "$SUT")"
assert_eq "no repo means no gh call" "0" \
  "$(line_count "$(cat "$gh_log_noorigin" 2>/dev/null || true)")"
assert_eq "no repo means null pr" "null" "$(printf '%s' "$out" | jq -r '.pr')"

# 13. A merged PR on a clean tree is reapable.
make_repo "$WORK/prmerged" clean
stub_gh "$WORK/bin_merged" '{"number":8,"state":"MERGED"}'
prov="$WORK/p13.sh"
make_provider "$prov" "912	1	$WORK/prmerged	100	60000"
out="$(PATH="$WORK/bin_merged:$PATH" BSG_SESSION_PROVIDER="$prov" \
  BSG_SESSION_SELF_PID=999 bash "$SUT")"
assert_eq "merged pr reapable" "reapable" "$(printf '%s' "$out" | jq -r '.verdict')"

# 14. An injected dev-server command outranks a clean tree.
make_repo "$WORK/servers" clean
stub_gh "$WORK/bin_none" ''
prov="$WORK/p14.sh"
make_provider "$prov" "913	1	$WORK/servers	100	60000"
servers_stub="$WORK/servers_stub.sh"
printf '#!/usr/bin/env bash\necho 4306\n' > "$servers_stub"
chmod +x "$servers_stub"
out="$(PATH="$WORK/bin_none:$PATH" BSG_SESSION_PROVIDER="$prov" \
  BSG_SESSION_DEV_SERVER_CMD="$servers_stub" BSG_SESSION_SELF_PID=999 bash "$SUT")"
assert_eq "dev server listed" "4306" "$(printf '%s' "$out" | jq -r '.dev_servers[0]')"
assert_eq "dev servers kept" "keep:dev-servers" "$(printf '%s' "$out" | jq -r '.verdict')"

# 14b. A dev-server command that fails, or prints junk, degrades that one
# field on that one row. It must not abort the batch.
servers_junk="$WORK/servers_junk.sh"
printf '#!/usr/bin/env bash\necho "not-a-pid"\necho 4307\nexit 3\n' > "$servers_junk"
chmod +x "$servers_junk"
prov="$WORK/p14b.sh"
{
  echo '#!/usr/bin/env bash'
  printf 'printf "%%s\\n" %q\n' "914	1	$WORK/servers	100	60000"
  printf 'printf "%%s\\n" %q\n' "915	1	$WORK/clean2	100	60000"
} > "$prov"
chmod +x "$prov"
out="$(PATH="$WORK/bin_none:$PATH" BSG_SESSION_PROVIDER="$prov" \
  BSG_SESSION_DEV_SERVER_CMD="$servers_junk" BSG_SESSION_SELF_PID=999 bash "$SUT")"
assert_eq "junk dev-server output keeps the batch" "2" "$(line_count "$out")"
assert_eq "junk dev-server token dropped, numeric one kept" "[4307]" \
  "$(printf '%s\n' "$out" | head -1 | jq -c '.dev_servers')"

# 15. A transcript touched just now marks the session busy (strict encoding).
make_repo "$WORK/busy" clean
fake_cfg="$WORK/cfg"
enc="$(printf '%s' "$WORK/busy" | tr '/.+' '---')"
mkdir -p "$fake_cfg/projects/$enc"
touch "$fake_cfg/projects/$enc/session.jsonl"
prov="$WORK/p15.sh"
make_provider "$prov" "916	1	$WORK/busy	100	60000"
out="$(PATH="$WORK/bin_none:$PATH" CLAUDE_CONFIG_DIR="$fake_cfg" \
  BSG_SESSION_PROVIDER="$prov" BSG_SESSION_SELF_PID=999 bash "$SUT")"
assert_eq "busy detected (strict encoding)" "true" "$(printf '%s' "$out" | jq -r '.busy')"
assert_eq "busy kept" "keep:busy" "$(printf '%s' "$out" | jq -r '.verdict')"

# 15b. The permissive fallback. The strict encoder only replaces `/`, `.`
# and `+`; Claude Code's own encoder replaces other non-alphanumerics
# too, and no local path exercises `_` or a space. A silent divergence
# would make `busy` always false and keep:busy never fire — the unsafe
# direction, since an actively working session could then be reaped.
# Here ONLY the permissively-encoded directory exists.
busy_loose_dir="$WORK/busy loose_dir"
make_repo "$busy_loose_dir" clean
loose_enc="$(printf '%s' "$busy_loose_dir" | sed 's/[^A-Za-z0-9]/-/g')"
strict_enc="$(printf '%s' "$busy_loose_dir" | tr '/.+' '---')"
assert_eq "fixture path really distinguishes the two encoders" "different" \
  "$(if [ "$loose_enc" = "$strict_enc" ]; then echo same; else echo different; fi)"
mkdir -p "$fake_cfg/projects/$loose_enc"
touch "$fake_cfg/projects/$loose_enc/session.jsonl"
prov="$WORK/p15b.sh"
make_provider "$prov" "917	1	$busy_loose_dir	100	60000"
out="$(PATH="$WORK/bin_none:$PATH" CLAUDE_CONFIG_DIR="$fake_cfg" \
  BSG_SESSION_PROVIDER="$prov" BSG_SESSION_SELF_PID=999 bash "$SUT")"
assert_eq "busy detected via permissive fallback" "true" \
  "$(printf '%s' "$out" | jq -r '.busy')"
assert_eq "permissive-fallback busy kept" "keep:busy" \
  "$(printf '%s' "$out" | jq -r '.verdict')"

# 15c. Strict wins when both directories exist, and a stale transcript is
# not busy — so the fallback cannot turn every session busy by accident.
stale_dir="$WORK/stale"
make_repo "$stale_dir" clean
stale_enc="$(printf '%s' "$stale_dir" | tr '/.+' '---')"
mkdir -p "$fake_cfg/projects/$stale_enc"
touch -t 202001010000 "$fake_cfg/projects/$stale_enc/session.jsonl"
prov="$WORK/p15c.sh"
make_provider "$prov" "918	1	$stale_dir	100	60000"
out="$(PATH="$WORK/bin_none:$PATH" CLAUDE_CONFIG_DIR="$fake_cfg" \
  BSG_SESSION_PROVIDER="$prov" BSG_SESSION_SELF_PID=999 bash "$SUT")"
assert_eq "stale transcript is not busy" "false" "$(printf '%s' "$out" | jq -r '.busy')"

# 15d. REGRESSION: `is_busy` must not be poisonable by a non-numeric
# mtime. The real defect (line 318, pre-fix) was `stat -f %m` succeeding
# on GNU coreutils — `-f` there means `--file-system`, takes no argument,
# so `%m` is parsed as a FILE operand and `stat` prints a multi-line
# "  File: ..." filesystem block and exits 0. `mtime` then held that text
# and `$((now - mtime))` died with `set -u`'s "unbound variable", killing
# the WHOLE run, not just this row.
#
# Both stat forms behave differently per platform, so this stub ignores
# its arguments entirely and always emits the GNU-filesystem-block shape,
# reproducing the poison identically on macOS or Linux, whichever runs
# this suite.
make_repo "$WORK/busybadstat" clean
make_repo "$WORK/afterbadstat" clean
badstat_enc="$(printf '%s' "$WORK/busybadstat" | tr '/.+' '---')"
mkdir -p "$fake_cfg/projects/$badstat_enc"
touch "$fake_cfg/projects/$badstat_enc/session.jsonl"
bin_badstat="$WORK/bin_badstat"
mkdir -p "$bin_badstat"
{
  echo '#!/usr/bin/env bash'
  echo 'printf "  File: \"/some/mount/point\"\n"'
  echo 'printf "  ID: deadbeef Namelen: 255     Type: apfs\n"'
  echo 'exit 0'
} > "$bin_badstat/stat"
chmod +x "$bin_badstat/stat"
prov="$WORK/p15d.sh"
{
  echo '#!/usr/bin/env bash'
  printf 'printf "%%s\\n" %q\n' "924	1	$WORK/busybadstat	100	60000"
  printf 'printf "%%s\\n" %q\n' "925	1	$WORK/afterbadstat	100	60000"
} > "$prov"
chmod +x "$prov"
rc15d=0
out="$(PATH="$bin_badstat:$WORK/bin_none:$PATH" CLAUDE_CONFIG_DIR="$fake_cfg" \
  BSG_SESSION_PROVIDER="$prov" BSG_SESSION_SELF_PID=999 bash "$SUT")" || rc15d=$?
assert_eq "poisoned stat: run does not abort" "0" "$rc15d"
assert_eq "poisoned stat: both rows still emit" "2" "$(line_count "$out")"
assert_eq "poisoned stat: busy is false, not poisoned into a crash" "false" \
  "$(printf '%s\n' "$out" | head -1 | jq -r '.busy')"
assert_eq "poisoned stat: the row after it still gets a real verdict" "reapable" \
  "$(printf '%s\n' "$out" | tail -1 | jq -r '.verdict')"

# 16. Batch of two sessions where the first session's `gh pr view` call
# fails outright (non-zero exit, no JSON). Under `set -e` a call-site
# command substitution around a failing `gh` is the exact hazard Task 3
# already hit twice with git — one bad session must not truncate the
# batch and lose the session after it.
make_repo "$WORK/ghfail" clean
make_repo "$WORK/clean3" clean
bin_fail="$WORK/bin_fail"
mkdir -p "$bin_fail"
{
  echo '#!/usr/bin/env bash'
  echo 'exit 1'
} > "$bin_fail/gh"
chmod +x "$bin_fail/gh"
prov="$WORK/p16.sh"
{
  echo '#!/usr/bin/env bash'
  printf 'printf "%%s\\n" %q\n' "919	1	$WORK/ghfail	100	60000"
  printf 'printf "%%s\\n" %q\n' "920	1	$WORK/clean3	100	60000"
} > "$prov"
chmod +x "$prov"
out="$(PATH="$bin_fail:$PATH" BSG_SESSION_PROVIDER="$prov" \
  BSG_SESSION_SELF_PID=999 bash "$SUT")"
assert_eq "gh-failure batch emits both rows" "2" "$(line_count "$out")"
assert_eq "gh-failure batch: second row is reapable" "reapable" \
  "$(printf '%s\n' "$out" | tail -1 | jq -r '.verdict')"

# 16b. A `gh` that returns garbage instead of JSON must not take the row
# or the batch with it.
bin_garbage="$WORK/bin_garbage"
stub_gh "$bin_garbage" 'not json at all {'
out="$(PATH="$bin_garbage:$PATH" BSG_SESSION_PROVIDER="$prov" \
  BSG_SESSION_SELF_PID=999 bash "$SUT")"
assert_eq "gh-garbage batch emits both rows" "2" "$(line_count "$out")"
assert_eq "gh-garbage yields null pr" "null" \
  "$(printf '%s\n' "$out" | head -1 | jq -r '.pr')"

# 17. THE REGISTRY IS UNTRUSTED INPUT. bsg-sessions.json is external data
# written by a later lot. A non-numeric issue (`"PROJ-42"`) used to make
# `jq -nc --argjson … ($issue | tonumber)` exit 5; under `set -e` inside
# the emitting `while` subshell that killed the run and ZERO rows were
# emitted. references/doctor.md redirects stdout to a file, so the user
# saw an empty scorecard rather than an error. Degrade the one field on
# the one row; never lose a row, never lose the batch.
reg_cfg="$WORK/regcfg"
mkdir -p "$reg_cfg"
make_repo "$WORK/reg1" clean
make_repo "$WORK/reg2" clean
make_repo "$WORK/reg3" clean
jq -n --arg a "$WORK/reg1" --arg b "$WORK/reg2" \
  '{($a): {issue: "PROJ-42"}, ($b): {issue: 4242}}' > "$reg_cfg/bsg-sessions.json"
prov="$WORK/p17.sh"
{
  echo '#!/usr/bin/env bash'
  printf 'printf "%%s\\n" %q\n' "921	1	$WORK/reg1	100	60000"
  printf 'printf "%%s\\n" %q\n' "922	1	$WORK/reg2	100	60000"
  printf 'printf "%%s\\n" %q\n' "923	1	$WORK/reg3	100	60000"
} > "$prov"
chmod +x "$prov"
out="$(PATH="$WORK/bin_none:$PATH" CLAUDE_CONFIG_DIR="$reg_cfg" \
  BSG_SESSION_PROVIDER="$prov" BSG_SESSION_SELF_PID=999 bash "$SUT")"
assert_eq "non-numeric registry issue keeps every row" "3" "$(line_count "$out")"
assert_eq "non-numeric issue degrades to null" "null" \
  "$(printf '%s\n' "$out" | jq -r 'select(.pid == 921) | .issue')"
assert_eq "numeric issue on the NEXT row still resolves" "4242" \
  "$(printf '%s\n' "$out" | jq -r 'select(.pid == 922) | .issue')"
assert_eq "unregistered row still resolves to null" "null" \
  "$(printf '%s\n' "$out" | jq -r 'select(.pid == 923) | .issue')"
assert_eq "row after the poisoned one still gets a verdict" "reapable" \
  "$(printf '%s\n' "$out" | jq -r 'select(.pid == 923) | .verdict')"

# 17b. A registry that is not JSON at all, and one whose value is not an
# object, are both survivable.
printf '%s' '{ this is not json' > "$reg_cfg/bsg-sessions.json"
out="$(PATH="$WORK/bin_none:$PATH" CLAUDE_CONFIG_DIR="$reg_cfg" \
  BSG_SESSION_PROVIDER="$prov" BSG_SESSION_SELF_PID=999 bash "$SUT")"
assert_eq "malformed registry keeps every row" "3" "$(line_count "$out")"
jq -n --arg a "$WORK/reg1" '{($a): "a bare string"}' > "$reg_cfg/bsg-sessions.json"
out="$(PATH="$WORK/bin_none:$PATH" CLAUDE_CONFIG_DIR="$reg_cfg" \
  BSG_SESSION_PROVIDER="$prov" BSG_SESSION_SELF_PID=999 bash "$SUT")"
assert_eq "non-object registry entry keeps every row" "3" "$(line_count "$out")"

# 18. dev_servers over REAL processes, nothing injected. PRD-009 §5.4.6:
# a dev server is a descendant rooted in the worktree that is LISTENING
# ON A TCP PORT. Treating any child with that cwd as a dev server made 27
# of 31 live sessions keep:dev-servers and drove `reapable` to zero — the
# git rungs below became dead code and the printed reason was false.
if command -v python3 >/dev/null 2>&1 && command -v lsof >/dev/null 2>&1; then
  srv_root="$WORK/srvroot"
  mkdir -p "$srv_root" "$WORK/srvroot-old"
  listener="$WORK/listener.py"
  cat > "$listener" <<'PY'
import socket, time
s = socket.socket()
s.bind(('127.0.0.1', 0))
s.listen(1)
time.sleep(45)
PY
  # A listener rooted in the worktree: a real dev server.
  ( cd "$srv_root" && exec python3 "$listener" ) &
  srv_pid=$!
  FIXTURE_PIDS="$FIXTURE_PIDS $srv_pid"
  # A listener rooted in a SIBLING whose name merely shares the prefix:
  # `grep -q "^$cwd"` counted this one.
  ( cd "$WORK/srvroot-old" && exec python3 "$listener" ) &
  sibling_pid=$!
  FIXTURE_PIDS="$FIXTURE_PIDS $sibling_pid"
  # A non-listening child rooted in the worktree: an MCP stdio helper.
  ( cd "$srv_root" && exec sleep 45 ) &
  quiet_pid=$!
  FIXTURE_PIDS="$FIXTURE_PIDS $quiet_pid"

  # Wait for both listeners to bind, up to ~10s.
  waited=0
  while [ "$waited" -lt 100 ]; do
    if lsof -nP -iTCP -sTCP:LISTEN -a -p "$srv_pid" >/dev/null 2>&1 \
       && lsof -nP -iTCP -sTCP:LISTEN -a -p "$sibling_pid" >/dev/null 2>&1; then
      break
    fi
    sleep 0.1
    waited=$((waited + 1))
  done
  _LISTEN_LOADED=""; _LISTEN_PIDS=""
  found="$(dev_servers "$$" "$srv_root" | sort)"
  assert_eq "real dev server: the listener in the worktree is found" "$srv_pid" "$found"
  assert_eq "real dev server: a non-listening child is NOT a dev server" "" \
    "$(printf '%s\n' "$found" | grep -Fx "$quiet_pid" || true)"
  assert_eq "real dev server: a prefix-sibling worktree is NOT included" "" \
    "$(printf '%s\n' "$found" | grep -Fx "$sibling_pid" || true)"
  _LISTEN_LOADED=""; _LISTEN_PIDS=""
  assert_eq "real dev server: the sibling worktree finds its own listener" \
    "$sibling_pid" "$(dev_servers "$$" "$WORK/srvroot-old" | sort)"
  _LISTEN_LOADED=""; _LISTEN_PIDS=""
  assert_eq "real dev server: an unrelated root finds nothing" "" \
    "$(dev_servers "$$" "$WORK/plain")"
  kill "$srv_pid" "$sibling_pid" "$quiet_pid" 2>/dev/null || true
  wait "$srv_pid" "$sibling_pid" "$quiet_pid" 2>/dev/null || true
  FIXTURE_PIDS=""
else
  echo "note: python3 or lsof missing — real dev-server tests skipped"
fi

# 19. The verdict vocabulary stays closed, and is exactly the nine values
# PRD-009 §5.3 names. A tenth value appearing here is a contract break
# for every consumer.
vocab_in_code="$(grep -oE 'echo "(reapable|keep:[a-z-]+|unknown)"' "$SUT" \
  | sed -E 's/echo "(.*)"/\1/' | sort -u | tr '\n' ' ')"
assert_eq "verdict vocabulary is the nine documented values" \
  "keep:busy keep:dev-servers keep:dirty keep:pr-open keep:self keep:too-young keep:unpushed reapable unknown " \
  "$vocab_in_code"

# 20. LIVE PATH — nothing stubbed. No BSG_SESSION_PROVIDER, no
# BSG_SESSION_SELF_PID, no gh stub, no CLAUDE_CONFIG_DIR override. This
# is the only test that exercises default_provider, the real pr_json and
# the real dev_servers together, and every serious defect in this lot
# lived in code reachable only from here.
#
# Assertions are invariants, not counts, so the test does not depend on
# how many sessions happen to be running.
live_rc=0
live_out="$(bash "$SUT")" || live_rc=$?
assert_eq "live: exits 0" "0" "$live_rc"
live_rows="$(line_count "$live_out")"

if [ "$live_rows" -eq 0 ]; then
  echo "note: live run found no Claude sessions — per-row invariants skipped"
else
  bad_json=0
  while IFS= read -r line; do
    printf '%s' "$line" | jq -e . >/dev/null 2>&1 || bad_json=$((bad_json + 1))
  done <<< "$live_out"
  assert_eq "live: every line is valid JSON" "0" "$bad_json"

  assert_eq "live: every row carries all 16 fields" "0" \
    "$(printf '%s\n' "$live_out" | jq -s '[.[] | select((keys | length) != 16)] | length')"

  vocab=" reapable keep:dirty keep:unpushed keep:pr-open keep:busy keep:dev-servers keep:too-young keep:self unknown "
  bad_verdict=0
  while IFS= read -r v; do
    case "$vocab" in *" $v "*) : ;; *) bad_verdict=$((bad_verdict + 1)) ;; esac
  done < <(printf '%s\n' "$live_out" | jq -r '.verdict')
  assert_eq "live: every verdict is in the closed vocabulary" "0" "$bad_verdict"

  assert_eq "live: no row leaks the literal @{u} as an upstream" "0" \
    "$(printf '%s\n' "$live_out" | jq -s '[.[] | select(.upstream == "@{u}")] | length')"
  assert_eq "live: no row reports the string HEAD as a branch on an unborn repo" "0" \
    "$(printf '%s\n' "$live_out" | jq -s '[.[] | select(.branch == "HEAD" and .unpushed == 0 and .upstream == "@{u}")] | length')"
  assert_eq "live: every pid is a positive integer" "0" \
    "$(printf '%s\n' "$live_out" | jq -s '[.[] | select((.pid | type) != "number" or .pid <= 0)] | length')"
  assert_eq "live: dev_servers is always an array of numbers" "0" \
    "$(printf '%s\n' "$live_out" | jq -s '[.[] | select((.dev_servers | type) != "array" or any(.dev_servers[]; type != "number"))] | length')"
  assert_eq "live: every cwd still exists" "0" \
    "$(live_bad=0
       while IFS= read -r d; do [ -d "$d" ] || live_bad=$((live_bad + 1)); done \
         < <(printf '%s\n' "$live_out" | jq -r '.cwd')
       printf '%s' "$live_bad")"
  assert_eq "live: a keep:dev-servers row always names at least one server" "0" \
    "$(printf '%s\n' "$live_out" | jq -s '[.[] | select(.verdict == "keep:dev-servers" and (.dev_servers | length) == 0)] | length')"

  # keep:self. Meaningful only when the suite really is running inside a
  # Claude session; in CI it is not, and the assertion becomes "no row
  # was mislabelled as the caller".
  live_self="$(resolve_self_pid)"
  live_self_cmd="$(ps -o command= -p "$live_self" 2>/dev/null || true)"
  self_rows="$(line_count "$(printf '%s\n' "$live_out" \
    | jq -r 'select(.verdict == "keep:self") | .pid')")"
  case "$live_self_cmd" in
    claude|claude\ *|*/claude|*/claude\ *)
      assert_eq "live: exactly one keep:self" "1" "$self_rows"
      assert_eq "live: keep:self names the resolved session" "$live_self" \
        "$(printf '%s\n' "$live_out" | jq -r 'select(.verdict == "keep:self") | .pid')"
      ;;
    *)
      echo "note: not running inside a Claude session — keep:self identity assertion relaxed"
      assert_eq "live: no session mislabelled keep:self" "0" "$self_rows"
      ;;
  esac
fi

echo "test_session_state.sh: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
