#!/usr/bin/env bash
# test_bsg_paths.sh — unit tests for _bsg-paths.sh resolver.
#
# Verifies that bsg_doc_path resolves every known doc kind correctly:
#   - Returns the .bsg/ path when it exists on disk
#   - Falls back to the legacy path when only legacy exists
#   - Returns the .bsg/ path when neither exists (so first writes go new)
#   - Returns rc=2 for unknown kinds
#
# Run locally:
#   bash claude-skills/tests/test_bsg_paths.sh
#
# Exit 0 = all pass, exit 1 = failure.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SUT="$REPO_ROOT/claude-skills/scripts/_bsg-paths.sh"

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

# Resolve relative to a tmpdir so we don't pollute the repo's own state.
run_in_tmp() {
  local tmp="$(mktemp -d)"
  ( cd "$tmp" && eval "$1" )
  local rc=$?
  rm -rf "$tmp"
  return $rc
}

# 1. Empty repo → returns the .bsg/ path (so first writes are new).
out="$(run_in_tmp 'source "'"$SUT"'"; bsg_doc_path plan')"
assert_eq "empty repo: plan resolves to .bsg/PLAN.md" ".bsg/PLAN.md" "$out"

out="$(run_in_tmp 'source "'"$SUT"'"; bsg_doc_path autopilot')"
# Empty repo: returns the .bsg/ path so --init / first-write callers
# write into the new tree without further wiring.
assert_eq "empty repo: autopilot resolves to .bsg/AUTOPILOT.yml" ".bsg/AUTOPILOT.yml" "$out"

# 2. Legacy-only repo → fallback path.
tmp="$(mktemp -d)"
mkdir -p "$tmp/po"
touch "$tmp/po/PLAN.md"
out="$(cd "$tmp" && bash -c "source $SUT; bsg_doc_path plan")"
assert_eq "legacy-only: plan resolves to po/PLAN.md" "po/PLAN.md" "$out"
rm -rf "$tmp"

# 3. .bsg/-only repo → new path.
tmp="$(mktemp -d)"
mkdir -p "$tmp/.bsg"
touch "$tmp/.bsg/PLAN.md"
touch "$tmp/.bsg/AUTOPILOT.yml"
out="$(cd "$tmp" && bash -c "source $SUT; bsg_doc_path plan")"
assert_eq ".bsg-only: plan resolves to .bsg/PLAN.md" ".bsg/PLAN.md" "$out"

out="$(cd "$tmp" && bash -c "source $SUT; bsg_doc_path autopilot")"
assert_eq ".bsg-only: autopilot resolves to .bsg/AUTOPILOT.yml" ".bsg/AUTOPILOT.yml" "$out"

out="$(cd "$tmp" && bash -c "source $SUT; printf '%s' \"\$BSG_AUTOPILOT_FILE\"")"
assert_eq ".bsg-only: BSG_AUTOPILOT_FILE matches resolver" ".bsg/AUTOPILOT.yml" "$out"
rm -rf "$tmp"

# 4. Both present → .bsg/ wins.
tmp="$(mktemp -d)"
mkdir -p "$tmp/.bsg" "$tmp/po"
touch "$tmp/.bsg/PLAN.md"
touch "$tmp/po/PLAN.md"
out="$(cd "$tmp" && bash -c "source $SUT; bsg_doc_path plan")"
assert_eq "both present: .bsg/ wins" ".bsg/PLAN.md" "$out"
rm -rf "$tmp"

# 5. Unknown doc kind → rc=2.
set +e
out="$(bash -c "source $SUT; bsg_doc_path bogus" 2>&1)"
rc=$?
set -e
assert_eq "unknown kind: rc=2" "2" "$rc"

# 6. Every doc kind in the table is recognized (regression guard).
for kind in autopilot plan narrative keywords calendar announced \
            securityignore design adr brand reports; do
  set +e
  out="$(run_in_tmp 'source "'"$SUT"'"; bsg_doc_path '"$kind"' >/dev/null')"
  rc=$?
  set -e
  assert_eq "kind '$kind' is recognized (rc=0)" "0" "$rc"
done

echo ""
echo "PASS: $PASS, FAIL: $FAIL"
[[ $FAIL -eq 0 ]] || exit 1
