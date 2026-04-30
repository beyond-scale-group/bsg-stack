#!/usr/bin/env bash
# test_pilot_candidates.sh — unit tests for list-pilot-candidates.sh label logic.
#
# Mocks `gh` and `.bsg-autopilot.yml` to verify the correct label flags
# are passed in each mode. No network calls, no real GitHub API.
#
# Run locally:
#   bash claude-skills/tests/test_pilot_candidates.sh
#
# Exit 0 = all pass, exit 1 = failure.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SUT="$REPO_ROOT/claude-skills/scripts/list-pilot-candidates.sh"

TMPDIR_TEST="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_TEST"' EXIT

PASS=0
FAIL=0

assert_contains() {
  local label="$1" haystack="$2" needle="$3"
  if echo "$haystack" | grep -qF -- "$needle"; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    echo "FAIL: $label"
    echo "  expected to find: $needle"
    echo "  in: $haystack"
  fi
}

assert_not_contains() {
  local label="$1" haystack="$2" needle="$3"
  if echo "$haystack" | grep -qF -- "$needle"; then
    FAIL=$((FAIL + 1))
    echo "FAIL: $label"
    echo "  expected NOT to find: $needle"
    echo "  in: $haystack"
  else
    PASS=$((PASS + 1))
  fi
}

# --- Mock gh: captures the arguments passed to `gh issue list` ---
# Only records args for `issue list` calls; silently ignores `issue edit`
# (bus_lock) so those don't overwrite the captured list-call args.
MOCK_GH="$TMPDIR_TEST/gh"
GH_ARGS_FILE="$TMPDIR_TEST/gh_args"
cat > "$MOCK_GH" <<'MOCK'
#!/usr/bin/env bash
# Only capture args for `gh issue list` calls.
if [[ "${2:-}" == "list" ]]; then
  echo "$@" > "$GH_ARGS_FILE"
  # Return one issue with an epic label so jq post-filter passes it through.
  cat <<'JSON'
[{"number":67,"title":"test issue","url":"https://example.com/67","labels":[{"name":"bug"},{"name":"tech"},{"name":"epic:E2"}]}]
JSON
fi
# bus_lock calls `gh issue edit` — succeed silently.
MOCK
chmod +x "$MOCK_GH"
export GH_ARGS_FILE

# Put mock gh first in PATH.
export PATH="$TMPDIR_TEST:$PATH"

# ---------- Test 1: No autopilot file → script exits 0 with no candidates ----------
# Since #286, auto-implementation is opt-in at the repo level via
# .bsg-autopilot.yml. Without the file the script exits before any
# `gh` call, so ARGS_FILE is never written and OUTPUT must be empty.
echo "--- Test 1: no autopilot file → no candidates ---"
cd "$TMPDIR_TEST"
rm -f .bsg-autopilot.yml "$GH_ARGS_FILE"
OUTPUT="$(bash "$SUT" --agent tech 2>/dev/null)"
if [[ -z "$OUTPUT" && ! -f "$GH_ARGS_FILE" ]]; then
  PASS=$((PASS + 1))
else
  FAIL=$((FAIL + 1))
  echo "FAIL: T1: expected no candidates and no gh call, got OUTPUT=[$OUTPUT] gh_called=$([[ -f "$GH_ARGS_FILE" ]] && echo yes || echo no)"
fi

# ---------- Test 2: Autopilot enabled for tech → drops both gates ----------
echo "--- Test 2: autopilot enabled for tech ---"
cat > "$TMPDIR_TEST/.bsg-autopilot.yml" <<'YAML'
enabled: true
agents:
  - tech
  - qa
YAML
bash "$SUT" --agent tech >/dev/null 2>&1
ARGS="$(cat "$GH_ARGS_FILE")"

assert_contains "T2: has --label tech" "$ARGS" "--label tech"
assert_not_contains "T2: no --label bug (filter moved to jq)" "$ARGS" "--label bug"
assert_not_contains "T2: no human-reviewed" "$ARGS" "human-reviewed"
assert_not_contains "T2: no safe-to-automate" "$ARGS" "safe-to-automate"
assert_not_contains "T2: no needs-human-review" "$ARGS" "needs-human-review"

# ---------- Test 3: Autopilot enabled but agent NOT listed → no candidates ----------
echo "--- Test 3: autopilot enabled, agent NOT listed (seo) → no candidates ---"
rm -f "$GH_ARGS_FILE"
OUTPUT="$(bash "$SUT" --agent seo 2>/dev/null)"
if [[ -z "$OUTPUT" && ! -f "$GH_ARGS_FILE" ]]; then
  PASS=$((PASS + 1))
else
  FAIL=$((FAIL + 1))
  echo "FAIL: T3: expected no candidates for unauthorized agent, got OUTPUT=[$OUTPUT]"
fi

# ---------- Test 4: Autopilot file exists but enabled: false → no candidates ----------
echo "--- Test 4: autopilot disabled → no candidates ---"
cat > "$TMPDIR_TEST/.bsg-autopilot.yml" <<'YAML'
enabled: false
agents:
  - tech
YAML
rm -f "$GH_ARGS_FILE"
OUTPUT="$(bash "$SUT" --agent tech 2>/dev/null)"
if [[ -z "$OUTPUT" && ! -f "$GH_ARGS_FILE" ]]; then
  PASS=$((PASS + 1))
else
  FAIL=$((FAIL + 1))
  echo "FAIL: T4: expected no candidates with enabled:false, got OUTPUT=[$OUTPUT]"
