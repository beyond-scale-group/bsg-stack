#!/usr/bin/env bash
# test_consumers_use_resolver.sh — guard that every consumer script of a
# BSG custom doc sources `_bsg-paths.sh` instead of hardcoding legacy paths.
#
# Implements ADR-001 enforcement: once a script's read of a custom doc is
# routed through `bsg_doc_path`, it must stay routed. Catches regressions
# where someone re-introduces `marketing/CALENDAR.md` etc. without the
# resolver.
#
# Each row in CONSUMERS pairs a script path with the doc kinds it must
# resolve. A kind is "covered" if the script either:
#   - calls `bsg_doc_path <kind>`, or
#   - references the variable form `$(bsg_doc_path ...)` for that kind.
#
# Run locally:
#   bash claude-skills/tests/test_consumers_use_resolver.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

PASS=0
FAIL=0

check() {
  local file="$1" kind="$2"
  local path="$REPO_ROOT/$file"
  if [[ ! -f "$path" ]]; then
    echo "FAIL: $file does not exist"
    FAIL=$((FAIL + 1))
    return
  fi
  if grep -q "bsg_doc_path $kind\b" "$path"; then
    PASS=$((PASS + 1))
  else
    echo "FAIL: $file does not call \`bsg_doc_path $kind\`"
    FAIL=$((FAIL + 1))
  fi
}

# Consumer → doc kind pairs. Add a row when a new consumer script reads a
# custom doc; the test will fail until the script routes through the resolver.
check "claude-skills/skills/po/scripts/parse-plan.sh"               "plan"
check "claude-skills/skills/marketing-report/scripts/collect.sh"    "calendar"
check "claude-skills/skills/storytelling-report/scripts/collect.sh" "narrative"
check "claude-skills/skills/seo-report/scripts/collect.sh"          "keywords"
check "claude-skills/skills/pr-comms-report/scripts/collect.sh"     "announced"
check "claude-skills/skills/security-report/scripts/collect.sh"     "securityignore"
check "claude-skills/scripts/validate-plan.sh"                      "plan"

echo ""
echo "PASS: $PASS, FAIL: $FAIL"
[[ $FAIL -eq 0 ]] || exit 1
