#!/usr/bin/env bash
# doctor.sh — daily health check for `gog`, with auto-repair of missing
# services. Run before a Workspace-heavy session, or wire into a PreToolUse
# hook to surface drift early.
#
#   bash scripts/doctor.sh             # full check
#   bash scripts/doctor.sh --quiet     # exit codes only, no output if green
#   bash scripts/doctor.sh --no-repair # skip auto-relogin even on missing services
#
# Checks the active account (GOG_ACCOUNT, else gog's default). Use
# `GOG_ACCOUNT=other@example.com bash scripts/doctor.sh` for another one.
#
# Exit codes (suitable for hook gating):
#   0  all green
#   1  warnings only (e.g. outdated gog version)
#   2  one or more services failing or auth invalid
#
# Distinct from scripts/onboard.sh — that's the one-shot zero-to-working
# bootstrap. doctor is the recurring "is everything still wired up?" check.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_gog.sh
source "$SCRIPT_DIR/_gog.sh"

QUIET=0
REPAIR=1
for arg in "$@"; do
  case "$arg" in
    --quiet)     QUIET=1 ;;
    --no-repair) REPAIR=0 ;;
    -h|--help) sed -n '2,19p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
  esac
done

# Buffered output so --quiet can suppress everything when exit == 0.
BUF=$(mktemp -t gog-doctor.XXXXXX)
trap 'rm -f "$BUF"' EXIT
say()  { printf "%s\n" "$*" >>"$BUF"; }
ok()   { say "  ✓ $*"; }
warn() { say "  ⚠ $*"; }
bad()  { say "  ✗ $*"; }
hdr()  { say ""; say "[$1] $2"; }

EXIT_CODE=0
bump() { [ "$1" -gt "$EXIT_CODE" ] && EXIT_CODE=$1 || true; }

#==============================================================================
# [1/4] Binary & version
#==============================================================================
hdr "1/4" "Binary & version"

if ! command -v "$GOG_BIN" >/dev/null; then
  bad "gog not installed"
  bad "  → $GOG_INSTALL_HINT"
  bump 2
else
  INSTALLED=$("$GOG_BIN" --version 2>/dev/null | head -1 | sed -E 's/^[^0-9]*([0-9]+\.[0-9]+\.[0-9]+).*/\1/')
  ok "gog $INSTALLED"
  if [ -z "$INSTALLED" ] || [ "$(printf '%s\n%s\n' "$GOG_MIN_VERSION" "$INSTALLED" | sort -V | head -1)" != "$GOG_MIN_VERSION" ]; then
    bad "gog $INSTALLED is older than $GOG_MIN_VERSION — brew upgrade openclaw/tap/gogcli"
    bump 2
  elif command -v gh >/dev/null; then
    LATEST=$(gh release view -R openclaw/gogcli --json tagName -q .tagName 2>/dev/null | sed 's/^v//' || true)
    if [ -n "$LATEST" ] && [ "$INSTALLED" != "$LATEST" ] \
       && [ "$(printf '%s\n%s\n' "$INSTALLED" "$LATEST" | sort -V | tail -1)" = "$LATEST" ]; then
      warn "$LATEST available — brew upgrade openclaw/tap/gogcli"
      bump 1
    fi
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

EMAIL=""
if [ "$EXIT_CODE" -ge 2 ]; then
  warn "skipping (binary/jq missing)"
else
  EMAIL=$(gog_account)
  if [ -z "$EMAIL" ]; then
    bad "no account configured"
    bad "  → bash scripts/auth-login.sh you@example.com"
    bump 2
  elif ! gog_auth_ok; then
    bad "refresh token for $EMAIL is not usable"
    bad "  → bash scripts/auth-login.sh $EMAIL"
    bump 2
  else
    ok "token valid"
    ok "user      = $EMAIL"
    PROJECT=$("$GOG_BIN" auth status --json --no-input 2>/dev/null | jq -r '.account.credentials_path // empty')
    [ -n "$PROJECT" ] && [ -f "$PROJECT" ] \
      && ok "project   = $(jq -r '(.installed // .web // .) | (.project_id // ((.client_id // "") | split("-")[0])) // "unknown"' "$PROJECT" 2>/dev/null)"
  fi
fi

#==============================================================================
# [3/4] Service audit
#==============================================================================
hdr "3/4" "Service audit"

audit_services() {
  local s want
  GRANTED_LIST=$("$GOG_BIN" auth list --json --no-input 2>/dev/null \
    | jq -r --arg e "$EMAIL" '.accounts[] | select(.email == $e) | .services[]' | sort -u) || return 1
  [ -n "$GRANTED_LIST" ] || return 1
  MISSING_LIST=()
  IFS=',' read -ra want <<< "$(bash "$SCRIPT_DIR/auth-login.sh" --print-services)"
  EXPECTED_COUNT=${#want[@]}
  for s in "${want[@]}"; do
    printf '%s\n' "$GRANTED_LIST" | grep -qx "$s" || MISSING_LIST+=("$s")
  done
}

if [ "$EXIT_CODE" -ge 2 ]; then
  warn "skipping (auth invalid)"
else
  MISSING_LIST=()
  if audit_services; then
    ok "Expected: $EXPECTED_COUNT services"
    ok "Granted : $(printf '%s' "$GRANTED_LIST" | paste -sd, -)"
    if [ "${#MISSING_LIST[@]}" -gt 0 ]; then
      warn "Missing : ${MISSING_LIST[*]}"
      if [ "$REPAIR" -eq 1 ]; then
        say "  → re-running auth-login.sh to request the full service set…"
        # Run and append output to BUF so --quiet still suppresses on green.
        bash "$SCRIPT_DIR/auth-login.sh" "$EMAIL" >>"$BUF" 2>&1 || true
        if audit_services && [ "${#MISSING_LIST[@]}" -eq 0 ]; then
          ok "re-auth complete — all $EXPECTED_COUNT services granted"
        else
          warn "still missing: ${MISSING_LIST[*]} — likely not registered"
          warn "on the OAuth consent screen. Fix:"
          warn "  bash scripts/onboard.sh --step scopes"
          bump 2
        fi
      else
        bump 1
      fi
    fi
  else
    warn "could not read the granted services for $EMAIL (skipping)"
    bump 1
  fi
fi

#==============================================================================
# [4/4] Service smoke tests
#==============================================================================
hdr "4/4" "Service smoke tests"

if [ "$EXIT_CODE" -ge 2 ]; then
  warn "skipping (auth or service problem above)"
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

  smoke "Gmail    (search)"         ""                                          "$GOG_BIN" gmail search 'in:inbox' --max 1 --json --no-input
  smoke "Calendar (events)"         ""                                          "$GOG_BIN" calendar events --today --max 1 --json --no-input
  smoke "Drive    (ls)"             "bash scripts/fix-iam-403.sh"               "$GOG_BIN" drive ls --max 1 --json --no-input
  smoke "Tasks    (lists)"          "bash scripts/fix-iam-403.sh"               "$GOG_BIN" tasks lists list --json --no-input
  smoke "Chat     (spaces)"         "bash scripts/onboard.sh --step chat-app"   "$GOG_BIN" chat spaces list --json --no-input
  smoke "Contacts (directory)"      "bash scripts/onboard.sh --step scopes"     "$GOG_BIN" contacts directory list --max 1 --json --no-input
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
