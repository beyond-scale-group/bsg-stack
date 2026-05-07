#!/usr/bin/env bash
# test_po_init.sh — unit tests for skills/po/scripts/init.sh.
#
# Covers the safety-check + path-resolution wrapper around
# bootstrap-plan.sh. Uses a fixture snapshot so no GitHub API calls
# happen at test time.
#
# Run locally:
#   bash claude-skills/tests/test_po_init.sh
#
# Exit 0 = all pass, exit 1 = failure.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SUT="$REPO_ROOT/claude-skills/skills/po/scripts/init.sh"

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
    echo "  got: $haystack"
  fi
}

# Build a deterministic snapshot fixture so bootstrap-plan.sh has data
# to render without needing a `gh` GraphQL call.
SNAPSHOT="$(mktemp)"
cat >"$SNAPSHOT" <<'EOF'
{
  "repo": "test-org/test-repo",
  "milestones": [
    {"title": "M1-launch", "state": "open", "dueOn": "2026-06-01"},
    {"title": "M0-archived", "state": "closed", "dueOn": null}
  ],
  "issues": [
    {"number": 1, "title": "Add login flow", "state": "OPEN", "labels": ["bug", "tech"]},
    {"number": 2, "title": "Add signup flow", "state": "OPEN", "labels": ["enhancement"]}
  ],
  "pullRequests": [],
  "labels": [],
  "releases": []
}
EOF

# 1. Fresh repo: writes .bsg/PLAN.md with the milestone seeded as an objective.
TMP="$(mktemp -d)"
( cd "$TMP" && bash "$SUT" --snapshot "$SNAPSHOT" >/dev/null 2>&1 )
rc=$?
assert_eq "fresh repo: rc=0" "0" "$rc"
assert_eq "fresh repo: writes .bsg/PLAN.md" "1" "$([[ -f $TMP/.bsg/PLAN.md ]] && echo 1 || echo 0)"

if [[ -f "$TMP/.bsg/PLAN.md" ]]; then
  content="$(cat "$TMP/.bsg/PLAN.md")"
  assert_contains "fresh repo: includes M1-launch milestone"   "$content" "M1-launch"
  assert_contains "fresh repo: includes binding tag"           "$content" "[milestone:M1-launch]"
  assert_contains "fresh repo: skips closed milestones"        "$(echo "$content" | grep -v M0-archived | head -50)" "Objectives"
  # Closed milestones must NOT be rendered as objectives:
  if grep -q "M0-archived" "$TMP/.bsg/PLAN.md"; then
    FAIL=$((FAIL + 1))
    echo "FAIL: fresh repo: closed milestones should not appear in plan"
  else
    PASS=$((PASS + 1))
  fi
fi
rm -rf "$TMP"

# 2. Existing plan: refuses with rc=3.
TMP="$(mktemp -d)"
mkdir -p "$TMP/.bsg"
echo "# existing" > "$TMP/.bsg/PLAN.md"
set +e
out="$( cd "$TMP" && bash "$SUT" --snapshot "$SNAPSHOT" 2>&1 )"
rc=$?
set -e
assert_eq "existing plan: rc=3" "3" "$rc"
assert_contains "existing plan: error mentions --force" "$out" "--force"
# Verify it didn't overwrite:
assert_eq "existing plan: not overwritten" "# existing" "$(cat "$TMP/.bsg/PLAN.md")"
rm -rf "$TMP"

# 3. Existing plan + --force: overwrites.
TMP="$(mktemp -d)"
mkdir -p "$TMP/.bsg"
echo "# existing" > "$TMP/.bsg/PLAN.md"
( cd "$TMP" && bash "$SUT" --snapshot "$SNAPSHOT" --force >/dev/null 2>&1 )
rc=$?
assert_eq "force overwrite: rc=0" "0" "$rc"
content="$(cat "$TMP/.bsg/PLAN.md")"
assert_contains "force overwrite: bootstrapped header"   "$content" "Big plan"
rm -rf "$TMP"

# 4. --dry-run: writes nothing, prints draft to stdout.
TMP="$(mktemp -d)"
out="$( cd "$TMP" && bash "$SUT" --snapshot "$SNAPSHOT" --dry-run 2>/dev/null )"
rc=$?
assert_eq "dry run: rc=0" "0" "$rc"
assert_contains "dry run: prints draft to stdout"    "$out" "Big plan"
assert_contains "dry run: prints milestone binding"  "$out" "[milestone:M1-launch]"
assert_eq       "dry run: writes nothing" "0" "$([[ -f $TMP/.bsg/PLAN.md ]] && echo 1 || echo 0)"
rm -rf "$TMP"

# 5. --out custom destination is honored.
TMP="$(mktemp -d)"
( cd "$TMP" && bash "$SUT" --snapshot "$SNAPSHOT" --out custom/PLAN.md >/dev/null 2>&1 )
assert_eq "custom out: file exists" "1" "$([[ -f $TMP/custom/PLAN.md ]] && echo 1 || echo 0)"
assert_eq "custom out: .bsg/PLAN.md NOT written" "0" "$([[ -f $TMP/.bsg/PLAN.md ]] && echo 1 || echo 0)"
rm -rf "$TMP"

# 6. Legacy po/PLAN.md takes precedence over .bsg/ on a partially-migrated
#    repo (matches _bsg-paths.sh resolver semantics — refuses without --force).
TMP="$(mktemp -d)"
mkdir -p "$TMP/po"
echo "# legacy" > "$TMP/po/PLAN.md"
set +e
out="$( cd "$TMP" && bash "$SUT" --snapshot "$SNAPSHOT" 2>&1 )"
rc=$?
set -e
assert_eq       "partial migration: rc=3 because legacy plan exists" "3" "$rc"
assert_contains "partial migration: error names legacy path"         "$out" "po/PLAN.md"
rm -rf "$TMP"

# 7. Unknown flag → rc=2.
set +e
bash "$SUT" --bogus >/dev/null 2>&1
rc=$?
set -e
assert_eq "unknown flag: rc=2" "2" "$rc"

rm -f "$SNAPSHOT"

echo ""
echo "PASS: $PASS, FAIL: $FAIL"
[[ $FAIL -eq 0 ]] || exit 1
