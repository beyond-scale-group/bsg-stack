#!/usr/bin/env bash
# test_bus_handler.sh — unit tests for bus-handler.sh per-agent claim processing.
#
# Verifies that bus-handler.sh:
#   1. Identifies issues in the needs:<agent> inbox
#   2. Posts a structured marker comment acknowledging the claim
#   3. Returns the list of inbox issue numbers it processed
#   4. Returns empty output for an empty inbox (no-op)
#
# Run locally:
#   bash claude-skills/tests/test_bus_handler.sh
#
# Exit 0 = all pass, exit 1 = failure.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SUT="$REPO_ROOT/claude-skills/scripts/bus-handler.sh"

# Fail fast if the script doesn't exist yet (this is the failing test commit).
if [[ ! -f "$SUT" ]]; then
  echo "FAIL: bus-handler.sh not found at $SUT"
  echo "=== 1 tests: 0 passed, 1 failed ==="
  exit 1
fi

TMPDIR_TEST="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_TEST"' EXIT

PASS=0
FAIL=0

assert_eq() {
  local label="$1" got="$2" want="$3"
  if [[ "$got" == "$want" ]]; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    echo "FAIL: $label"
    echo "  got : $got"
    echo "  want: $want"
  fi
}

assert_contains() {
  local label="$1" haystack="$2" needle="$3"
  if echo "$haystack" | grep -qF "$needle"; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    echo "FAIL: $label"
    echo "  expected to contain: $needle"
    echo "  got: $haystack"
  fi
}

# ── Mock gh ───────────────────────────────────────────────────────────────────
MOCK_GH="$TMPDIR_TEST/gh"
GH_CALLS_FILE="$TMPDIR_TEST/gh_calls"
GH_RESPONSE_FILE="$TMPDIR_TEST/gh_response"
cat > "$MOCK_GH" <<'MOCK'
#!/usr/bin/env bash
echo "$*" >> "$GH_CALLS_FILE"
cat "$GH_RESPONSE_FILE" 2>/dev/null || echo "[]"
MOCK
chmod +x "$MOCK_GH"
export GH_CALLS_FILE GH_RESPONSE_FILE
export PATH="$TMPDIR_TEST:$PATH"

# ── Test 1: acknowledge-only — bus-handler.sh posts a marker comment ─────────
echo "--- Test 1: handler posts acknowledge marker for inbox item ---"
> "$GH_CALLS_FILE"
cat > "$GH_RESPONSE_FILE" <<'JSON'
[{"number":42,"labels":[{"name":"needs:tech"},{"name":"enhancement"},{"name":"tech"}],"title":"Test inbox item","body":""}]
JSON

bash "$SUT" --agent tech --action acknowledge 2>/dev/null || true
CALLS="$(cat "$GH_CALLS_FILE")"
assert_contains "T1: issue comment called" "$CALLS" "issue comment 42"

# ── Test 2: handler prints processed issue numbers ───────────────────────────
echo "--- Test 2: handler returns processed issue numbers ---"
> "$GH_CALLS_FILE"
cat > "$GH_RESPONSE_FILE" <<'JSON'
[{"number":99,"labels":[{"name":"needs:tech"}],"title":"Another item","body":""}]
JSON

RESULT=$(bash "$SUT" --agent tech --action acknowledge 2>/dev/null)
assert_eq "T2: processed number emitted" "$RESULT" "99"

# ── Test 3: empty inbox — no-op ───────────────────────────────────────────────
echo "--- Test 3: empty inbox returns empty output ---"
> "$GH_CALLS_FILE"
echo "[]" > "$GH_RESPONSE_FILE"

RESULT=$(bash "$SUT" --agent tech --action acknowledge 2>/dev/null)
assert_eq "T3: empty inbox is silent" "$RESULT" ""

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo "=== $((PASS + FAIL)) tests: $PASS passed, $FAIL failed ==="
[[ "$FAIL" -eq 0 ]]
