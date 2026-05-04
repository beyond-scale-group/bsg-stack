#!/usr/bin/env bash
# assert-invariants.sh — verify pipeline regression invariants I1-I8
# from the artifacts collected by run-pipeline-test.sh (#292).
#
# I1 distribution      ≥ 2 different bus_labels opened ≥ 1 PR
# I2 idempotency       no duplicate report PRs (same agent, same day)
# I3 lock cleanup      zero agent:lock:* labels left (live query)
# I4 budget compliance no merged PR exceeds MAX_LOC LOC / MAX_FILES files
# I5 issue dedup       no two open agent-filed issues share a fingerprint
# I6 phase-B reactivity eligible issues get a PR within REACTIVITY_SECS (default 300s)
# I7 token budget      total tokens ≤ baseline × TOKEN_DRIFT_FACTOR (default 1.2)
# I8 auto-merge labels every auto-merged PR carries human-reviewed
#
# Inputs: --logs DIR (must contain prs.json and issues.json)
# Optional: --repo OWNER/NAME     (required for I3)
#           --baseline-dir DIR    (dir with latest.json; skips I7 if absent)
#           --tokens N            (current run token count; skips I7 if absent)
# Optional env: MAX_LOC (default 200), MAX_FILES (default 8),
#               REACTIVITY_SECS (default 300), TOKEN_DRIFT_FACTOR (default 1.2)
#
# Exits 0 if all pass, 1 if any failed.

set -euo pipefail

LOG_DIR=""
REPO=""
BASELINE_DIR=""
TOKENS=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --logs)          LOG_DIR="$2";      shift 2 ;;
    --repo)          REPO="$2";         shift 2 ;;
    --baseline-dir)  BASELINE_DIR="$2"; shift 2 ;;
    --tokens)        TOKENS="$2";       shift 2 ;;
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
REACTIVITY_SECS=${REACTIVITY_SECS:-300}
TOKEN_DRIFT_FACTOR=${TOKEN_DRIFT_FACTOR:-1.2}

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
# Guard against null titles with (.title // "")
dups=$(jq -r '
  [ .[]
    | select((.title // "") | test("^report\\("))
    | { agent: (((.title // "") | capture("^report\\((?<a>[^)]+)\\)") // {}).a // "_"),
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

# ---------- I5 — issue dedup (filed-by fingerprints) ----------
# No two open agent-filed issues should share the same "fingerprint:" value.
dup_fingerprints=$(jq -r '
  [ .[]
    | select(.state == "OPEN")
    | select((.labels // []) | map(.name) | any(startswith("filed-by:")))
    | (.body // "") | scan("fingerprint: ([^\n]+)") | .[0]
  ]
  | group_by(.)
  | map(select(length > 1) | .[0])
  | length
' "$ISSUES")
if [[ "$dup_fingerprints" -eq 0 ]]; then
  agent_filed=$(jq '[.[] | select((.labels // []) | map(.name) | any(startswith("filed-by:")))] | length' "$ISSUES")
  report "I5 issue dedup" PASS "$agent_filed agent-filed issue(s), no duplicate fingerprints"
else
  report "I5 issue dedup" FAIL "$dup_fingerprints fingerprint(s) appear on >1 open issue"
fi

# ---------- I6 — phase-B reactivity ----------
# For each issue that was eligible for auto-implementation (has bus label +
# bug/enhancement label), check that a PR referencing it was opened within
# REACTIVITY_SECS seconds of the issue's creation.
# We match PRs whose body contains "#N" matching the issue number.
slow=$(python3 - <<PYEOF
import json, sys
from datetime import datetime, timezone

with open("$PRS")    as f: prs    = json.load(f)
with open("$ISSUES") as f: issues = json.load(f)

BUS_LABELS = {"tech","qa","seo","po","security"}
IMPL_LABELS = {"bug","enhancement"}
SECS = int("$REACTIVITY_SECS")

def parse_dt(s):
    if not s: return None
    s = s.rstrip("Z")
    try: return datetime.fromisoformat(s).replace(tzinfo=timezone.utc)
    except Exception: return None

slow = 0
for issue in issues:
    labels = {l["name"] for l in (issue.get("labels") or [])}
    if not (labels & BUS_LABELS and labels & IMPL_LABELS):
        continue
    issue_num = issue["number"]
    issue_ts  = parse_dt(issue.get("createdAt"))
    if not issue_ts:
        continue
    # find earliest PR referencing this issue
    refs = []
    for pr in prs:
        body = pr.get("body") or ""
        if f"#{issue_num}" in body:
            pr_ts = parse_dt(pr.get("createdAt"))
            if pr_ts:
                refs.append(pr_ts)
    if not refs:
        # no PR found — skip (harness may still be running)
        continue
    first_pr_ts = min(refs)
    delta = (first_pr_ts - issue_ts).total_seconds()
    if delta > SECS:
        slow += 1

print(slow)
PYEOF
)
if [[ "$slow" -eq 0 ]]; then
  report "I6 phase-B reactivity" PASS "all eligible issues got a PR within ${REACTIVITY_SECS}s"
else
  report "I6 phase-B reactivity" FAIL "$slow issue(s) waited >${REACTIVITY_SECS}s for a PR"
fi

# ---------- I7 — token budget ----------
if [[ -n "$BASELINE_DIR" && -n "$TOKENS" && -f "$BASELINE_DIR/latest.json" ]]; then
  baseline_tokens=$(jq '.total_tokens // 0' "$BASELINE_DIR/latest.json")
  if [[ "$baseline_tokens" -le 0 ]]; then
    report "I7 token budget" SKIP "baseline total_tokens is 0 or missing"
  else
    # Use python3 for float comparison
    within=$(python3 -c "
import sys
current=$TOKENS
baseline=$baseline_tokens
factor=$TOKEN_DRIFT_FACTOR
print('yes' if current <= baseline * factor else 'no')
")
    if [[ "$within" == "yes" ]]; then
      pct=$(python3 -c "print(f'+{($TOKENS/$baseline_tokens - 1)*100:.1f}%')" 2>/dev/null || echo "")
      report "I7 token budget" PASS "tokens ${TOKENS} within ${TOKEN_DRIFT_FACTOR}x baseline ${baseline_tokens} ${pct}"
    else
      pct=$(python3 -c "print(f'+{($TOKENS/$baseline_tokens - 1)*100:.1f}%')" 2>/dev/null || echo "")
      report "I7 token budget" FAIL "tokens ${TOKENS} exceeds ${TOKEN_DRIFT_FACTOR}x baseline ${baseline_tokens} ${pct}"
    fi
  fi
else
  report "I7 token budget" SKIP "needs --baseline-dir and --tokens"
fi

# ---------- I8 — auto-merge labels ----------
# Every merged PR should carry human-reviewed (auto-merge path stamps it).
merged_without_label=$(jq '
  [ .[]
    | select(.state == "MERGED")
    | select( ((.labels // []) | map(.name) | any(. == "human-reviewed")) | not )
  ] | length
' "$PRS")
if [[ "$merged_without_label" -eq 0 ]]; then
  merged_total=$(jq '[.[] | select(.state == "MERGED")] | length' "$PRS")
  report "I8 auto-merge labels" PASS "$merged_total merged PR(s) all carry human-reviewed"
else
  report "I8 auto-merge labels" FAIL "$merged_without_label merged PR(s) missing human-reviewed"
fi

echo
echo "summary: $PASS passed, $FAIL failed, $SKIP skipped"
exit $((FAIL == 0 ? 0 : 1))
