#!/usr/bin/env bash
# test_session_state.sh — unit tests for session-state.sh.
#
# Process enumeration is injected via BSG_SESSION_PROVIDER so no test
# ever inspects or signals a real Claude session.
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

WORK="$(mktemp -d)"

# 1. One plain session round-trips its fields.
prov="$WORK/p1.sh"
make_provider "$prov" "4242	1	$WORK/none	142	60000"
out="$(BSG_SESSION_PROVIDER="$prov" BSG_SESSION_SELF_PID=999 bash "$SUT")"
assert_eq "one row emitted" "1" "$(printf '%s\n' "$out" | wc -l | tr -d ' ')"
assert_eq "pid parsed"      "4242" "$(printf '%s' "$out" | jq -r '.pid')"
assert_eq "rss parsed"      "142"  "$(printf '%s' "$out" | jq -r '.rss_mb')"
assert_eq "age parsed"      "60000" "$(printf '%s' "$out" | jq -r '.age_seconds')"

# 2. The calling session is excluded by verdict, not by omission.
prov="$WORK/p2.sh"
make_provider "$prov" "555	1	$WORK/none	100	60000"
out="$(BSG_SESSION_PROVIDER="$prov" BSG_SESSION_SELF_PID=555 bash "$SUT")"
assert_eq "self is kept" "keep:self" "$(printf '%s' "$out" | jq -r '.verdict')"

# 3. A wrapper/child pair sharing a cwd collapses to the child.
prov="$WORK/p3.sh"
make_provider "$prov" \
  "700	1	$WORK/shared	0	5000" \
  "701	700	$WORK/shared	208	5000"
out="$(BSG_SESSION_PROVIDER="$prov" BSG_SESSION_SELF_PID=999 bash "$SUT")"
assert_eq "wrapper collapsed" "1" "$(printf '%s\n' "$out" | wc -l | tr -d ' ')"
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

# 6. A dirty tree is kept — the build+socle-v0 case from PRD-009 §1.
make_repo "$WORK/dirty" dirty
prov="$WORK/p6.sh"
make_provider "$prov" "901	1	$WORK/dirty	100	60000"
out="$(BSG_SESSION_PROVIDER="$prov" BSG_SESSION_SELF_PID=999 bash "$SUT")"
assert_eq "dirty counted" "1" "$(printf '%s' "$out" | jq -r '.dirty')"
assert_eq "dirty is kept"  "keep:dirty" "$(printf '%s' "$out" | jq -r '.verdict')"

# 7. Commits with no upstream are kept — the clear-harbor-6a62 case.
make_repo "$WORK/unpushed" unpushed
prov="$WORK/p7.sh"
make_provider "$prov" "902	1	$WORK/unpushed	100	60000"
out="$(BSG_SESSION_PROVIDER="$prov" BSG_SESSION_SELF_PID=999 bash "$SUT")"
assert_eq "no upstream"  "null" "$(printf '%s' "$out" | jq -r '.upstream')"
assert_eq "unpushed > 0" "1"    "$(printf '%s' "$out" | jq -r '.unpushed')"
assert_eq "unpushed kept" "keep:unpushed" "$(printf '%s' "$out" | jq -r '.verdict')"

# 8. A cwd that is not a git repo yields nulls, never a crash.
mkdir -p "$WORK/plain"
prov="$WORK/p8.sh"
make_provider "$prov" "903	1	$WORK/plain	100	60000"
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
make_provider "$prov" "904	1	$WORK/no-origin	100	60000"
out="$(BSG_SESSION_PROVIDER="$prov" BSG_SESSION_SELF_PID=999 bash "$SUT")"
assert_eq "no-origin repo is null" "null" "$(printf '%s' "$out" | jq -r '.repo')"
assert_eq "no-origin exits 0" "1" "$(printf '%s\n' "$out" | wc -l | tr -d ' ')"

# 10. A fresh git init with no commits (unborn HEAD) still emits a row.
mkdir -p "$WORK/unborn"
git -C "$WORK/unborn" init -q -b main
git -C "$WORK/unborn" config user.email t@t.t
git -C "$WORK/unborn" config user.name t
git -C "$WORK/unborn" remote add origin https://github.com/acme/widget.git
prov="$WORK/p10.sh"
make_provider "$prov" "905	1	$WORK/unborn	100	60000"
out="$(BSG_SESSION_PROVIDER="$prov" BSG_SESSION_SELF_PID=999 bash "$SUT")"
assert_eq "unborn row emitted" "1" "$(printf '%s\n' "$out" | wc -l | tr -d ' ')"
assert_eq "unborn script exits 0" "0" "$?"

