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
AMOF="$REPO_ROOT/claude-skills/scripts/auto-merge-or-flag.sh"

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

# ── Mock gh ──────────────────────────────────────────────────────────────────
MOCK_GH="$TMPDIR_TEST/gh"
GH_RESPONSE_FILE="$TMPDIR_TEST/gh_response"
GH_CALLS_FILE="$TMPDIR_TEST/gh_calls"
cat > "$MOCK_GH" <<'MOCK'
#!/usr/bin/env bash
echo "$*" >> "$GH_CALLS_FILE"
cat "$GH_RESPONSE_FILE" 2>/dev/null || true
MOCK
chmod +x "$MOCK_GH"
export GH_RESPONSE_FILE
export GH_CALLS_FILE
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

# ── Test 3: auto-merge-or-flag calls bus_unlock when PR body has Fixes #NN ───
echo "--- Test 3: bus_unlock called on auto-merge path when Fixes #NN present ---"
> "$GH_CALLS_FILE"

# Isolated working dir with its own .bsg-autopilot.yml
WORKDIR="$TMPDIR_TEST/workdir"
mkdir -p "$WORKDIR"
cat > "$WORKDIR/.bsg-autopilot.yml" <<'YAML'
enabled: true
auto_merge: true
agents:
  - tech
YAML

# gh mock: pr view returns body with Fixes #270; all other calls succeed silently
cat > "$GH_RESPONSE_FILE" <<'JSON'
{"body":"fix(pilot): Release pilot lock (#270)\n\nFixes #270\n"}
JSON

(
  cd "$WORKDIR"
  bash "$AMOF" 99 tech 2>/dev/null || true
)

assert_contains "T3: bus_unlock removes lock label" \
  "$(cat "$GH_CALLS_FILE")" \
  "issue edit 270 --remove-label agent:lock:tech"

# ── Summary ──────────────────────────────────────────────────────────────────
echo ""
echo "=== $((PASS + FAIL)) tests: $PASS passed, $FAIL failed ==="
[[ "$FAIL" -eq 0 ]]
