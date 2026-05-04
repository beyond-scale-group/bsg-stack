#!/usr/bin/env bash
# test_email_from_md.sh — unit tests for email-from-md.sh
#
# Tests:
#   - Table CSS inlining: <table> gets border-collapse styles
#   - <th> and <td> get border + padding styles
#   - <blockquote> gets left-border styles
#   - --no-signature flag skips signature fetch
#   - --markdown flag required (exits 1 without it)
#   - Output is valid HTML (contains <html> or table tags)
#
# Run locally:
#   bash claude-skills/tests/test_email_from_md.sh
#
# Exit 0 = all pass, exit 1 = failure.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SUT="$REPO_ROOT/claude-skills/skills/google-workspace/scripts/email-from-md.sh"

# Skip gracefully if pandoc is not available
if ! command -v pandoc &>/dev/null; then
  echo "SKIP: pandoc not available — skipping test_email_from_md.sh"
  exit 0
fi

TMPDIR_TEST="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_TEST"' EXIT

PASS=0
FAIL=0

assert_contains() {
  local label="$1" needle="$2" haystack="$3"
  if echo "$haystack" | grep -qF "$needle"; then
    echo "PASS: $label"
    PASS=$((PASS + 1))
  else
    echo "FAIL: $label — expected to find: $needle"
    FAIL=$((FAIL + 1))
  fi
}

assert_exit() {
  local label="$1" expected="$2"
  shift 2
  local actual=0
  "$@" &>/dev/null || actual=$?
  if [[ "$actual" -eq "$expected" ]]; then
    echo "PASS: $label"
    PASS=$((PASS + 1))
  else
    echo "FAIL: $label — expected exit $expected, got $actual"
    FAIL=$((FAIL + 1))
  fi
}

# ---- fixture markdown file ----
FIXTURE_MD="$TMPDIR_TEST/input.md"
cat > "$FIXTURE_MD" <<'MD'
# Hello

| Col A | Col B | Col C |
|-------|-------|-------|
| 1     | 2     | 3     |

> A blockquote here.

Some body text.
MD

# ---- Test 1: script exists ----
echo "--- Test 1: script exists ---"
if [[ -f "$SUT" ]]; then
  echo "PASS: script exists"
  PASS=$((PASS + 1))
else
  echo "FAIL: $SUT not found"
  FAIL=$((FAIL + 1))
fi

# ---- Test 2: --no-signature flag produces HTML output ----
echo "--- Test 2: --no-signature produces HTML ---"
OUTPUT=$(bash "$SUT" --markdown "$FIXTURE_MD" --no-signature 2>/dev/null)
assert_contains "T2: output contains <table" "<table" "$OUTPUT"

# ---- Test 3: table gets border-collapse CSS ----
echo "--- Test 3: table gets border-collapse style ---"
assert_contains "T3: border-collapse:collapse" "border-collapse:collapse" "$OUTPUT"

# ---- Test 4: <th> gets background style ----
echo "--- Test 4: <th> gets background style ---"
assert_contains "T4: th has background:#f4f4f4" "background:#f4f4f4" "$OUTPUT"

# ---- Test 5: <td> gets border style ----
echo "--- Test 5: <td> gets border style ---"
assert_contains "T5: td has border:1px solid" "border:1px solid" "$OUTPUT"

# ---- Test 6: blockquote gets border-left style ----
echo "--- Test 6: blockquote gets border-left style ---"
assert_contains "T6: blockquote has border-left" "border-left" "$OUTPUT"

# ---- Test 7: missing --markdown exits non-zero ----
echo "--- Test 7: missing --markdown exits 1 ---"
assert_exit "T7: no --markdown → exit 1" 1 bash "$SUT" --no-signature

# ---- Test 8: --markdown with nonexistent file exits non-zero ----
echo "--- Test 8: nonexistent file exits 1 ---"
assert_exit "T8: bad path → exit 1" 1 bash "$SUT" --markdown "/tmp/does-not-exist-$$.md" --no-signature

# ---------- Summary ----------
echo ""
echo "=== $((PASS + FAIL)) tests: $PASS passed, $FAIL failed ==="
[[ "$FAIL" -eq 0 ]]