# 11. Batch of two sessions where first is broken repo, second is normal clean repo.
# This is the critical regression test: if first session kills the script, second never
# emits and the verdict is lost. The batch must emit both rows.
make_repo "$WORK/clean2" clean
prov="$WORK/p11.sh"
{
  echo '#!/usr/bin/env bash'
  printf 'printf "%%s\\n" %q\n' "906	1	$WORK/no-origin	100	60000"
  printf 'printf "%%s\\n" %q\n' "907	1	$WORK/clean2	100	60000"
} > "$prov"
chmod +x "$prov"
out="$(BSG_SESSION_PROVIDER="$prov" BSG_SESSION_SELF_PID=999 bash "$SUT")"
row_count="$(printf '%s\n' "$out" | wc -l | tr -d ' ')"
assert_eq "batch emits both rows" "2" "$row_count"
second_verdict="$(printf '%s\n' "$out" | tail -1 | jq -r '.verdict')"
assert_eq "batch: second row is reapable" "reapable" "$second_verdict"

# stub_gh <dir> <json> — a fake `gh` on PATH returning fixed JSON.
stub_gh() {
  local dir="$1" json="$2"
  mkdir -p "$dir"
  {
    echo '#!/usr/bin/env bash'
    printf 'printf "%%s" %q\n' "$json"
  } > "$dir/gh"
  chmod +x "$dir/gh"
}

# 9. An open PR outranks a clean, merged tree.
make_repo "$WORK/propen" clean
stub_gh "$WORK/bin_open" '{"number":2816,"state":"OPEN"}'
prov="$WORK/p9.sh"
make_provider "$prov" "904	1	$WORK/propen	100	60000"
out="$(PATH="$WORK/bin_open:$PATH" BSG_SESSION_PROVIDER="$prov" \
  BSG_SESSION_SELF_PID=999 bash "$SUT")"
assert_eq "pr number" "2816" "$(printf '%s' "$out" | jq -r '.pr.number')"
assert_eq "open pr kept" "keep:pr-open" "$(printf '%s' "$out" | jq -r '.verdict')"

# 10. A merged PR on a clean tree is reapable.
make_repo "$WORK/prmerged" clean
stub_gh "$WORK/bin_merged" '{"number":8,"state":"MERGED"}'
prov="$WORK/p10.sh"
make_provider "$prov" "905	1	$WORK/prmerged	100	60000"
out="$(PATH="$WORK/bin_merged:$PATH" BSG_SESSION_PROVIDER="$prov" \
  BSG_SESSION_SELF_PID=999 bash "$SUT")"
assert_eq "merged pr reapable" "reapable" "$(printf '%s' "$out" | jq -r '.verdict')"

# 11. A dev server running under the worktree outranks a clean tree.
make_repo "$WORK/servers" clean
stub_gh "$WORK/bin_none" ''
prov="$WORK/p11.sh"
make_provider "$prov" "906	1	$WORK/servers	100	60000"
servers_stub="$WORK/servers_stub.sh"
printf '#!/usr/bin/env bash\necho 4306\n' > "$servers_stub"
chmod +x "$servers_stub"
out="$(PATH="$WORK/bin_none:$PATH" BSG_SESSION_PROVIDER="$prov" \
  BSG_SESSION_DEV_SERVER_CMD="$servers_stub" BSG_SESSION_SELF_PID=999 bash "$SUT")"
assert_eq "dev server listed" "4306" "$(printf '%s' "$out" | jq -r '.dev_servers[0]')"
assert_eq "dev servers kept" "keep:dev-servers" "$(printf '%s' "$out" | jq -r '.verdict')"

# 12. A transcript touched just now marks the session busy.
make_repo "$WORK/busy" clean
fake_cfg="$WORK/cfg"
enc="$(printf '%s' "$WORK/busy" | tr '/.+' '---')"
mkdir -p "$fake_cfg/projects/$enc"
touch "$fake_cfg/projects/$enc/session.jsonl"
prov="$WORK/p12.sh"
make_provider "$prov" "907	1	$WORK/busy	100	60000"
out="$(PATH="$WORK/bin_none:$PATH" CLAUDE_CONFIG_DIR="$fake_cfg" \
  BSG_SESSION_PROVIDER="$prov" BSG_SESSION_SELF_PID=999 bash "$SUT")"
assert_eq "busy detected" "true" "$(printf '%s' "$out" | jq -r '.busy')"
assert_eq "busy kept" "keep:busy" "$(printf '%s' "$out" | jq -r '.verdict')"

# 13. Batch of two sessions where the first session's `gh pr view` call
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
prov="$WORK/p13.sh"
{
  echo '#!/usr/bin/env bash'
  printf 'printf "%%s\\n" %q\n' "908	1	$WORK/ghfail	100	60000"
  printf 'printf "%%s\\n" %q\n' "909	1	$WORK/clean3	100	60000"
} > "$prov"
chmod +x "$prov"
out="$(PATH="$bin_fail:$PATH" BSG_SESSION_PROVIDER="$prov" \
  BSG_SESSION_SELF_PID=999 bash "$SUT")"
row_count="$(printf '%s\n' "$out" | wc -l | tr -d ' ')"
assert_eq "gh-failure batch emits both rows" "2" "$row_count"
second_verdict="$(printf '%s\n' "$out" | tail -1 | jq -r '.verdict')"
assert_eq "gh-failure batch: second row is reapable" "reapable" "$second_verdict"

rm -rf "$WORK"

echo "test_session_state.sh: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]

