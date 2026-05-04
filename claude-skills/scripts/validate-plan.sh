#!/usr/bin/env bash
# validate-plan.sh — validate po/PLAN.md and exit non-zero with a diagnostic
# when the plan is missing or contains no binding tags (E6-plan-schema-hygiene).
#
# Usage:
#   bash claude-skills/scripts/validate-plan.sh [--plan <path>]
#
# Exits:
#   0   — PLAN.md exists and contains at least one binding tag
#   1   — PLAN.md is missing
#   2   — PLAN.md exists but contains no binding tags (format drift)
#   3   — parse-plan.sh not found (installer misconfiguration)
#
# By default reads $PWD/po/PLAN.md. Override with --plan <path>.
#
# Uses parse-plan.sh --typed internally so the same grammar is enforced
# in both the agent tick and this standalone validator.
set -euo pipefail

PLAN_PATH=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --plan) PLAN_PATH="$2"; shift 2 ;;
    *) echo "validate-plan.sh: unknown argument: $1" >&2; exit 2 ;;
  esac
done

if [[ -z "$PLAN_PATH" ]]; then
  PLAN_PATH="$PWD/po/PLAN.md"
fi

# Locate parse-plan.sh: prefer the canonical repo path, fall back to cached copy.
PARSE_PLAN=""
for candidate in \
  "$(dirname "$0")/../skills/po/scripts/parse-plan.sh" \
  "$HOME/.claude/skills/po/scripts/parse-plan.sh"; do
  if [[ -f "$candidate" ]]; then
    PARSE_PLAN="$candidate"
    break
  fi
done

if [[ -z "$PARSE_PLAN" ]]; then
  echo "validate-plan.sh: parse-plan.sh not found — is the BSG skill catalog installed?" >&2
  echo "  Expected at: $(dirname "$0")/../skills/po/scripts/parse-plan.sh" >&2
  echo "  or:          \$HOME/.claude/skills/po/scripts/parse-plan.sh" >&2
  exit 3
fi

# Run the typed parser to get a structured result.
result=$(bash "$PARSE_PLAN" --plan "$PLAN_PATH" --typed 2>&1)
exit_code=$?

if [[ $exit_code -ne 0 ]]; then
  echo "validate-plan.sh: parse-plan.sh exited $exit_code — check $PLAN_PATH" >&2
  echo "$result" >&2
  exit 1
fi

status=$(printf '%s' "$result" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('status','unknown'))" 2>/dev/null || echo "parse-error")

case "$status" in
  ok)
    item_count=$(printf '%s' "$result" | python3 -c "import json,sys; d=json.load(sys.stdin); print(len(d.get('items',[])))" 2>/dev/null || echo "0")
    echo "validate-plan.sh: OK — $PLAN_PATH has $item_count bound plan item(s)"
    exit 0
    ;;
  missing)
    reason=$(printf '%s' "$result" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('reason','plan file missing'))" 2>/dev/null || echo "plan file missing")
    echo "validate-plan.sh: MISSING — $reason" >&2
    echo "  To fix: create $PLAN_PATH following the schema in" >&2
    echo "  claude-skills/skills/po/references/plan-schema.md" >&2
    exit 1
    ;;
  unparseable)
    reason=$(printf '%s' "$result" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('reason','no binding tags found'))" 2>/dev/null || echo "no binding tags found")
    echo "validate-plan.sh: INVALID — $reason" >&2
    echo "  To fix: ensure bullets carry at least one binding tag, e.g.:" >&2
    echo "    - Ship feature X   [milestone:M1]" >&2
    echo "  See claude-skills/skills/po/references/plan-schema.md for the grammar." >&2
    exit 2
    ;;
  *)
    echo "validate-plan.sh: UNKNOWN parse status '$status' — raw output:" >&2
    echo "$result" >&2
    exit 2
    ;;
esac