fi

# Tests 5+ require autopilot to be enabled — that's the only path that
# reaches `gh issue list` since #286.
write_autopilot_enabled() {
  cat > "$TMPDIR_TEST/.bsg-autopilot.yml" <<'YAML'
enabled: true
agents:
  - tech
  - qa
YAML
}

# ---------- Test 5: jq post-filter requires epic:* label ----------
echo "--- Test 5: epic filter ---"
write_autopilot_enabled
# Mock gh returns an issue WITHOUT an epic label.
cat > "$MOCK_GH" <<'MOCK2'
#!/usr/bin/env bash
if [[ "${2:-}" == "list" ]]; then
  echo "$@" > "$GH_ARGS_FILE"
  cat <<'JSON'
[{"number":99,"title":"no epic","url":"https://example.com/99","labels":[{"name":"bug"},{"name":"tech"}]}]
JSON
fi
MOCK2
chmod +x "$MOCK_GH"

OUTPUT="$(bash "$SUT" --agent tech 2>/dev/null)"
if [[ -z "$OUTPUT" ]]; then
  PASS=$((PASS + 1))
else
  FAIL=$((FAIL + 1))
  echo "FAIL: T5: issue without epic should be filtered out, got: $OUTPUT"
fi

# ---------- Test 6: needs-human-review must NEVER appear in label flags ----------
echo "--- Test 6: regression guard — needs-human-review never in label flags ---"
write_autopilot_enabled
cat > "$MOCK_GH" <<'MOCK3'
#!/usr/bin/env bash
if [[ "${2:-}" == "list" ]]; then
  echo "$@" > "$GH_ARGS_FILE"
  echo '[]'
fi
MOCK3
chmod +x "$MOCK_GH"

bash "$SUT" --agent tech >/dev/null 2>&1
ARGS="$(cat "$GH_ARGS_FILE")"
assert_not_contains "T6: no needs-human-review (autopilot)" "$ARGS" "needs-human-review"
assert_not_contains "T6: no human-reviewed (autopilot)" "$ARGS" "human-reviewed"
assert_not_contains "T6: no safe-to-automate (autopilot)" "$ARGS" "safe-to-automate"

# ---------- Test 7: bus_lock called on first candidate ----------
echo "--- Test 7: bus_lock invoked on first candidate ---"
write_autopilot_enabled
GH_LOCK_FILE="$TMPDIR_TEST/gh_lock_args"
rm -f "$GH_LOCK_FILE"
cat > "$MOCK_GH" <<'MOCK4'
#!/usr/bin/env bash
if [[ "${2:-}" == "list" ]]; then
  echo "$@" > "$GH_ARGS_FILE"
  cat <<'JSON'
[{"number":42,"title":"lock me","url":"https://example.com/42","labels":[{"name":"bug"},{"name":"tech"},{"name":"epic:E1"}]}]
JSON
elif [[ "${2:-}" == "edit" ]]; then
  echo "$@" > "$GH_LOCK_FILE"
fi
MOCK4
chmod +x "$MOCK_GH"
export GH_LOCK_FILE

bash "$SUT" --agent tech >/dev/null 2>&1
LOCK_ARGS="$(cat "$GH_LOCK_FILE" 2>/dev/null || echo "")"
assert_contains "T7: bus_lock adds agent:lock:tech" "$LOCK_ARGS" "agent:lock:tech"
assert_contains "T7: bus_lock targets issue 42" "$LOCK_ARGS" "42"

# ---------- Test 8: enhancement issues are eligible (#282) ----------
echo "--- Test 8: enhancement-only issue surfaces as candidate ---"
write_autopilot_enabled
cat > "$MOCK_GH" <<'MOCK8'
#!/usr/bin/env bash
if [[ "${2:-}" == "list" ]]; then
  echo "$@" > "$GH_ARGS_FILE"
  cat <<'JSON'
[{"number":62,"title":"enh","url":"https://example.com/62","labels":[{"name":"enhancement"},{"name":"tech"},{"name":"epic:E1"}]}]
JSON
fi
MOCK8
chmod +x "$MOCK_GH"

OUTPUT="$(bash "$SUT" --agent tech 2>/dev/null)"
assert_contains "T8: enhancement issue surfaces" "$OUTPUT" '"number":62'

# ---------- Test 9: issue with neither bug nor enhancement is rejected ----------
echo "--- Test 9: issue without bug/enhancement is filtered out ---"
write_autopilot_enabled
cat > "$MOCK_GH" <<'MOCK9'
#!/usr/bin/env bash
if [[ "${2:-}" == "list" ]]; then
  echo "$@" > "$GH_ARGS_FILE"
  cat <<'JSON'
[{"number":77,"title":"docs","url":"https://example.com/77","labels":[{"name":"documentation"},{"name":"tech"},{"name":"epic:E1"}]}]
JSON
fi
MOCK9
chmod +x "$MOCK_GH"

OUTPUT="$(bash "$SUT" --agent tech 2>/dev/null)"
if [[ -z "$OUTPUT" ]]; then
  PASS=$((PASS + 1))
else
  FAIL=$((FAIL + 1))
  echo "FAIL: T9: docs-only issue should be filtered out, got: $OUTPUT"
fi

# ---------- Summary ----------
echo ""
echo "=== $((PASS + FAIL)) tests: $PASS passed, $FAIL failed ==="
[[ "$FAIL" -eq 0 ]]
