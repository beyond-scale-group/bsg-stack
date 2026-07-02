#!/usr/bin/env bash
# test_tick_convergence.sh — the infinite-loop safety property of tick-fingerprint.sh.
#
# A recurring tick (per-agent /loop, /tick-all on /loop, /schedule) is only
# safe if a tick's own output is invisible to the next tick's fingerprint:
#
#   fp(state) == fp(state + own report PR merged + report commit on main)
#
# Without this, every landed report perturbs the input state, the next tick
# fails to short-circuit, generates another report, and the loop never
# reaches a fixed point — observed as duplicate same-day report PRs
# (#538/#540, #541/#542 on 2026-05-04).
#
# Mocks `gh` with a PATH shim that serves JSON fixtures through the
# caller-supplied --jq filter (so the exclusion logic in the real script's
# jq expression is what gets exercised), and uses a throwaway git repo for
# the HEAD-commit input.

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
TICK_FP="$SCRIPT_DIR/../scripts/tick-fingerprint.sh"

PASS=0
FAIL=0

assert_eq() {
  local label="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    echo "  PASS: $label"
    ((PASS++)) || true
  else
    echo "  FAIL: $label (expected='$expected', got='$actual')"
    ((FAIL++)) || true
  fi
}

assert_ne() {
  local label="$1" a="$2" b="$3"
  if [[ "$a" != "$b" ]]; then
    echo "  PASS: $label"
    ((PASS++)) || true
  else
    echo "  FAIL: $label (both '$a')"
    ((FAIL++)) || true
  fi
}

fingerprint() {
  bash "$TICK_FP" qa qa 2>/dev/null \
    | sed -n 's/^export TICK_FINGERPRINT=//p'
}

echo "=== test_tick_convergence.sh ==="

# ---------------------------------------------------------------- fixtures

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

export GH_FIXTURE_ISSUES="$WORK/issues.json"
export GH_FIXTURE_PRS="$WORK/prs.json"

cat > "$GH_FIXTURE_ISSUES" <<'EOF'
[
  {"number": 10, "state": "OPEN", "labels": [{"name": "bug"}, {"name": "tech"}]}
]
EOF

cat > "$GH_FIXTURE_PRS" <<'EOF'
[
  {"number": 1, "state": "MERGED", "headRefName": "feat/base"}
]
EOF

# gh shim: serve the fixture for the subcommand, applying the real --jq
# expression the caller passed, so the script's own filter is under test.
mkdir -p "$WORK/bin"
cat > "$WORK/bin/gh" <<'SHIM'
#!/usr/bin/env bash
sub="$1 $2"
jq_expr=""
prev=""
for a in "$@"; do
  [[ "$prev" == "--jq" ]] && jq_expr="$a"
  prev="$a"
done
case "$sub" in
  "issue list") src="$GH_FIXTURE_ISSUES" ;;
  "pr list")    src="$GH_FIXTURE_PRS" ;;
  *) echo "[]"; exit 0 ;;
esac
if [[ -n "$jq_expr" ]]; then jq "$jq_expr" "$src"; else cat "$src"; fi
SHIM
chmod +x "$WORK/bin/gh"
export PATH="$WORK/bin:$PATH"

# Throwaway repo for the HEAD-commit input.
git init -q "$WORK/repo"
cd "$WORK/repo"
git config user.email test@example.com
git config user.name "Convergence Test"
git commit -q --allow-empty -m "feat: base commit"

fp_base=$(fingerprint)
echo "Test 0: baseline fingerprint is a 16-char hex"
assert_eq "fingerprint shape" "16" "${#fp_base}"

# --- Test 1: a merged report PR must NOT change the fingerprint ----------
echo "Test 1: own report PR is invisible (convergence)"
cat > "$GH_FIXTURE_PRS" <<'EOF'
[
  {"number": 1, "state": "MERGED", "headRefName": "feat/base"},
  {"number": 2, "state": "MERGED", "headRefName": "reports/qa/2026-07-02T10-00-00-audit"}
]
EOF
assert_eq "fp unchanged after report PR merges" "$fp_base" "$(fingerprint)"

# --- Test 2: a real PR must change the fingerprint -----------------------
echo "Test 2: real PR state still triggers"
cat > "$GH_FIXTURE_PRS" <<'EOF'
[
  {"number": 1, "state": "MERGED", "headRefName": "feat/base"},
  {"number": 2, "state": "MERGED", "headRefName": "reports/qa/2026-07-02T10-00-00-audit"},
  {"number": 3, "state": "OPEN",   "headRefName": "fix/real-change"}
]
EOF
fp_real_pr=$(fingerprint)
assert_ne "fp changes on a non-report PR" "$fp_base" "$fp_real_pr"

# --- Test 3: a report commit on main must NOT change the fingerprint -----
echo "Test 3: report commit on main is invisible (convergence)"
git commit -q --allow-empty -m "report(qa): 2026-07-02T10-00-00-audit (#2)"
assert_eq "fp unchanged after report commit" "$fp_real_pr" "$(fingerprint)"

# --- Test 4: a real commit must change the fingerprint -------------------
echo "Test 4: real commit still triggers"
git commit -q --allow-empty -m "fix: actual code change"
assert_ne "fp changes on a non-report commit" "$fp_real_pr" "$(fingerprint)"

# --- Test 5: issue label churn still triggers (routing is real state) ----
echo "Test 5: issue label change still triggers"
fp_before_label=$(fingerprint)
cat > "$GH_FIXTURE_ISSUES" <<'EOF'
[
  {"number": 10, "state": "OPEN", "labels": [{"name": "bug"}, {"name": "tech"}, {"name": "needs:tech"}]}
]
EOF
assert_ne "fp changes when needs:tech is applied" "$fp_before_label" "$(fingerprint)"

echo ""
echo "=== $((PASS + FAIL)) tests: $PASS passed, $FAIL failed ==="
[[ "$FAIL" -eq 0 ]]
