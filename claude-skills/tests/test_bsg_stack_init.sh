#!/usr/bin/env bash
# test_bsg_stack_init.sh — unit tests for skills/bsg-stack/scripts/init.sh
# and update.sh.
#
# Run locally:
#   bash claude-skills/tests/test_bsg_stack_init.sh
#
# Exit 0 = all pass, exit 1 = failure.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
INIT_SH="$REPO_ROOT/claude-skills/skills/bsg-stack/scripts/init.sh"
UPDATE_SH="$REPO_ROOT/claude-skills/skills/bsg-stack/scripts/update.sh"

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

assert_contains() {
  local label="$1" haystack="$2" needle="$3"
  if echo "$haystack" | grep -qF -- "$needle"; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    echo "FAIL: $label"
    echo "  expected to contain: $needle"
    echo "  got: $(echo "$haystack" | head -3)"
  fi
}

# --- init.sh tests --------------------------------------------------------

# 1. Unknown flag → rc=2.
set +e
"$INIT_SH" --bogus >/dev/null 2>&1
rc=$?
set -e
assert_eq "init.sh: unknown flag → rc=2" "2" "$rc"

# 2. Help works.
out="$("$INIT_SH" --help 2>&1)"
assert_contains "init.sh: --help prints docstring" "$out" "first-time bootstrap"

# 3. --dry-run --skip-labels in a fresh repo. Touches nothing, lists what
#    would happen, exits 0.
TMP="$(mktemp -d)"
out="$( cd "$TMP" && "$INIT_SH" --dry-run --skip-labels 2>&1 )"
rc=$?
assert_eq "init.sh: dry-run rc=0" "0" "$rc"
assert_contains "init.sh: dry-run announces .bsg/ skeleton"  "$out" "Ensuring .bsg/ skeleton"
assert_contains "init.sh: dry-run announces per-agent init"  "$out" "Per-agent init"
assert_contains "init.sh: dry-run skips labels"              "$out" "skip-labels"
# Dry-run must NOT have created anything:
assert_eq "init.sh: dry-run wrote nothing" "0" "$([[ -d $TMP/.bsg ]] && echo 1 || echo 0)"
rm -rf "$TMP"

# 4. Real run (no labels, no gh). Creates skeleton + TODO stubs for agents
#    that have no per-agent init script.
TMP="$(mktemp -d)"
( cd "$TMP" && "$INIT_SH" --skip-labels --only seo,marketing,storytelling,pr-comms,security,cleaner >/dev/null 2>&1 )
rc=$?
assert_eq "init.sh: real run rc=0" "0" "$rc"
assert_eq "init.sh: created .bsg/" "1" "$([[ -d $TMP/.bsg ]] && echo 1 || echo 0)"
assert_eq "init.sh: created .bsg/adr/"     "1" "$([[ -d $TMP/.bsg/adr ]] && echo 1 || echo 0)"
assert_eq "init.sh: created .bsg/reports/" "1" "$([[ -d $TMP/.bsg/reports ]] && echo 1 || echo 0)"
assert_eq "init.sh: stubbed KEYWORDS.md"   "1" "$([[ -f $TMP/.bsg/KEYWORDS.md ]] && echo 1 || echo 0)"
assert_eq "init.sh: stubbed CALENDAR.md"   "1" "$([[ -f $TMP/.bsg/CALENDAR.md ]] && echo 1 || echo 0)"
assert_eq "init.sh: stubbed NARRATIVE.md"  "1" "$([[ -f $TMP/.bsg/NARRATIVE.md ]] && echo 1 || echo 0)"
assert_eq "init.sh: stubbed ANNOUNCED.md"  "1" "$([[ -f $TMP/.bsg/ANNOUNCED.md ]] && echo 1 || echo 0)"
assert_eq "init.sh: stubbed SECURITYIGNORE" "1" "$([[ -f $TMP/.bsg/SECURITYIGNORE ]] && echo 1 || echo 0)"

# Stubs reference #237 deliverable #2 so future readers know the plan.
assert_contains "init.sh: stub references #237" "$(cat "$TMP/.bsg/KEYWORDS.md")" "#237 deliverable #2"

