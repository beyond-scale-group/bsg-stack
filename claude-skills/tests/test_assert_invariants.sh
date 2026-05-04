#!/usr/bin/env bash
# test_assert_invariants.sh — unit tests for assert-invariants.sh I5-I8 (#292)
#
# Exercises the four invariants added in the #292 completion pass:
#   I5 issue dedup (no two open issues share a filed-by fingerprint)
#   I6 phase-B reactivity (eligible issues get a PR within 5 min of creation)
#   I7 token budget (total tokens ≤ baseline × 1.2)
#   I8 auto-merge labels (every auto-merged PR carries human-reviewed)
#
# Usage: bash claude-skills/tests/test_assert_invariants.sh
# Exit 0 = all assertions passed; exit 1 = at least one failed.

set -euo pipefail

SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../scripts/test/assert-invariants.sh"; pwd)/$(basename claude-skills/scripts/test/assert-invariants.sh)"
# Resolve relative to repo root
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.."; pwd)"
SCRIPT="$REPO_ROOT/claude-skills/scripts/test/assert-invariants.sh"

PASS=0
FAIL=0

ok()   { echo "  PASS  $1"; PASS=$((PASS+1)); }
fail() { echo "  FAIL  $1"; FAIL=$((FAIL+1)); }

run_assert() {   # $1=label  args…
  local label="$1"; shift
  bash "$SCRIPT" "$@" 2>&1
}

# ---- helpers ----------------------------------------------------------------

make_logs() {
  local dir
  dir=$(mktemp -d)
  echo "$dir"
}

write_prs() {   # dir json
  echo "$2" > "$1/prs.json"
}

write_issues() {  # dir json
  echo "$2" > "$1/issues.json"
}

write_baselines() {  # dir json
  mkdir -p "$1"
  echo "$2" > "$1/latest.json"
}

# ---- I5 — issue dedup -------------------------------------------------------

test_i5_pass() {
  local d; d=$(make_logs)
  write_prs "$d" "[]"
  # Two issues with different fingerprints
  write_issues "$d" '[
    {"number":1,"body":"fingerprint: tech:stale-todo:foo.py:10","labels":[{"name":"filed-by:tech"}],"state":"OPEN"},
    {"number":2,"body":"fingerprint: tech:stale-todo:bar.py:20","labels":[{"name":"filed-by:tech"}],"state":"OPEN"}
  ]'
  local out; out=$(bash "$SCRIPT" --logs "$d" 2>&1) || true
  if echo "$out" | grep -q "I5.*✓"; then
    ok "I5 pass: distinct fingerprints"
  else
    fail "I5 pass: distinct fingerprints — got: $out"
  fi
  rm -rf "$d"
}

test_i5_fail() {
  local d; d=$(make_logs)
  write_prs "$d" "[]"
  # Two issues sharing the same fingerprint = dedup violation
  write_issues "$d" '[
    {"number":1,"body":"fingerprint: tech:stale-todo:foo.py:10","labels":[{"name":"filed-by:tech"}],"state":"OPEN"},
    {"number":2,"body":"fingerprint: tech:stale-todo:foo.py:10","labels":[{"name":"filed-by:tech"}],"state":"OPEN"}
  ]'
  local out; out=$(bash "$SCRIPT" --logs "$d" 2>&1) || true
  if echo "$out" | grep -q "I5.*✗"; then
    ok "I5 fail: duplicate fingerprint detected"
  else
    fail "I5 fail: expected detection of duplicate fingerprint — got: $out"
  fi
  rm -rf "$d"
}

# ---- I6 — phase-B reactivity ------------------------------------------------

test_i6_pass() {
  local d; d=$(make_logs)
  # Issue created at T, PR opened at T+3min (within 5min SLA)
  write_issues "$d" '[
    {"number":10,"labels":[{"name":"tech"},{"name":"bug"},{"name":"safe-to-automate"}],
     "state":"OPEN","createdAt":"2026-05-04T10:00:00Z"}
  ]'
  write_prs "$d" '[
    {"number":100,"body":"Closes #10","state":"OPEN","createdAt":"2026-05-04T10:03:00Z",
     "labels":[{"name":"tech"}]}
  ]'
  local out; out=$(bash "$SCRIPT" --logs "$d" 2>&1) || true
  if echo "$out" | grep -q "I6.*✓"; then
    ok "I6 pass: PR within 5min SLA"
  else
    fail "I6 pass: expected I6 pass — got: $out"
  fi
  rm -rf "$d"
}

