#!/usr/bin/env bash
# test_google_apps_script.sh — unit tests for the google-apps-script skill
# scripts (onboard.sh, doctor.sh).
#
# All tests run **offline** — no network calls, no clasp login. They verify:
#   - scripts exist and are executable
#   - --step routing works (unknown step → exit 1)
#   - --quiet flag on doctor suppresses output
#   - doctor detects missing binary (via PATH override)
#   - doctor detects missing credentials (via HOME override)
#   - doctor reports healthy when binary + credentials are present (mocked)
#   - onboard.sh --step verify detects missing binary
#   - SKILL.md frontmatter contains required fields
#
# Run locally:
#   bash claude-skills/tests/test_google_apps_script.sh
#
# Exit 0 = all pass, exit 1 = failure.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SKILL_DIR="$REPO_ROOT/claude-skills/skills/google-apps-script"
DOCTOR="$SKILL_DIR/scripts/doctor.sh"
ONBOARD="$SKILL_DIR/scripts/onboard.sh"
PREFLIGHT="$SKILL_DIR/scripts/preflight.sh"
SKILL_MD="$SKILL_DIR/SKILL.md"

TMPDIR_TEST="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_TEST"' EXIT

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
  if printf '%s' "$haystack" | grep -qF -e "$needle"; then
    echo "PASS: $label"
    PASS=$((PASS + 1))
  else
    echo "FAIL: $label — expected to find: $needle"
    FAIL=$((FAIL + 1))
  fi
}

assert_not_contains() {
  local label="$1" needle="$2" haystack="$3"
  if ! printf '%s' "$haystack" | grep -qF -e "$needle"; then
    echo "PASS: $label"
    PASS=$((PASS + 1))
  else
    echo "FAIL: $label — expected NOT to find: $needle"
    FAIL=$((FAIL + 1))
  fi
}

# ---------- T1-T3: scripts exist & are executable ----------
echo "--- existence ---"
assert_exists "doctor.sh exists"  "$DOCTOR"
assert_exists "onboard.sh exists" "$ONBOARD"
if [[ -f "$SKILL_MD" ]]; then
  echo "PASS: SKILL.md exists"
  PASS=$((PASS + 1))
else
  echo "FAIL: SKILL.md exists — not found: $SKILL_MD"
  FAIL=$((FAIL + 1))
fi

# ---------- T4: SKILL.md has required frontmatter ----------
echo "--- SKILL.md frontmatter ---"
FRONTMATTER=$(sed -n '/^---$/,/^---$/p' "$SKILL_MD")
assert_contains "SKILL.md has name field"        "name:"        "$FRONTMATTER"
assert_contains "SKILL.md has description field"  "description:" "$FRONTMATTER"
assert_contains "SKILL.md name is correct"        "google-apps-script" "$FRONTMATTER"

# ---------- T5: SKILL.md has required footer ----------
echo "--- SKILL.md footer ---"
FOOTER=$(tail -20 "$SKILL_MD")
assert_contains "footer references canonical path" \
  "claude-skills/skills/google-apps-script/SKILL.md" "$FOOTER"
assert_contains "footer references bsg-stack" \
  "beyond-scale-group/bsg-stack" "$FOOTER"

# ---------- T6-T7: onboard.sh --step routing ----------
echo "--- onboard step routing ---"
assert_exit "onboard: unknown step → exit 1" 1 \
  bash "$ONBOARD" --step nonexistent

# ---------- T8-T10: doctor with missing clasp binary ----------
echo "--- doctor: missing binary detection ---"

# Build a PATH that has system tools + node/npm but NOT clasp.
# Since node and clasp may live in the same directory (/opt/homebrew/bin),
# we symlink only the binaries we need into a staging dir.
STAGING_BIN="$TMPDIR_TEST/staging-bin"
mkdir -p "$STAGING_BIN"
for bin in node npm; do
  real="$(command -v "$bin" 2>/dev/null || true)"
  [ -n "$real" ] && ln -sf "$real" "$STAGING_BIN/$bin"
done
NO_CLASP_PATH="$STAGING_BIN:/usr/bin:/bin:/usr/sbin:/sbin"

