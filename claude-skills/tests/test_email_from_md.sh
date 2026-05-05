#!/usr/bin/env bash
# test_email_from_md.sh — unit tests for email-from-md.sh
#
# Tests:
#   - Table CSS inlining: <table> gets border-collapse styles
#   - <th> and <td> get border + padding styles
#   - <blockquote> gets left-border styles
#   - --no-signature flag skips signature fetch
#   - --markdown flag required (exits 1 without it)
#   - Output is valid HTML (contains <html> or table tags)
#
# Run locally:
#   bash claude-skills/tests/test_email_from_md.sh
#
# Exit 0 = all pass, exit 1 = failure.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SUT="$REPO_ROOT/claude-skills/skills/google-workspace/scripts/email-from-md.sh"

# Skip gracefully if pandoc is not available
if ! command -v pandoc &>/dev/null; then
  echo "SKIP: pandoc not available — skipping test_email_from_md.sh"
  exit 0
fi

TMPDIR_TEST="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_TEST"' EXIT

PASS=0
FAIL=0

assert_contains() {
  local label="$1" needle="$2" haystack="$3"
  if echo "$haystack" | grep -qF "$needle"; then
    echo "PASS: $label"
    PASS=$((PASS + 1))
  else
    echo "FAIL: $label — expected to find: $needle"
    FAIL=$((FAIL + 1))
  fi
}

assert_exit() {
  local label="$1" expected="$2"
  shift 2
  local actual=0
  "$@" &>/dev/null || actual=$?
  if [[ "$actual" -eq "$expected" ]]; then
    echo "PASS: $label"
    PASS=$((PASS + 1))
  else
    echo "FAIL: $label — expected exit $expected, got $actual"
    FAIL=$((FAIL + 1))
  fi
}

# ---- fixture markdown file ----
FIXTURE_MD="$TMPDIR_TEST/input.md"
cat > "$FIXTURE_MD" <<'MD'
# Hello

| Col A | Col B | Col C |
|-------|-------|-------|
| 1     | 2     | 3     |

> A blockquote here.

Some body text.
MD

# ---- Test 1: script exists ----
echo "--- Test 1: script exists ---"
if [[ -f "$SUT" ]]; then
  echo "PASS: script exists"
  PASS=$((PASS + 1))
else
  echo "FAIL: $SUT not found"
  FAIL=$((FAIL + 1))
fi

# ---- Test 2: --no-signature flag produces HTML output ----
echo "--- Test 2: --no-signature produces HTML ---"
OUTPUT=$(bash "$SUT" --markdown "$FIXTURE_MD" --no-signature 2>/dev/null)
assert_contains "T2: output contains <table" "<table" "$OUTPUT"

# ---- Test 3: table gets border-collapse CSS ----
echo "--- Test 3: table gets border-collapse style ---"
assert_contains "T3: border-collapse:collapse" "border-collapse:collapse" "$OUTPUT"

# ---- Test 4: <th> gets background style ----
echo "--- Test 4: <th> gets background style ---"
assert_contains "T4: th has background:#f4f4f4" "background:#f4f4f4" "$OUTPUT"

# ---- Test 5: <td> gets border style ----
echo "--- Test 5: <td> gets border style ---"
assert_contains "T5: td has border:1px solid" "border:1px solid" "$OUTPUT"

# ---- Test 6: blockquote gets border-left style ----
echo "--- Test 6: blockquote gets border-left style ---"
assert_contains "T6: blockquote has border-left" "border-left" "$OUTPUT"

# ---- Test 7: missing --markdown exits non-zero ----
echo "--- Test 7: missing --markdown exits 1 ---"
assert_exit "T7: no --markdown → exit 1" 1 bash "$SUT" --no-signature

# ---- Test 8: --markdown with nonexistent file exits non-zero ----
echo "--- Test 8: nonexistent file exits 1 ---"
assert_exit "T8: bad path → exit 1" 1 bash "$SUT" --markdown "/tmp/does-not-exist-$$.md" --no-signature

# ============================================================================
# Markdown coverage suite — verifies every common element survives the pipe
# with Gmail-friendly inline CSS attached.
# ============================================================================

COVERAGE_MD="$TMPDIR_TEST/coverage.md"
cat > "$COVERAGE_MD" <<'MD'
# H1
## H2
### H3
#### H4

