#!/usr/bin/env bash
# test_bsg_stack_orchestrator.sh — guards for /bsg-stack init/update/status.
#
# Verifies the orchestrator scripts:
#   1. Respond to --help with exit 0
#   2. Run --dry-run cleanly in an empty tmpdir (no crash, no disk writes)
#   3. Are idempotent: running twice produces the same .bsg/ tree
#   4. status.sh delegates to doctor.sh --status

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

INIT="$REPO_ROOT/claude-skills/skills/bsg-stack/scripts/init.sh"
UPDATE="$REPO_ROOT/claude-skills/skills/bsg-stack/scripts/update.sh"
STATUS="$REPO_ROOT/claude-skills/skills/bsg-stack/scripts/status.sh"

PASS=0
FAIL=0

assert() {
  local label="$1" condition="$2"
  if eval "$condition"; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    echo "FAIL: $label"
    echo "  condition: $condition"
  fi
}

# 1. Each script exists, is executable, and responds to --help.
for s in "$INIT" "$UPDATE" "$STATUS"; do
  name="$(basename "$s")"
  assert "$name exists"        "[[ -f '$s' ]]"
  assert "$name is executable" "[[ -x '$s' ]]"
  assert "$name --help exits 0" "$s --help >/dev/null 2>&1"
done

# 2. init.sh --dry-run in an empty git repo:
#    - exits cleanly
#    - does NOT create .bsg/ (it's a dry run)
tmp="$(mktemp -d)"
(
  cd "$tmp"
  git init -q
)
assert "init --dry-run exits 0 in empty repo" \
  "(cd '$tmp' && bash '$INIT' --dry-run --no-labels >/dev/null 2>&1)"
assert "init --dry-run does NOT create .bsg/" \
  "[[ ! -d '$tmp/.bsg' ]]"
rm -rf "$tmp"

# 3. init.sh real run in an empty git repo:
#    - exits cleanly
#    - creates .bsg/ with skeleton subdirs
#    - re-running produces no diff in the .bsg/ tree
tmp="$(mktemp -d)"
(
  cd "$tmp"
  git init -q
  bash "$INIT" --no-labels >/dev/null 2>&1
)
assert "init creates .bsg/ skeleton"            "[[ -d '$tmp/.bsg' ]]"
assert "init creates .bsg/adr/"                 "[[ -d '$tmp/.bsg/adr' ]]"
assert "init creates .bsg/reports/po/"          "[[ -d '$tmp/.bsg/reports/po' ]]"
assert "init creates .bsg/AUTOPILOT.yml"        "[[ -f '$tmp/.bsg/AUTOPILOT.yml' ]]"

# Per-agent custom docs that #622 (and the wider #237 batch) explicitly
# required init.sh to bootstrap. Each row below pairs one of those four
# agents with the .bsg/ path its init script must populate. Pin them here
# so a future change that drops a wire from init.sh — or breaks one of
# the per-agent init-*.sh scripts — fails the orchestrator suite
# instead of silently producing an incomplete .bsg/ tree.
assert "init creates .bsg/CALENDAR.md (marketing)"                "[[ -f '$tmp/.bsg/CALENDAR.md' ]]"
assert "init creates .bsg/ANNOUNCED.md (pr-comms)"                "[[ -f '$tmp/.bsg/ANNOUNCED.md' ]]"
assert "init creates .bsg/adr/0000-architecture-baseline.md"      "[[ -f '$tmp/.bsg/adr/0000-architecture-baseline.md' ]]"
assert "init creates .bsg/reports/qa/0000-baseline.md"            "[[ -f '$tmp/.bsg/reports/qa/0000-baseline.md' ]]"

# Capture pre-state, re-run, compare.
pre="$(find "$tmp/.bsg" -type f | sort | xargs -I{} stat -f '%N %m' {} 2>/dev/null \
       || find "$tmp/.bsg" -type f | sort | xargs -I{} stat -c '%n %Y' {})"
(
  cd "$tmp"
  bash "$INIT" --no-labels >/dev/null 2>&1
)
post="$(find "$tmp/.bsg" -type f | sort | xargs -I{} stat -f '%N %m' {} 2>/dev/null \
       || find "$tmp/.bsg" -type f | sort | xargs -I{} stat -c '%n %Y' {})"
assert "init is idempotent (re-run leaves .bsg/ unchanged)" "[[ '$pre' == '$post' ]]"
rm -rf "$tmp"

# 4. update.sh --dry-run in an empty git repo: exits cleanly.
tmp="$(mktemp -d)"
(
  cd "$tmp"
  git init -q
)
assert "update --dry-run exits 0 in empty repo" \
  "(cd '$tmp' && bash '$UPDATE' --dry-run >/dev/null 2>&1)"
rm -rf "$tmp"

# 5. status.sh runs doctor.sh --status.
tmp="$(mktemp -d)"
(
  cd "$tmp"
  git init -q
)
# status.sh exits 1 when missing docs detected — that's expected in
# an empty repo. We just verify it ran and produced output.
out="$(cd "$tmp" && bash "$STATUS" 2>&1 || true)"
assert "status.sh produces summary line" "[[ '$out' == *'BSG:'* ]]"
rm -rf "$tmp"

echo ""
echo "PASS: $PASS, FAIL: $FAIL"
[[ $FAIL -eq 0 ]] || exit 1