# doctor.sh should exit 2 when clasp is not in PATH
OUT=$(PATH="$NO_CLASP_PATH" HOME="$TMPDIR_TEST" bash "$DOCTOR" 2>&1) || true
EXIT_CODE=0
PATH="$NO_CLASP_PATH" HOME="$TMPDIR_TEST" bash "$DOCTOR" &>/dev/null || EXIT_CODE=$?
if [[ "$EXIT_CODE" -eq 2 ]]; then
  echo "PASS: doctor exits 2 when clasp missing"
  PASS=$((PASS + 1))
else
  echo "FAIL: doctor exits 2 when clasp missing — got exit $EXIT_CODE"
  FAIL=$((FAIL + 1))
fi

assert_contains "doctor reports clasp not found" "not found" "$OUT"

# ---------- T11: doctor --quiet suppresses output ----------
echo "--- doctor --quiet ---"
QUIET_OUT=$(PATH="$NO_CLASP_PATH" HOME="$TMPDIR_TEST" bash "$DOCTOR" --quiet 2>&1) || true
assert_not_contains "doctor --quiet suppresses checkmarks" "✓" "$QUIET_OUT"

# ---------- T12-T13: doctor with fake clasp present ----------
echo "--- doctor: mock binary detection ---"

# Create a fake clasp that prints a version
MOCK_BIN="$TMPDIR_TEST/mock-bin"
mkdir -p "$MOCK_BIN"
cat > "$MOCK_BIN/clasp" <<'MOCK'
#!/usr/bin/env bash
echo "1.0.0-mock"
MOCK
chmod +x "$MOCK_BIN/clasp"

# Create fake credentials
MOCK_HOME="$TMPDIR_TEST/mock-home"
mkdir -p "$MOCK_HOME"
echo '{"token":"fake"}' > "$MOCK_HOME/.clasprc.json"

# Merge mock clasp + system tools + node/npm into a single PATH
MERGE_PATH="$MOCK_BIN:/usr/bin:/bin:/usr/sbin:/sbin"
command -v node >/dev/null 2>&1 && MERGE_PATH="$MERGE_PATH:$(dirname "$(command -v node)")"
command -v npm  >/dev/null 2>&1 && MERGE_PATH="$MERGE_PATH:$(dirname "$(command -v npm)")"

MOCK_OUT=$(PATH="$MERGE_PATH" HOME="$MOCK_HOME" bash "$DOCTOR" 2>&1) || true
MOCK_EXIT=0
PATH="$MERGE_PATH" HOME="$MOCK_HOME" bash "$DOCTOR" &>/dev/null || MOCK_EXIT=$?

if [[ "$MOCK_EXIT" -eq 0 ]]; then
  echo "PASS: doctor exits 0 with clasp + creds present"
  PASS=$((PASS + 1))
else
  echo "FAIL: doctor exits 0 with clasp + creds present — got exit $MOCK_EXIT"
  FAIL=$((FAIL + 1))
fi

assert_contains "doctor reports clasp binary ok" "clasp binary" "$MOCK_OUT"
assert_contains "doctor reports credentials ok"  "credentials"  "$MOCK_OUT"

# ---------- T14: onboard --step verify with no clasp ----------
echo "--- onboard: verify detects missing binary ---"
assert_exit "onboard verify with no clasp → exit 2" 2 \
  env PATH="$NO_CLASP_PATH" HOME="$TMPDIR_TEST" bash "$ONBOARD" --step verify

# ---------- T15: onboard --step install when clasp exists ----------
echo "--- onboard: install with existing clasp ---"
INSTALL_OUT=$(PATH="$MERGE_PATH" HOME="$MOCK_HOME" bash "$ONBOARD" --step install 2>&1) || true
assert_contains "onboard install detects existing clasp" "already installed" "$INSTALL_OUT"

# ---------- T16: onboard --step login with existing creds ----------
echo "--- onboard: login with existing creds ---"
LOGIN_OUT=$(PATH="$MERGE_PATH" HOME="$MOCK_HOME" bash "$ONBOARD" --step login 2>&1) || true
assert_contains "onboard login detects existing creds" "credentials found" "$LOGIN_OUT"

# ---------- T17: preflight script exists ----------
echo "--- preflight ---"
assert_exists "preflight.sh exists" "$PREFLIGHT"

