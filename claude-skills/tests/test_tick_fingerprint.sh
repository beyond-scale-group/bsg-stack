#!/usr/bin/env bash
# test_tick_fingerprint.sh — verify tick-fingerprint.sh exports propagate to child processes.
# Regression test for #262: TICK_FINGERPRINT was not exported, so generate-report.sh
# always saw "none".

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/.." && pwd)
TICK_FP="$REPO_ROOT/scripts/tick-fingerprint.sh"

PASS=0
FAIL=0

assert_eq() {
  local label="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    echo "  PASS: $label"
    ((PASS++)) || true
  else
    echo "  FAIL: $label (expected='$expected', got='$actual')"
    ((FAIL++)) || true
  fi
}

echo "=== test_tick_fingerprint.sh ==="

# Capture the output once (gh API calls make this ~2-3s)
output=$(bash "$TICK_FP" tech-lead tech 2>/dev/null)

# --- Test 1: output lines use 'export' keyword ---
echo "Test 1: emitted assignments use 'export'"
exports_count=$(echo "$output" | grep -c '^export ' || true)
assert_eq "all 4 lines start with 'export'" "4" "$exports_count"

# --- Test 2: all expected variables are present ---
echo "Test 2: all expected variables present"
for var in TICK_SHORT_CIRCUIT TICK_LAST_PR TICK_FINGERPRINT TICK_REPORT_FILE; do
  if echo "$output" | grep -q "^export ${var}="; then
    echo "  PASS: $var present"
    ((PASS++)) || true
  else
    echo "  FAIL: $var missing from output"
    ((FAIL++)) || true
  fi
done

# --- Test 3: TICK_FINGERPRINT propagates to a child bash process ---
echo "Test 3: TICK_FINGERPRINT visible in child process"
eval "$output"
child_val=$(bash -c 'echo $TICK_FINGERPRINT')
if [[ -n "$child_val" && "$child_val" != "none" ]]; then
  echo "  PASS: child process sees TICK_FINGERPRINT='$child_val'"
  ((PASS++)) || true
else
  echo "  FAIL: child process got TICK_FINGERPRINT='$child_val' (expected non-empty, non-'none')"
  ((FAIL++)) || true
fi

# --- Test 4: TICK_FINGERPRINT is a 16-char hex string ---
echo "Test 4: fingerprint format"
if [[ "$TICK_FINGERPRINT" =~ ^[0-9a-f]{16}$ ]]; then
  echo "  PASS: fingerprint is 16-char hex ($TICK_FINGERPRINT)"
  ((PASS++)) || true
else
  echo "  FAIL: fingerprint format unexpected: '$TICK_FINGERPRINT'"
  ((FAIL++)) || true
fi

# --- Summary ---
echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]] || exit 1