A paragraph with **bold**, *italic*, ***both***, ~~strike~~,
`inline code`, and [a link](https://example.com).

---

* unordered
* with **markup**
  * nested
  * nested

1. first
2. second

> Quoted line.
> second line.

| Item | Qty |
|------|-----|
| Foo  | 12  |
| Bar  | 7   |

```bash
echo hello
```

![alt](https://example.com/img.png)

Term
:   Definition body.
MD

OUT=$(bash "$SUT" --markdown "$COVERAGE_MD" --no-signature 2>/dev/null)

echo "--- Coverage: every supported tag is emitted ---"
assert_contains "C1:  <h1> emitted"          "<h1"          "$OUT"
assert_contains "C2:  <h2> emitted"          "<h2"          "$OUT"
assert_contains "C3:  <h3> emitted"          "<h3"          "$OUT"
assert_contains "C4:  <h4> emitted"          "<h4"          "$OUT"
assert_contains "C5:  <strong> for **bold**" "<strong>"     "$OUT"
assert_contains "C6:  <em> for *italic*"     "<em>"         "$OUT"
assert_contains "C7:  <del> for ~~strike~~"  "<del>"        "$OUT"
assert_contains "C8:  <code> for inline"     "<code"        "$OUT"
assert_contains "C9:  <a href> for link"     'href="https://example.com"' "$OUT"
assert_contains "C10: <hr> for ---"          "<hr"          "$OUT"
assert_contains "C11: <ul> for unordered"    "<ul"          "$OUT"
assert_contains "C12: <ol> for ordered"      "<ol"          "$OUT"
assert_contains "C13: <li> for items"        "<li"          "$OUT"
assert_contains "C14: <blockquote> emitted"  "<blockquote"  "$OUT"
assert_contains "C15: <table> emitted"       "<table"       "$OUT"
assert_contains "C16: <thead> emitted"       "<thead"       "$OUT"
assert_contains "C17: <th> emitted"          "<th"          "$OUT"
assert_contains "C18: <tbody> emitted"       "<tbody"       "$OUT"
assert_contains "C19: <td> emitted"          "<td"          "$OUT"
assert_contains "C20: <pre> for fenced code" "<pre"         "$OUT"
assert_contains "C21: <img src> emitted"     'src="https://example.com/img.png"' "$OUT"
assert_contains "C22: <dl> for def list"     "<dl"          "$OUT"
assert_contains "C23: <dt> for def term"     "<dt"          "$OUT"
assert_contains "C24: <dd> for def body"     "<dd"          "$OUT"

echo "--- Coverage: every supported tag has Gmail-friendly inline CSS ---"
# Re-using assert_contains with regex would require grep -E, so we anchor on
# unique style fragments per tag instead.
assert_contains "S1:  table has border-collapse"  "border-collapse:collapse" "$OUT"
assert_contains "S2:  th has background"          "background:#f4f4f4"       "$OUT"
assert_contains "S3:  td has padding"             "padding:8px 10px"         "$OUT"
assert_contains "S4:  blockquote has border-left" "border-left:3px solid"    "$OUT"
assert_contains "S5:  h1 has size 24px"           "font-size:24px"           "$OUT"
assert_contains "S6:  h2 has size 20px"           "font-size:20px"           "$OUT"
assert_contains "S7:  pre has monospace bg"       "background:#f6f8fa"       "$OUT"
assert_contains "S8:  code has Menlo font"        "font-family:Menlo"        "$OUT"
assert_contains "S9:  hr has border-top"          "border-top:1px solid"     "$OUT"
assert_contains "S10: ul has padding-left"        "padding-left:24px"        "$OUT"
assert_contains "S11: img has max-width"          "max-width:100%"           "$OUT"
assert_contains "S12: dt has bold"                "font-weight:600"          "$OUT"

echo "--- Coverage: regression — no duplicated style=\"…\" attributes ---"
# `grep` returns 1 when no matches, so guard the pipeline against pipefail.
DUPES=$( { printf '%s' "$OUT" | grep -oE 'style="[^"]*" style="[^"]*"' || true; } | wc -l | tr -d ' ')
if [[ "$DUPES" -eq 0 ]]; then
  echo "PASS: D1: zero duplicate style= attributes (was buggy on <th>/<td>)"
  PASS=$((PASS + 1))
else
  echo "FAIL: D1: $DUPES duplicate style= attributes detected"
  FAIL=$((FAIL + 1))
fi

echo "--- Coverage: pandoc syntax-highlighting spans are stripped ---"
# `--no-highlight` should suppress the <span class="kw"> et al pollution.
HL_SPANS=$( { printf '%s' "$OUT" | grep -cE '<span class="(kw|st|fu|at|bu|dt|cf|op|co)"' || true; } | tr -d ' ')
if [[ "$HL_SPANS" -eq 0 ]]; then
  echo "PASS: D2: no syntax-highlighting class spans"
  PASS=$((PASS + 1))
else
  echo "FAIL: D2: $HL_SPANS syntax-highlighting spans leaked through"
  FAIL=$((FAIL + 1))
fi

echo "--- Coverage: <figcaption> wrapper is stripped (Gmail orphan-text fix) ---"
if printf '%s' "$OUT" | grep -q '<figcaption'; then
  echo "FAIL: D3: <figcaption> still present in output"
  FAIL=$((FAIL + 1))
else
  echo "PASS: D3: <figcaption> stripped"
  PASS=$((PASS + 1))
fi

# ---------- Summary ----------
echo ""
echo "=== $((PASS + FAIL)) tests: $PASS passed, $FAIL failed ==="
[[ "$FAIL" -eq 0 ]]