# Re-run is idempotent (no-op when docs exist):
out="$( cd "$TMP" && "$INIT_SH" --skip-labels --only seo 2>&1 )"
assert_contains "init.sh: re-run skips existing docs" "$out" "already exists"
rm -rf "$TMP"

# 5. --only filter is respected.
TMP="$(mktemp -d)"
out="$( cd "$TMP" && "$INIT_SH" --skip-labels --only seo --dry-run 2>&1 )"
assert_contains "init.sh: --only includes seo" "$out" "seo:"
# Should NOT mention marketing or pr-comms in the per-agent section:
if echo "$out" | grep -qE "^  marketing:"; then
  FAIL=$((FAIL + 1))
  echo "FAIL: init.sh: --only seo should not process marketing"
else
  PASS=$((PASS + 1))
fi
rm -rf "$TMP"

# --- update.sh tests ------------------------------------------------------

# 6. Unknown flag → rc=2.
set +e
"$UPDATE_SH" --unknown >/dev/null 2>&1
rc=$?
set -e
assert_eq "update.sh: unknown flag → rc=2" "2" "$rc"

# 7. Empty repo → every agent skipped with "missing" note.
TMP="$(mktemp -d)"
out="$( cd "$TMP" && "$UPDATE_SH" 2>&1 )"
rc=$?
assert_eq "update.sh: empty repo rc=0" "0" "$rc"
assert_contains "update.sh: notes missing PLAN.md"      "$out" "PLAN.md is missing"
assert_contains "update.sh: notes missing NARRATIVE.md" "$out" "NARRATIVE.md is missing"
assert_contains "update.sh: directs to /bsg-stack init" "$out" "run /bsg-stack init first"
rm -rf "$TMP"

# 8. Fresh doc (newly written) → skip silently.
TMP="$(mktemp -d)"
mkdir -p "$TMP/.bsg"
echo "# fresh" > "$TMP/.bsg/PLAN.md"
out="$( cd "$TMP" && "$UPDATE_SH" --only po 2>&1 )"
assert_contains "update.sh: fresh doc reported as fresh" "$out" "is fresh"
rm -rf "$TMP"

# 9. Stale doc → would-refresh in dry-run.
TMP="$(mktemp -d)"
mkdir -p "$TMP/.bsg"
echo "# stale" > "$TMP/.bsg/PLAN.md"
# Backdate the file 200 days.
touch -t "$(date -v-200d +%Y%m%d0000 2>/dev/null || date -d "200 days ago" +%Y%m%d0000)" "$TMP/.bsg/PLAN.md"
out="$( cd "$TMP" && "$UPDATE_SH" --only po --dry-run 2>&1 )"
assert_contains "update.sh: stale doc detected"          "$out" "is stale"
assert_contains "update.sh: dry-run says would-run"      "$out" "would run"
# Stale dry-run must NOT mutate:
assert_eq "update.sh: dry-run did not mutate" "# stale" "$(cat "$TMP/.bsg/PLAN.md")"
rm -rf "$TMP"

# 10. --max-age-days override.
TMP="$(mktemp -d)"
mkdir -p "$TMP/.bsg"
echo "# medium" > "$TMP/.bsg/PLAN.md"
touch -t "$(date -v-30d +%Y%m%d0000 2>/dev/null || date -d "30 days ago" +%Y%m%d0000)" "$TMP/.bsg/PLAN.md"
# Default 90d threshold → fresh
out="$( cd "$TMP" && "$UPDATE_SH" --only po 2>&1 )"
assert_contains "update.sh: 30-day file fresh at 90d threshold" "$out" "is fresh"
# Tighter 7d threshold → stale
out="$( cd "$TMP" && "$UPDATE_SH" --only po --max-age-days 7 --dry-run 2>&1 )"
assert_contains "update.sh: 30-day file stale at 7d threshold"  "$out" "is stale"
rm -rf "$TMP"

echo ""
echo "PASS: $PASS, FAIL: $FAIL"
[[ $FAIL -eq 0 ]] || exit 1
