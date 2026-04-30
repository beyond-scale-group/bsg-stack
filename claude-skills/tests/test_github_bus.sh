#!/usr/bin/env bash
# test_github_bus.sh — unit tests for bus_claim label filtering in github-bus.sh.
#
# Mocks `gh` to verify that bus_claim includes unlocked issues and
# excludes issues carrying an agent:lock:* label. No network calls.
#
# Run locally:
#   bash claude-skills/tests/test_github_bus.sh
#
# Exit 0 = all pass, exit 1 = failure.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SUT="$REPO_ROOT/claude-skills/scripts/github-bus.sh"

TMPDIR_TEST="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_TEST"' EXIT

PASS=0
FAIL=0

# Normalise to compact JSON before comparing so pretty-print vs compact is irrelevant.
assert_json_eq() {
  local label="$1" got want
  got="$(echo "$2" | jq -c '.')"
  want="$(echo "$3" | jq -c '.')"
  if [[ "$got" == "$want" ]]; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    echo "FAIL: $label"
    echo "  got : $got"
    echo "  want: $want"
  fi
}

# ── Mock gh ──────────────────────────────────────────────────────────────────
MOCK_GH="$TMPDIR_TEST/gh"
GH_RESPONSE_FILE="$TMPDIR_TEST/gh_response"
cat > "$MOCK_GH" <<'MOCK'
#!/usr/bin/env bash
cat "$GH_RESPONSE_FILE"
MOCK
chmod +x "$MOCK_GH"
export GH_RESPONSE_FILE
export PATH="$TMPDIR_TEST:$PATH"

# ── Test 1 (positive): unlocked issue → bus_claim returns its number ─────────
echo "--- Test 1: unlocked issue is claimed ---"
cat > "$GH_RESPONSE_FILE" <<'JSON'
[{"number":42,"labels":[{"name":"needs:tech"}]}]
JSON

RESULT=$(bash -c "source \"$SUT\"; bus_claim tech" 2>/dev/null)
assert_json_eq "T1: number present" "$RESULT" "[42]"

# ── Test 2 (negative): locked issue → bus_claim returns empty array ──────────
echo "--- Test 2: locked issue is excluded ---"
cat > "$GH_RESPONSE_FILE" <<'JSON'
[{"number":55,"labels":[{"name":"needs:tech"},{"name":"agent:lock:tech"}]}]
JSON

RESULT=$(bash -c "source \"$SUT\"; bus_claim tech" 2>/dev/null)
assert_json_eq "T2: locked issue excluded" "$RESULT" "[]"

# ── Summary ──────────────────────────────────────────────────────────────────
echo ""
echo "=== $((PASS + FAIL)) tests: $PASS passed, $FAIL failed ==="
[[ "$FAIL" -eq 0 ]]
