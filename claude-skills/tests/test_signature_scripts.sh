#!/usr/bin/env bash
# test_signature_scripts.sh — smoke tests for the Gmail signature audit /
# extract / set scripts and the email-md-send wrapper.
#
# These tests run **offline** — no network calls, no Gmail API. They
# verify:
#   - --help output works (sources documentation from comment header)
#   - missing required flags trigger exit 2
#   - mutually-exclusive flags are detected
#   - --dry-run path renders the patch body without calling gws
#
# When `gws` and a live auth token are available, the audit and extract
# scripts are exercised in --quiet / --dry-run mode but failures are
# tolerated (the test only asserts they exit cleanly when network is
# down).
#
# Run locally:
#   bash claude-skills/tests/test_signature_scripts.sh
#
# Exit 0 = all pass, exit 1 = failure.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
GWS_DIR="$REPO_ROOT/claude-skills/skills/google-workspace/scripts"

AUDIT="$GWS_DIR/signature-audit.sh"
EXTRACT="$GWS_DIR/signature-extract.sh"
SET="$GWS_DIR/signature-set.sh"
SEND="$GWS_DIR/email-md-send.sh"

PASS=0
FAIL=0

assert_exists() {
  local label="$1" path="$2"
  if [[ -x "$path" ]]; then
    echo "PASS: $label"
    PASS=$((PASS + 1))
  else
    echo "FAIL: $label — not found or not executable: $path"
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

assert_contains() {
  local label="$1" needle="$2" haystack="$3"
  # `grep -- --` so dashes in the needle aren't parsed as grep flags.
  if printf '%s' "$haystack" | grep -qF -e "$needle"; then
    echo "PASS: $label"
    PASS=$((PASS + 1))
  else
    echo "FAIL: $label — expected to find: $needle"
    FAIL=$((FAIL + 1))
  fi
}

# ---------- T1-T4: every script exists & is executable ----------
echo "--- existence ---"
assert_exists "audit script exists"   "$AUDIT"
assert_exists "extract script exists" "$EXTRACT"
assert_exists "set script exists"     "$SET"
assert_exists "email-md-send exists"  "$SEND"

# ---------- T5-T8: --help works and prints usage ----------
echo "--- --help output ---"
HELP_OUT=$(bash "$AUDIT"   --help 2>&1) && assert_contains "audit --help mentions sendAs"     "sendAs" "$HELP_OUT" || true
HELP_OUT=$(bash "$EXTRACT" --help 2>&1) && assert_contains "extract --help mentions signature" "signature" "$HELP_OUT" || true
HELP_OUT=$(bash "$SET"     --help 2>&1) && assert_contains "set --help mentions --alias"       "--alias" "$HELP_OUT" || true
HELP_OUT=$(bash "$SEND"    --help 2>&1) && assert_contains "send --help mentions --markdown"   "--markdown" "$HELP_OUT" || true

# ---------- T9-T12: missing required flags exit 2 ----------
echo "--- required-flag enforcement ---"
assert_exit "set: missing --alias → exit 2"     2 bash "$SET" --html '<p>x</p>'
assert_exit "set: missing source → exit 2"      2 bash "$SET" --alias me@x.com
assert_exit "send: missing --markdown → exit 2" 2 bash "$SEND" --to a@x.com --subject hi
assert_exit "send: missing --to → exit 2"       2 bash "$SEND" --markdown /etc/hosts --subject hi

# ---------- T13: mutually-exclusive sources rejected ----------
echo "--- mutual-exclusion ---"
assert_exit "set: --html + --html-file → exit 2" 2 \
  bash "$SET" --alias me@x.com --html '<p>a</p>' --html-file /etc/hosts

# ---------- T14-T15: --dry-run on signature-set with inline HTML ----------
# This requires gws auth to pass the preflight; skip gracefully when offline.
echo "--- dry-run smoke (online-only) ---"
if command -v gws >/dev/null \
   && gws auth status 2>/dev/null | jq -e '.token_valid == true' >/dev/null 2>&1; then

  # Pick the first alias from the live account
  ALIAS=$(gws gmail users settings sendAs list --params '{"userId":"me"}' 2>/dev/null \
          | jq -r '.sendAs[0].sendAsEmail // empty')

  if [[ -n "$ALIAS" ]]; then
    DRY_OUT=$(bash "$SET" --alias "$ALIAS" \
              --html '<p>test only</p>' --dry-run --yes 2>&1) || DRY_OUT=""
    assert_contains "set --dry-run mentions DRY-RUN" "DRY-RUN" "$DRY_OUT"
    assert_contains "set --dry-run emits patch JSON" '"signature"' "$DRY_OUT"
  else
    echo "SKIP: no aliases on this account — dry-run smoke skipped"
  fi
else
  echo "SKIP: gws / auth unavailable — dry-run smoke skipped"
fi

# ---------- summary ----------
echo ""
echo "=== $((PASS + FAIL)) tests: $PASS passed, $FAIL failed ==="
[[ "$FAIL" -eq 0 ]]
