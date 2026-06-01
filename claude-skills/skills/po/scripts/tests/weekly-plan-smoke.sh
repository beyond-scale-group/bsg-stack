#!/usr/bin/env bash
# weekly-plan-smoke.sh — smoke test for scripts/weekly-plan.sh.
#
# Feeds a fake snapshot into the script (no `gh`, no `gws`) and asserts
# the JSON shape. Run from anywhere:
#
#   bash claude-skills/skills/po/scripts/tests/weekly-plan-smoke.sh
#
# Exit 0 = all pass, exit 1 = failure.

set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
SUT="$HERE/../weekly-plan.sh"

if [[ ! -x "$SUT" ]]; then
  echo "FAIL: $SUT not executable" >&2
  exit 1
fi

for bin in jq python3; do
  if ! command -v "$bin" >/dev/null 2>&1; then
    echo "SKIP: $bin missing" >&2
    exit 0
  fi
done

PASS=0
FAIL=0

assert() {
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

snap=$(mktemp)
trap 'rm -f "$snap"' EXIT

cat > "$snap" <<'JSON'
{
  "repo": "beyond-scale-group/bsg-lbo",
  "generatedAt": "2026-06-01T08:00:00Z",
  "issues": [
    {"number": 181, "title": "Avocat LOI bloqué",
     "url": "https://github.com/beyond-scale-group/bsg-lbo/issues/181",
     "state": "OPEN", "labels": ["P0", "blocker"], "assignees": []},
    {"number": 132, "title": "Envoyer LOI DIPOLE",
     "url": "https://github.com/beyond-scale-group/bsg-lbo/issues/132",
     "state": "OPEN", "labels": ["urgent"], "assignees": ["g-dumas"]},
    {"number": 99, "title": "Refacto modèle valuation",
     "url": "https://github.com/beyond-scale-group/bsg-lbo/issues/99",
     "state": "OPEN", "labels": ["P1", "epic"], "assignees": []},
    {"number": 88, "title": "Relance cédant ALPHA",
     "url": "https://github.com/beyond-scale-group/bsg-lbo/issues/88",
     "state": "OPEN", "labels": ["outreach"], "assignees": []},
    {"number": 44, "title": "Already closed",
     "url": "https://github.com/beyond-scale-group/bsg-lbo/issues/44",
     "state": "CLOSED", "labels": [], "assignees": []}
  ],
  "pullRequests": [
    {"number": 200, "title": "Fix typo",
     "url": "https://github.com/beyond-scale-group/bsg-lbo/pull/200",
     "state": "OPEN", "isDraft": false, "labels": [],
     "reviewDecision": "REVIEW_REQUIRED"}
  ],
  "milestones": []
}
JSON

# Pin a known Monday so the assertions are stable.
out=$(bash "$SUT" --snapshot "$snap" --start 2026-06-01)

# --- shape -----------------------------------------------------------------
assert "top-level repo"      "beyond-scale-group/bsg-lbo" "$(jq -r '.repo' <<<"$out")"
assert "top-level repoShort" "bsg-lbo"                    "$(jq -r '.repoShort' <<<"$out")"
assert "top-level repoUrl"   "https://github.com/beyond-scale-group/bsg-lbo" "$(jq -r '.repoUrl' <<<"$out")"
assert "weekIso"             "2026-W23"                   "$(jq -r '.weekIso' <<<"$out")"
assert "exactly 5 days"      "5"                          "$(jq '.days | length' <<<"$out")"

# --- per-day basics --------------------------------------------------------
assert "Monday date"   "2026-06-01" "$(jq -r '.days[0].date'  <<<"$out")"
assert "Friday date"   "2026-06-05" "$(jq -r '.days[4].date'  <<<"$out")"
assert "Monday label"  "Lun 1/6"    "$(jq -r '.days[0].label' <<<"$out")"
assert "Monday priority" "P0"       "$(jq -r '.days[0].priority' <<<"$out")"
assert "Friday priority" "PR-REVIEW" "$(jq -r '.days[4].priority' <<<"$out")"

# --- heuristics ------------------------------------------------------------
# P0/blocker #181 lands Monday/Tuesday (first slot is Monday).
assert "P0 issue routed to Mon" \
  "181" \
  "$(jq -r '.days[0].tasks[] | select(.kind == "issue") | .issue' <<<"$out" | head -n1)"

# Closed issues should NOT appear anywhere.
assert "closed issue absent" \
  "0" \
  "$(jq '[.days[].tasks[].issue] | map(select(. == 44)) | length' <<<"$out")"

# PR review batch -> Friday only.
assert "PR review on Friday" \
  "200" \
  "$(jq -r '.days[4].tasks[] | select(.kind == "pr-review") | .issue' <<<"$out")"

assert "no PR review before Friday" \
  "0" \
  "$(jq '[.days[0:4][].tasks[] | select(.kind == "pr-review")] | length' <<<"$out")"

# Every task must carry the four documented keys.
missing_keys=$(jq '[.days[].tasks[]
  | select((has("issue") and has("title") and has("url") and has("action") and has("kind")) | not)
] | length' <<<"$out")
assert "all tasks have required keys" "0" "$missing_keys"

# Report path defaulting: must look like po/reports/YYYY-MM-DD-weekly-plan-sNN.md
report=$(jq -r '.reportPath' <<<"$out")
if [[ "$report" =~ ^po/reports/[0-9]{4}-[0-9]{2}-[0-9]{2}-weekly-plan-s[0-9]{2}\.md$ ]]; then
  PASS=$((PASS + 1))
else
  FAIL=$((FAIL + 1))
  echo "FAIL: reportPath shape"
  echo "  got: $report"
fi

# --- weekday name resolution: --start FRI from a Monday should give that Friday
out2=$(bash "$SUT" --snapshot "$snap" --start FRI 2>/dev/null) || true
# Just check it produced 5 days and starts on a Friday-formatted label.
n=$(jq '.days | length' <<<"$out2")
assert "FRI start: 5 days" "5" "$n"
fri_label=$(jq -r '.days[0].label' <<<"$out2")
case "$fri_label" in
  Ven\ *) PASS=$((PASS + 1)) ;;
  *)
    FAIL=$((FAIL + 1))
    echo "FAIL: --start FRI: expected first day label to start with 'Ven '"
    echo "  got: $fri_label"
    ;;
esac

echo ""
echo "PASS: $PASS, FAIL: $FAIL"
[[ $FAIL -eq 0 ]] || exit 1
