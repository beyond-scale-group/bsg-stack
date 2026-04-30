#!/usr/bin/env bash
# test_read_intent_file.sh — unit tests for read-intent-file.sh.
#
# Verifies:
#   1. Script exists and is executable.
#   2. Returns file content when the file exists in the current directory.
#   3. Exits 0 with empty output when the file is absent (no error).
#   4. Returns file content when given an explicit path override via
#      INTENT_FILE_BASEDIR env var (allows testing without chdir).
#
# Run locally:
#   bash claude-skills/tests/test_read_intent_file.sh
#
# Exit 0 = all pass, exit 1 = any failure.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SUT="$REPO_ROOT/claude-skills/scripts/read-intent-file.sh"

TMPDIR_TEST="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_TEST"' EXIT

PASS=0
FAIL=0

assert_eq() {
  local label="$1" actual="$2" expected="$3"
  if [ "$actual" = "$expected" ]; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    echo "FAIL: $label"
    echo "  expected: $(printf '%q' "$expected")"
    echo "  actual:   $(printf '%q' "$actual")"
  fi
}

assert_exit() {
  local label="$1" code="$2" expected="$3"
  if [ "$code" = "$expected" ]; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    echo "FAIL: $label — exit $code (expected $expected)"
  fi
}

# ── test 1: script exists ─────────────────────────────────────────────────────
if [ -f "$SUT" ]; then
  PASS=$((PASS + 1))
else
  FAIL=$((FAIL + 1))
  echo "FAIL: script exists — $SUT not found"
fi

# ── test 2: script is executable ─────────────────────────────────────────────
if [ -x "$SUT" ]; then
  PASS=$((PASS + 1))
else
  FAIL=$((FAIL + 1))
  echo "FAIL: script is executable — $SUT not executable"
fi

# ── test 3: present file is returned ─────────────────────────────────────────
echo "# Test ROADMAP" > "$TMPDIR_TEST/ROADMAP.md"
output=$(INTENT_FILE_BASEDIR="$TMPDIR_TEST" bash "$SUT" ROADMAP.md 2>&1)
exit_code=$?
assert_exit "present file — exit 0" "$exit_code" "0"
assert_eq   "present file — content" "$output" "# Test ROADMAP"

# ── test 4: absent file → exit 0, empty output ───────────────────────────────
output=$(INTENT_FILE_BASEDIR="$TMPDIR_TEST" bash "$SUT" ARCHITECTURE.md 2>&1)
exit_code=$?
assert_exit "absent file — exit 0" "$exit_code" "0"
assert_eq   "absent file — empty output" "$output" ""

# ── test 5: missing argument → exit 1 ────────────────────────────────────────
set +e
bash "$SUT" 2>/dev/null
exit_code=$?
set -e
assert_exit "missing arg — exit 1" "$exit_code" "1"

# ── summary ──────────────────────────────────────────────────────────────────
echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
