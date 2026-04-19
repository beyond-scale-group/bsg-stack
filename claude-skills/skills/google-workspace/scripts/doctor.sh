#!/usr/bin/env bash
# doctor.sh — daily health check for `gws`, with auto-repair of missing
# scopes. Run before a Workspace-heavy session, or wire into a PreToolUse
# hook to surface drift early.
#
#   bash scripts/doctor.sh             # full check
#   bash scripts/doctor.sh --quiet     # exit codes only, no output if green
#   bash scripts/doctor.sh --no-repair # skip auto-relogin even on missing scopes
#
# Exit codes (suitable for hook gating):
#   0  all green
#   1  warnings only (e.g. outdated gws version)
#   2  one or more services failing or auth invalid
#
# Distinct from scripts/onboard.sh — that's the one-shot zero-to-working
# bootstrap. doctor is the recurring "is everything still wired up?" check.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

QUIET=0
REPAIR=1
for arg in "$@"; do
  case "$arg" in
    --quiet)     QUIET=1 ;;
    --no-repair) REPAIR=0 ;;
    -h|--help) sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
  esac
done

# Buffered output so --quiet can suppress everything when exit == 0.
BUF=$(mktemp -t gws-doctor.XXXXXX)
trap 'rm -f "$BUF"' EXIT
say()  { printf "%s\n" "$*" >>"$BUF"; }
ok()   { say "  ✓ $*"; }
warn() { say "  ⚠ $*"; }
bad()  { say "  ✗ $*"; }
hdr()  { say ""; say "[$1] $2"; }

EXIT_CODE=0
bump() { [ "$1" -gt "$EXIT_CODE" ] && EXIT_CODE=$1 || true; }

