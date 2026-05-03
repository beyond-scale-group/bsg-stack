#!/usr/bin/env bash
# test_no_needs_rework_in_peer_review.sh
#
# Asserts that no agent or CLAUDE.md peer review section instructs
# reviewers to apply the `needs-rework` label. Per issue #312, peer
# review is comment-only — the reviewer posts a comment with the rework
# rationale instead of applying a label.
#
# Exit 0 = pass, 1 = fail.

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"

AGENT_FILES=(
  "$REPO_ROOT/claude-skills/agents/tech-lead.md"
  "$REPO_ROOT/claude-skills/agents/qa.md"
  "$REPO_ROOT/claude-skills/agents/seo.md"
  "$REPO_ROOT/claude-skills/agents/po-manager.md"
  "$REPO_ROOT/claude-skills/agents/security.md"
)
CLAUDE_MD="$REPO_ROOT/CLAUDE.md"

failures=0

for f in "${AGENT_FILES[@]}" "$CLAUDE_MD"; do
  if grep -qn "needs-rework" "$f"; then
    echo "FAIL: needs-rework still referenced in $f"
    grep -n "needs-rework" "$f"
    failures=$((failures + 1))
  fi
done

if [[ $failures -eq 0 ]]; then
  echo "PASS: no needs-rework references found in peer review docs"
  exit 0
else
  echo "FAIL: $failures file(s) still reference needs-rework"
  exit 1
fi
