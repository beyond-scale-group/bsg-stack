#!/usr/bin/env bash
# assert-invariants.sh — verify pipeline regression invariants I1-I4
# from the artifacts collected by run-pipeline-test.sh (#292).
#
# I1 distribution      ≥ 2 different bus_labels opened ≥ 1 PR
# I2 idempotency       no duplicate report PRs (same agent, same day)
# I3 lock cleanup      zero agent:lock:* labels left (live query)
# I4 budget compliance no merged PR exceeds 200 LOC / 8 files
#
# Inputs: --logs DIR (must contain prs.json and issues.json)
# Optional: --repo OWNER/NAME (required for I3)
# Optional env: MAX_LOC (default 200), MAX_FILES (default 8)
#
# Exits 0 if all pass, 1 if any failed.

set -euo pipefail

LOG_DIR=""
REPO=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --logs) LOG_DIR="$2"; shift 2 ;;
    --repo) REPO="$2"; shift 2 ;;
    -h|--help) sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "assert-invariants: unknown arg: $1" >&2; exit 2 ;;
  esac
done

[[ -z "$LOG_DIR" || ! -d "$LOG_DIR" ]] && { echo "missing --logs DIR" >&2; exit 2; }

PRS="$LOG_DIR/prs.json"
ISSUES="$LOG_DIR/issues.json"
[[ ! -f "$PRS" || ! -f "$ISSUES" ]] && { echo "missing prs.json or issues.json in $LOG_DIR" >&2; exit 2; }

MAX_LOC=${MAX_LOC:-200}
MAX_FILES=${MAX_FILES:-8}

PASS=0
FAIL=0
SKIP=0
report() { # $1=name $2=status (PASS|FAIL|SKIP) $3=detail
  case "$2" in
    PASS) printf "  %-26s ✓  %s\n" "$1" "$3"; PASS=$((PASS + 1)) ;;
    FAIL) printf "  %-26s ✗  %s\n" "$1" "$3"; FAIL=$((FAIL + 1)) ;;
    SKIP) printf "  %-26s ·  %s\n" "$1" "$3"; SKIP=$((SKIP + 1)) ;;
  esac
}

# ---------- I1 — distribution ----------
buses_with_prs=$(jq -r '
  [ .[]
    | (.labels // []) | map(.name)
    | map(select(. == "tech" or . == "qa" or . == "seo" or . == "po" or . == "security"))
    | .[]
  ] | unique | length
' "$PRS")
if [[ "$buses_with_prs" -ge 2 ]]; then
  report "I1 distribution" PASS "$buses_with_prs buses opened PRs"
else
  report "I1 distribution" FAIL "only $buses_with_prs bus(es) opened PRs (expected ≥ 2)"
fi

# ---------- I2 — idempotency ----------
dups=$(jq -r '
  [ .[]
    | select(.title | test("^report\\("))
    | { agent: ((.title | capture("^report\\((?<a>[^)]+)\\)") // {}).a // "_"),
        day:    (.createdAt[:10]) }
  ]
  | group_by(.agent + "|" + .day)
  | map(select(length > 1))
  | length
' "$PRS")
if [[ "$dups" -eq 0 ]]; then
  report "I2 idempotency" PASS "no duplicate report PRs"
else
  report "I2 idempotency" FAIL "$dups duplicate report PR group(s)"
fi

# ---------- I3 — lock cleanup ----------
if [[ -n "$REPO" ]]; then
  leftover=0
  for agent in po security qa tech seo marketing storytelling pr-comms; do
    n=$(gh issue list --repo "$REPO" --label "agent:lock:$agent" --state open --json number --jq length 2>/dev/null || echo 0)
    leftover=$((leftover + n))
  done
  if [[ "$leftover" -eq 0 ]]; then
    report "I3 lock cleanup" PASS "no leftover agent:lock:* labels"
  else
    report "I3 lock cleanup" FAIL "$leftover issue(s) still locked"
  fi
else
  report "I3 lock cleanup" SKIP "needs --repo"
fi

# ---------- I4 — budget compliance ----------
violations=$(jq --argjson loc "$MAX_LOC" --argjson files "$MAX_FILES" '
  [ .[]
    | select(.state == "MERGED")
    | select( ((.additions + .deletions) > $loc) or (.changedFiles > $files) )
  ] | length
' "$PRS")
if [[ "$violations" -eq 0 ]]; then
  merged=$(jq '[.[] | select(.state == "MERGED")] | length' "$PRS")
  report "I4 budget compliance" PASS "$merged merged PR(s) within $MAX_LOC LOC / $MAX_FILES files"
else
  report "I4 budget compliance" FAIL "$violations merged PR(s) exceed budget"
fi

echo
echo "summary: $PASS passed, $FAIL failed, $SKIP skipped"
exit $((FAIL == 0 ? 0 : 1))