# ---------- T18: preflight passes with mock clasp + creds ----------
echo "--- preflight: healthy mock environment ---"
PF_OUT=$(PATH="$MERGE_PATH" HOME="$MOCK_HOME" bash "$PREFLIGHT" 2>&1) || true
PF_EXIT=0
PATH="$MERGE_PATH" HOME="$MOCK_HOME" bash "$PREFLIGHT" &>/dev/null || PF_EXIT=$?
if [[ "$PF_EXIT" -eq 0 ]]; then
  echo "PASS: preflight exits 0 with clasp + creds"
  PASS=$((PASS + 1))
else
  echo "FAIL: preflight exits 0 with clasp + creds — got exit $PF_EXIT"
  FAIL=$((FAIL + 1))
fi
assert_contains "preflight reports ready" "ready" "$PF_OUT"
assert_contains "preflight reports authenticated" "Authenticated" "$PF_OUT"

# ---------- T19: preflight auto-remediates missing clasp ----------
# When clasp is missing, preflight calls onboard --step install.
# Use a PATH with no npm so install can't succeed.
echo "--- preflight: auto-remediation on missing clasp ---"
NO_NPM_PATH="$TMPDIR_TEST/no-npm-bin:/usr/bin:/bin:/usr/sbin:/sbin"
mkdir -p "$TMPDIR_TEST/no-npm-bin"
assert_exit "preflight exits 2 when clasp missing and install fails" 2 \
  env PATH="$NO_NPM_PATH" HOME="$TMPDIR_TEST" bash "$PREFLIGHT"

# ---------- T20: preflight auto-remediates missing creds ----------
# clasp present but no ~/.clasprc.json — preflight calls onboard --step login.
# Without a real OAuth flow login will fail, so preflight should exit 2.
echo "--- preflight: auto-remediation on missing creds ---"
BARE_HOME="$TMPDIR_TEST/bare-home"
mkdir -p "$BARE_HOME"
# preflight calls onboard login, which calls `clasp login` — our mock
# clasp doesn't create .clasprc.json, so preflight should exit 2.
assert_exit "preflight exits 2 when creds missing and login fails" 2 \
  env PATH="$MERGE_PATH" HOME="$BARE_HOME" bash "$PREFLIGHT"

# ---------- T21: CLASP_AUTH env var respected by preflight ----------
echo "--- CLASP_AUTH multi-account ---"
ALT_CREDS="$TMPDIR_TEST/alt-account/.clasprc-alt.json"
mkdir -p "$(dirname "$ALT_CREDS")"
echo '{"token":"alt-fake"}' > "$ALT_CREDS"

PF_ALT_OUT=$(CLASP_AUTH="$ALT_CREDS" PATH="$MERGE_PATH" HOME="$TMPDIR_TEST/no-global-creds" bash "$PREFLIGHT" 2>&1) || true
PF_ALT_EXIT=0
CLASP_AUTH="$ALT_CREDS" PATH="$MERGE_PATH" HOME="$TMPDIR_TEST/no-global-creds" bash "$PREFLIGHT" &>/dev/null || PF_ALT_EXIT=$?

if [[ "$PF_ALT_EXIT" -eq 0 ]]; then
  echo "PASS: preflight exits 0 with CLASP_AUTH pointing to alt creds"
  PASS=$((PASS + 1))
else
  echo "FAIL: preflight exits 0 with CLASP_AUTH — got exit $PF_ALT_EXIT"
  FAIL=$((FAIL + 1))
fi
assert_contains "preflight reports alt creds file" "clasprc-alt.json" "$PF_ALT_OUT"

# ---------- T22: CLASP_AUTH respected by doctor ----------
echo "--- CLASP_AUTH in doctor ---"
DOC_ALT_OUT=$(CLASP_AUTH="$ALT_CREDS" PATH="$MERGE_PATH" HOME="$TMPDIR_TEST/no-global-creds" bash "$DOCTOR" 2>&1) || true
assert_contains "doctor reports alt creds file" "clasprc-alt.json" "$DOC_ALT_OUT"

# ---------- T23: CLASP_AUTH missing file triggers remediation ----------
MISSING_ALT="$TMPDIR_TEST/does-not-exist.json"
assert_exit "preflight exits 2 when CLASP_AUTH points to missing file" 2 \
  env CLASP_AUTH="$MISSING_ALT" PATH="$MERGE_PATH" HOME="$TMPDIR_TEST/no-global-creds" bash "$PREFLIGHT"

# ---------- summary ----------
echo ""
echo "=== $((PASS + FAIL)) tests: $PASS passed, $FAIL failed ==="
[[ "$FAIL" -eq 0 ]]
