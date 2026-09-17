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

rm -rf "$WORK"

echo "test_session_state.sh: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]

