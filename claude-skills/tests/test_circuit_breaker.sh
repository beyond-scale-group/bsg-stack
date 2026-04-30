#!/usr/bin/env bash
# test_circuit_breaker.sh — unit tests for pilot-circuit-breaker.sh
#
# Tests:
#   - Scalar max_prs_per_day (backward-compat): global cap
#   - Map max_prs_per_day: per-bus cap with _default fallback
#   - --bus flag respected when map format used
#   - Under cap → exit 0; at/over cap → exit 1
#
# Run locally:
#   bash claude-skills/tests/test_circuit_breaker.sh
#
# Exit 0 = all pass, exit 1 = failure.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SUT="$REPO_ROOT/claude-skills/scripts/pilot-circuit-breaker.sh"

TMPDIR_TEST="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_TEST"' EXIT

PASS=0
FAIL=0

assert_exit() {
  local label="$1" expected="$2"
  shift 2
  local actual
  actual=0
  "$@" >/dev/null 2>&1 || actual=$?
  if [[ "$actual" -eq "$expected" ]]; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    echo "FAIL: $label — expected exit $expected, got $actual"
  fi
}

# --- Mock gh: returns N fake pilot PRs ---
make_mock_gh() {
  local count="$1"
  local bus_label="${2:-}"
  local mock="$TMPDIR_TEST/gh"
  local items=""
  for i in $(seq 1 "$count"); do
    local labels_json='[{"name":"tech"}]'
    if [[ -n "$bus_label" ]]; then
      labels_json="[{\"name\":\"$bus_label\"}]"
    fi
    items+='{"number":'"$i"',"labels":'"$labels_json"'},'
  done
  items="${items%,}"
  cat > "$mock" <<MOCK
#!/usr/bin/env bash
echo '[$items]'
MOCK
  # Use printf to safely embed the items string
  printf '#!/usr/bin/env bash\necho '"'"'[%s]'"'"'\n' "$items" > "$mock"
  chmod +x "$mock"
  export PATH="$TMPDIR_TEST:$PATH"
}

# ---- Test 1: scalar cap — under limit (2 PRs, cap 3) → exit 0 ----
echo "--- Test 1: scalar cap, under limit ---"
cd "$TMPDIR_TEST"
cat > .bsg-autopilot.yml <<'YAML'
enabled: true
budget:
  max_prs_per_day: 3
YAML
make_mock_gh 2
assert_exit "T1: 2 PRs < cap=3 → exit 0" 0 bash "$SUT"

# ---- Test 2: scalar cap — at limit (3 PRs, cap 3) → exit 1 ----
echo "--- Test 2: scalar cap, at limit ---"
make_mock_gh 3
assert_exit "T2: 3 PRs >= cap=3 → exit 1" 1 bash "$SUT"

# ---- Test 3: map cap — bus under its own cap (tech: 2 PRs, cap 5) → exit 0 ----
echo "--- Test 3: map cap, bus under limit ---"
cat > .bsg-autopilot.yml <<'YAML'
enabled: true
budget:
  max_prs_per_day:
    _default: 200
    tech: 5
    qa: 3
YAML
make_mock_gh 2 "tech"
assert_exit "T3: tech 2 PRs < cap=5 → exit 0" 0 bash "$SUT" --bus tech

# ---- Test 4: map cap — bus at its own cap (tech: 5 PRs, cap 5) → exit 1 ----
echo "--- Test 4: map cap, bus at limit ---"
make_mock_gh 5 "tech"
assert_exit "T4: tech 5 PRs >= cap=5 → exit 1" 1 bash "$SUT" --bus tech

# ---- Test 5: map cap — _default fallback used for unlisted bus ----
echo "--- Test 5: map cap, _default fallback ---"
cat > .bsg-autopilot.yml <<'YAML'
enabled: true
budget:
  max_prs_per_day:
    _default: 2
    tech: 50
YAML
make_mock_gh 2 "seo"
assert_exit "T5: seo 2 PRs >= _default=2 → exit 1" 1 bash "$SUT" --bus seo

# ---- Test 6: map cap — bus well under _default ----
echo "--- Test 6: map cap, bus under _default ---"
make_mock_gh 1 "seo"
assert_exit "T6: seo 1 PR < _default=2 → exit 0" 0 bash "$SUT" --bus seo

# ---- Test 7: no autopilot file — uses hardcoded default=3 ----
echo "--- Test 7: no autopilot file, default cap ---"
rm -f .bsg-autopilot.yml
make_mock_gh 2
assert_exit "T7: 2 PRs < default cap=3 → exit 0" 0 bash "$SUT"

make_mock_gh 3
assert_exit "T7b: 3 PRs >= default cap=3 → exit 1" 1 bash "$SUT"

# ---- Test 8: backward compat — scalar used even without --bus ----
echo "--- Test 8: scalar cap, no --bus flag ---"
cat > .bsg-autopilot.yml <<'YAML'
enabled: true
budget:
  max_prs_per_day: 10
YAML
make_mock_gh 5
assert_exit "T8: scalar cap 10, 5 PRs → exit 0" 0 bash "$SUT"

# ---------- Summary ----------
echo ""
echo "=== $((PASS + FAIL)) tests: $PASS passed, $FAIL failed ==="
[[ "$FAIL" -eq 0 ]]