# Same scope list as scripts/auth-login.sh and scripts/onboard.sh.
EXPECTED_SCOPES=(
  https://www.googleapis.com/auth/drive
  https://www.googleapis.com/auth/spreadsheets
  https://www.googleapis.com/auth/gmail.modify
  https://www.googleapis.com/auth/calendar
  https://www.googleapis.com/auth/documents
  https://www.googleapis.com/auth/presentations
  https://www.googleapis.com/auth/tasks
  https://www.googleapis.com/auth/chat.spaces
  https://www.googleapis.com/auth/contacts
  https://www.googleapis.com/auth/directory.readonly
  https://www.googleapis.com/auth/forms.body
  https://www.googleapis.com/auth/meetings.space.created
  openid
  https://www.googleapis.com/auth/userinfo.email
  https://www.googleapis.com/auth/userinfo.profile
)
EXPECTED_COUNT=${#EXPECTED_SCOPES[@]}

#==============================================================================
# [1/4] Binary & version
#==============================================================================
hdr "1/4" "Binary & version"

if ! command -v gws >/dev/null; then
  bad "gws not installed"
  bad "  → npm install -g @googleworkspace/cli@latest"
  bump 2
else
  INSTALLED=$(gws --version 2>/dev/null | head -1 | awk '{print $2}')
  ok "gws $INSTALLED"
  LATEST=$(npm view @googleworkspace/cli version 2>/dev/null || true)
  if [ -n "$LATEST" ] && [ "$INSTALLED" != "$LATEST" ]; then
    warn "$LATEST available — npm install -g @googleworkspace/cli@latest"
    bump 1
  fi
fi

if ! command -v jq >/dev/null; then
  bad "jq not installed — brew install jq"
  bump 2
fi

#==============================================================================
# [2/4] Auth & token
#==============================================================================
hdr "2/4" "Auth & token"

if [ "$EXIT_CODE" -ge 2 ]; then
  warn "skipping (binary/jq missing)"
else
  STATUS=$(gws auth status 2>/dev/null || echo '{}')
  TOKEN_VALID=$(echo "$STATUS" | jq -r '.token_valid // false')
  PROJECT=$(echo "$STATUS" | jq -r '.project_id // empty')

  if [ "$TOKEN_VALID" != "true" ]; then
    bad "token_valid = false"
    bad "  → bash scripts/auth-login.sh"
    bump 2
  else
    ok "token_valid = true"
    [ -n "$PROJECT" ] && ok "project   = $PROJECT"

    EMAIL=$(gws gmail users getProfile --params '{"userId":"me"}' 2>/dev/null \
            | jq -r '.emailAddress // empty')
    [ -n "$EMAIL" ] && ok "user      = $EMAIL"
  fi
fi

#==============================================================================
# [3/4] Scope audit
#==============================================================================
hdr "3/4" "Scope audit"

mint_access_token() {
  local cid csecret refresh
  cid=$(gws auth export --unmasked 2>/dev/null | jq -r '.client_id // empty')
  csecret=$(gws auth export --unmasked 2>/dev/null | jq -r '.client_secret // empty')
  refresh=$(gws auth export --unmasked 2>/dev/null | jq -r '.refresh_token // empty')
  [ -n "$cid" ] && [ -n "$csecret" ] && [ -n "$refresh" ] || return 1
  curl -sX POST https://oauth2.googleapis.com/token \
    -d "client_id=$cid" -d "client_secret=$csecret" \
    -d "refresh_token=$refresh" -d "grant_type=refresh_token" \
    | jq -r '.access_token // empty'
}

audit_scopes() {
  local access granted missing s
  access=$(mint_access_token) || return 1
  [ -n "$access" ] || return 1
  granted=$(curl -s "https://oauth2.googleapis.com/tokeninfo?access_token=$access" \
            | jq -r '.scope // empty' | tr ' ' '\n' | sort -u)
  GRANTED_COUNT=$(printf '%s\n' "$granted" | grep -c .)
  MISSING_LIST=()
  for s in "${EXPECTED_SCOPES[@]}"; do
    if ! printf "%s\n" "$granted" | grep -Fxq "$s"; then
      MISSING_LIST+=("$s")
    fi
  done
}

if [ "$EXIT_CODE" -ge 2 ]; then
  warn "skipping (auth invalid)"
else
  GRANTED_COUNT=0
  MISSING_LIST=()
  if audit_scopes; then
    ok "Expected: $EXPECTED_COUNT scopes"
    ok "Granted : $GRANTED_COUNT"
    if [ "${#MISSING_LIST[@]}" -gt 0 ]; then
      warn "Missing : ${#MISSING_LIST[@]} scope(s)"
      for s in "${MISSING_LIST[@]}"; do
        warn "    - ${s##*/}"
      done
      if [ "$REPAIR" -eq 1 ]; then
        say "  → re-running auth-login.sh to request the full scope list…"
        # Run and append output to BUF so --quiet still suppresses on green.
        bash "$SCRIPT_DIR/auth-login.sh" >>"$BUF" 2>&1 || true
        if audit_scopes && [ "${#MISSING_LIST[@]}" -eq 0 ]; then
          ok "re-auth complete — $GRANTED_COUNT/$EXPECTED_COUNT scopes granted"
        else
          warn "still missing ${#MISSING_LIST[@]} scope(s) — likely not registered"
          warn "on the OAuth consent screen. Fix:"
          warn "  bash scripts/onboard.sh --step scopes"
          bump 2
        fi
      else
        bump 1
      fi
    fi
  else
    warn "could not mint access token to audit scopes (skipping)"
    bump 1
  fi
fi

#==============================================================================
# [4/4] Service smoke tests
#==============================================================================
hdr "4/4" "Service smoke tests"

if [ "$EXIT_CODE" -ge 2 ]; then
  warn "skipping (auth or scope problem above)"
else
  smoke() {
    local name="$1"; local fix="$2"; shift 2
    if "$@" >/dev/null 2>&1; then
      ok "$name"
    else
      bad "$name"
      [ -n "$fix" ] && bad "    Fix: $fix"
      bump 2
    fi
  }

  smoke "Gmail    (messages.list)"  ""                                          gws gmail users messages list --params '{"userId":"me","maxResults":1}'
  smoke "Calendar (events.list)"    ""                                          gws calendar events list --params '{"calendarId":"primary","maxResults":1}'
  smoke "Drive    (files.list)"     "bash scripts/fix-iam-403.sh"               gws drive files list --params '{"pageSize":1}'
  smoke "Tasks    (tasklists.list)" "bash scripts/fix-iam-403.sh"               gws tasks tasklists list --params '{"maxResults":1}'
  smoke "Chat     (spaces.list)"    "bash scripts/onboard.sh --step chat-app"   gws chat spaces list --params '{"pageSize":1}'
  smoke "Contacts (listDirectory)"  "bash scripts/onboard.sh --step scopes"     gws people people listDirectoryPeople --params '{"readMask":"emailAddresses","sources":"DIRECTORY_SOURCE_TYPE_DOMAIN_PROFILE","pageSize":1}'
fi

#==============================================================================
# Output
#==============================================================================
if [ "$QUIET" -eq 1 ] && [ "$EXIT_CODE" -eq 0 ]; then
  : # silent on green
else
  cat "$BUF"
  echo
  case "$EXIT_CODE" in
    0) echo "✓ healthy" ;;
    1) echo "⚠ warnings — see above" ;;
    2) echo "✗ failures — see above" ;;
  esac
fi

exit "$EXIT_CODE"
