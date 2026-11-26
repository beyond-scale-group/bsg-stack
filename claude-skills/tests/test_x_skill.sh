#!/usr/bin/env bash
# test_x_skill.sh — offline tests for the x skill CLI (claude-skills/skills/x/scripts).
#
# No network, no X account: fetch is replaced by _x_fetch_mock.mjs and only fake keys or the
# published docs.x.com signature example are used. Checks:
#   - every script parses (node --check)
#   - OAuth 1.0a signature against the docs.x.com "Creating a signature" example
#   - OAuth 2.0 still reads ~/.env, refreshes and re-saves rotated tokens
#   - process env wins over ~/.env; refresh refused (clear message) when it could not be saved
#   - OAuth 1.0a requests are signed (query in, JSON body out); OAuth 2.0-only commands refused
#
# Run locally:
#   bash claude-skills/tests/test_x_skill.sh
#
# Exit 0 = all pass, exit 1 = failure.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SKILL_DIR="$SCRIPT_DIR/../skills/x/scripts"

command -v node >/dev/null || { echo "FAIL  node not found"; exit 1; }

fail=0
for f in "$SKILL_DIR"/*.mjs; do
  if node --check "$f"; then echo "PASS  node --check $(basename "$f")"; else echo "FAIL  node --check $(basename "$f")"; fail=1; fi
done

node "$SCRIPT_DIR/_x_skill_checks.mjs" || fail=1
exit $fail
