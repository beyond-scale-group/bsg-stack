#!/usr/bin/env bash
# test_gog_scripts.sh — offline tests for the gog-based google-workspace scripts.
#
# A fake `gog` (injected through GOG_BIN) records its argv and answers with
# fixture JSON, so we can assert the exact commands the scripts build and that
# their jq parsing still fits the Google API shapes — no network, no auth.
#
# Also guards the migration: no script may call the old `gws` CLI again.
#
# Run locally:
#   bash claude-skills/tests/test_gog_scripts.sh
#
# Exit 0 = all pass, exit 1 = failure.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
GW_DIR="$REPO_ROOT/claude-skills/skills/google-workspace/scripts"
PO_DIR="$REPO_ROOT/claude-skills/skills/po/scripts"

for bin in jq python3; do
  command -v "$bin" >/dev/null 2>&1 || { echo "SKIP: $bin missing"; exit 0; }
done

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
export GOG_LOG="$WORK/gog.log"
export GOG_BIN="$WORK/gog"
export GOG_ACCOUNT="me@x.com"
: > "$GOG_LOG"

# ---------- fake gog ----------
cat > "$GOG_BIN" <<'FAKE'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$GOG_LOG"
case "$*" in
  --version*)
    echo "v0.42.0 (fake)" ;;
  *"auth status"*)
    echo '{"account":{"email":"me@x.com","credentials_exists":true,"credentials_path":""}}' ;;
  *"auth doctor"*)
    echo '{"status":"ok","checks":[{"name":"refresh.default.me@x.com","status":"ok"}]}' ;;
  *"users.settings.sendAs.list"*)
    echo '{"sendAs":[
      {"sendAsEmail":"me@x.com","displayName":"Me","isPrimary":true,"isDefault":true,"signature":"<div>Me <a href=\"https://x.com\">x.com</a></div>"},
      {"sendAsEmail":"alias@x.com","displayName":"Alias","isPrimary":false,"isDefault":false,"signature":""}]}' ;;
  *"users.settings.sendAs.get"*)
    echo '{"sendAsEmail":"alias@x.com","signature":""}' ;;
  *"events.list"*)
    echo "${FAKE_EVENTS:-{\"items\":[]}}" ;;
  *"gmail settings sendas update"*)
    echo '{"sendAsEmail":"alias@x.com","signature":"<p>new</p>"}' ;;
  *)
    echo '{}' ;;
esac
FAKE
chmod +x "$GOG_BIN"

PASS=0
FAIL=0
ok()   { echo "PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "FAIL: $1"; FAIL=$((FAIL + 1)); }

assert_contains() {
  local label="$1" needle="$2" haystack="$3"
  if printf '%s' "$haystack" | grep -qF -e "$needle"; then ok "$label"; else fail "$label — expected: $needle"; fi
}

# ---------- no gws left ----------
echo "--- no gws calls ---"
LEFT=$(grep -rnwE 'gws' "$GW_DIR" "$PO_DIR" 2>/dev/null | grep -vE 'GWS_(PROJECT_ID|USER_EMAIL)' || true)
if [[ -z "$LEFT" ]]; then ok "scripts never call gws"; else fail "gws still referenced:"; echo "$LEFT"; fi
[[ ! -e "$GW_DIR/gws-switch.sh" ]] && ok "gws-switch.sh removed" || fail "gws-switch.sh still present"

# ---------- _gog.sh helpers ----------
echo "--- _gog.sh ---"
OUT=$(bash -c "source '$GW_DIR/_gog.sh'; gog_require && gog_auth_ok && gog_account" 2>&1)
assert_contains "gog_require + gog_auth_ok + gog_account" "me@x.com" "$OUT"

OLD="$WORK/old"
printf '#!/usr/bin/env bash\necho "v0.9.0 (fake)"\n' > "$OLD"; chmod +x "$OLD"
GOG_BIN="$OLD" bash -c "source '$GW_DIR/_gog.sh'; gog_require" >/dev/null 2>&1; RC=$?
[[ "$RC" -eq 3 ]] && ok "gog_require rejects gog < 0.42 (exit 3)" || fail "gog_require old version: exit $RC"

# ---------- signature-audit ----------
echo "--- signature-audit ---"
OUT=$(bash "$GW_DIR/signature-audit.sh" --format json 2>&1); RC=$?
assert_contains "audit lists both aliases" '"total_aliases": 2' "$OUT"
assert_contains "audit flags the missing signature" '"missing_signature_count": 1' "$OUT"
[[ "$RC" -eq 1 ]] && ok "audit exits 1 when a signature is missing" || fail "audit exit code $RC"
assert_contains "audit called sendAs.list via gog api" "api call gmail v1 users.settings.sendAs.list" "$(cat "$GOG_LOG")"

# ---------- signature-set ----------
echo "--- signature-set ---"
OUT=$(bash "$GW_DIR/signature-set.sh" --alias alias@x.com --html '<p>new</p>' --dry-run 2>&1)
assert_contains "set --dry-run names the gog command" "gog gmail settings sendas update alias@x.com" "$OUT"
: > "$GOG_LOG"
bash "$GW_DIR/signature-set.sh" --alias alias@x.com --html '<p>new</p>' --display-name Al --yes >/dev/null 2>&1
LOG=$(cat "$GOG_LOG")
assert_contains "set applies via sendas update" "gmail settings sendas update alias@x.com --signature <p>new</p>" "$LOG"
assert_contains "set forwards --display-name" "--display-name Al" "$LOG"

# ---------- weekly-plan --calendar ----------
echo "--- weekly-plan --calendar ---"
SNAP="$WORK/snap.json"
cat > "$SNAP" <<'JSON'
{"repo":"acme/proj","generatedAt":"2026-06-01T08:00:00Z",
 "issues":[{"number":1,"title":"Ship it","url":"https://github.com/acme/proj/issues/1","state":"OPEN","labels":["P0"],"assignees":[]}],
 "pullRequests":[]}
JSON
: > "$GOG_LOG"
bash "$PO_DIR/weekly-plan.sh" --snapshot "$SNAP" --calendar >/dev/null 2>&1
LOG=$(cat "$GOG_LOG")
assert_contains "weekly-plan lists events via gog api" "api call calendar v3 events.list" "$LOG"
assert_contains "weekly-plan creates events with gog calendar create" "calendar create primary --summary [proj] PO Daily" "$LOG"

# The summary embeds the run date, so replay the first one the script created.
FIRST=$(grep -m1 'calendar create' "$GOG_LOG" | sed -E 's/^.*--summary (.*) --from .*$/\1/')
: > "$GOG_LOG"
FAKE_EVENTS=$(jq -nc --arg s "$FIRST" '{items:[{id:"evt1",summary:$s}]}')
export FAKE_EVENTS
bash "$PO_DIR/weekly-plan.sh" --snapshot "$SNAP" --calendar >/dev/null 2>&1
assert_contains "weekly-plan patches existing events with gog calendar update" "calendar update primary evt1" "$(cat "$GOG_LOG")"
unset FAKE_EVENTS

# ---------- summary ----------
echo ""
echo "=== $((PASS + FAIL)) tests: $PASS passed, $FAIL failed ==="
[[ "$FAIL" -eq 0 ]]
