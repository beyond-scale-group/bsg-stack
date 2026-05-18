#!/usr/bin/env bash
# test_init_scripts.sh — contract guard for per-agent `--init` scripts (#237).
#
# Every init script must:
#   1. Exist (path matches the expected pattern)
#   2. Be executable
#   3. Respond to --help with exit 0
#   4. Produce non-empty stdout in an empty tmp repo (so the orchestrator
#      always has *something* to write — first-tick repos shouldn't fail)
#   5. Not write to the cwd (the contract is stdout-only; the orchestrator
#      owns the disk side)
#
# Add a row to INIT_SCRIPTS when shipping a new per-agent init script.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

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

check_script() {
  local rel_path="$1"
  local path="$REPO_ROOT/$rel_path"
  local name="$(basename "$rel_path")"

  assert "$name exists"           "[[ -f '$path' ]]"
  assert "$name is executable"    "[[ -x '$path' ]]"
  assert "$name --help exits 0"   "$path --help >/dev/null 2>&1"

  # Run in an empty git repo, capture stdout, verify no disk write
  # happens inside the tmpdir (the contract is stdout-only).
  local tmp
  tmp="$(mktemp -d)"
  (
    cd "$tmp"
    git init -q
    bash "$path" > /tmp/init-script-output.$$ 2>/dev/null || true
  )
  local pre_files=$(find "$tmp" -mindepth 1 -not -path '*/.git*' 2>/dev/null | wc -l | tr -d ' ')
  local out_size=$(stat -f %z /tmp/init-script-output.$$ 2>/dev/null || stat -c %s /tmp/init-script-output.$$ 2>/dev/null || echo 0)
  rm -rf "$tmp" /tmp/init-script-output.$$

  assert "$name emits non-empty stdout in empty repo" "[[ '$out_size' -gt 50 ]]"
  assert "$name does not write to cwd"                "[[ '$pre_files' -eq 0 ]]"
}

# Add new init scripts here as they ship.
check_script "claude-skills/skills/seo-report/scripts/init-keywords.sh"
check_script "claude-skills/skills/marketing-report/scripts/init-calendar.sh"
check_script "claude-skills/skills/pr-comms-report/scripts/init-announced.sh"
check_script "claude-skills/skills/security-report/scripts/init-securityignore.sh"
check_script "claude-skills/skills/storytelling-report/scripts/init-narrative.sh"
check_script "claude-skills/skills/tech-report/scripts/init-adr.sh"

echo ""
echo "PASS: $PASS, FAIL: $FAIL"
[[ $FAIL -eq 0 ]] || exit 1