test_i6_fail() {
  local d; d=$(make_logs)
  # Issue created at T, PR opened at T+10min (exceeds 5min SLA)
  write_issues "$d" '[
    {"number":10,"labels":[{"name":"tech"},{"name":"bug"},{"name":"safe-to-automate"}],
     "state":"OPEN","createdAt":"2026-05-04T10:00:00Z"}
  ]'
  write_prs "$d" '[
    {"number":100,"body":"Closes #10","state":"OPEN","createdAt":"2026-05-04T10:10:00Z",
     "labels":[{"name":"tech"}]}
  ]'
  local out; out=$(bash "$SCRIPT" --logs "$d" 2>&1) || true
  if echo "$out" | grep -q "I6.*✗"; then
    ok "I6 fail: slow PR detected"
  else
    fail "I6 fail: expected I6 failure for slow PR — got: $out"
  fi
  rm -rf "$d"
}

# ---- I7 — token budget ------------------------------------------------------

test_i7_pass() {
  local d; d=$(make_logs)
  local bdir; bdir=$(mktemp -d)
  write_prs "$d" "[]"
  write_issues "$d" "[]"
  write_baselines "$bdir" '{"total_tokens":1000000}'
  # current tokens = 1.1× baseline (within 20% drift)
  local out; out=$(bash "$SCRIPT" --logs "$d" --baseline-dir "$bdir" --tokens 1100000 2>&1) || true
  if echo "$out" | grep -q "I7.*✓"; then
    ok "I7 pass: tokens within 20% drift"
  else
    fail "I7 pass: expected I7 pass — got: $out"
  fi
  rm -rf "$d" "$bdir"
}

test_i7_fail() {
  local d; d=$(make_logs)
  local bdir; bdir=$(mktemp -d)
  write_prs "$d" "[]"
  write_issues "$d" "[]"
  write_baselines "$bdir" '{"total_tokens":1000000}'
  # current tokens = 1.3× baseline (exceeds 20% drift)
  local out; out=$(bash "$SCRIPT" --logs "$d" --baseline-dir "$bdir" --tokens 1300000 2>&1) || true
  if echo "$out" | grep -q "I7.*✗"; then
    ok "I7 fail: token drift detected"
  else
    fail "I7 fail: expected I7 failure for token drift — got: $out"
  fi
  rm -rf "$d" "$bdir"
}

# ---- I8 — auto-merge labels -------------------------------------------------

test_i8_pass() {
  local d; d=$(make_logs)
  write_issues "$d" "[]"
  # Merged PR carries human-reviewed
  write_prs "$d" '[
    {"number":200,"state":"MERGED","mergedAt":"2026-05-04T11:00:00Z",
     "labels":[{"name":"human-reviewed"},{"name":"tech"}]}
  ]'
  local out; out=$(bash "$SCRIPT" --logs "$d" 2>&1) || true
  if echo "$out" | grep -q "I8.*✓"; then
    ok "I8 pass: merged PR carries human-reviewed"
  else
    fail "I8 pass: expected I8 pass — got: $out"
  fi
  rm -rf "$d"
}

test_i8_fail() {
  local d; d=$(make_logs)
  write_issues "$d" "[]"
  # Merged PR missing human-reviewed
  write_prs "$d" '[
    {"number":201,"state":"MERGED","mergedAt":"2026-05-04T11:00:00Z",
     "labels":[{"name":"tech"}]}
  ]'
  local out; out=$(bash "$SCRIPT" --logs "$d" 2>&1) || true
  if echo "$out" | grep -q "I8.*✗"; then
    ok "I8 fail: missing human-reviewed on merged PR detected"
  else
    fail "I8 fail: expected I8 failure — got: $out"
  fi
  rm -rf "$d"
}

# ---- run --------------------------------------------------------------------

echo "assert-invariants I5-I8 unit tests"
echo

test_i5_pass
test_i5_fail
test_i6_pass
test_i6_fail
test_i7_pass
test_i7_fail
test_i8_pass
test_i8_fail

echo
echo "summary: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
