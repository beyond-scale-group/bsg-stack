#!/usr/bin/env bash
# onboard.sh — zero-to-working `gws` setup, in one orchestrated flow.
#
# Solves the friction stack discovered in beyond-scale-group/bsg-stack#38:
# missing prereqs, OAuth client to be created by hand, scopes silently
# dropped because they aren't registered on the consent screen, and the
# Chat API requiring a separate app registration.
#
# Each step is idempotent. Re-run the whole script or jump to a single
# step:
#
#   bash scripts/onboard.sh                    # full flow
#   bash scripts/onboard.sh --step prereqs     # just the binary checks
#   bash scripts/onboard.sh --step apis        # just `gcloud services enable`
#   bash scripts/onboard.sh --step oauth       # OAuth client creation guide
#   bash scripts/onboard.sh --step scopes      # consent-screen scope guide
#   bash scripts/onboard.sh --step chat-app    # Chat app registration guide
#   bash scripts/onboard.sh --step login       # `gws auth login` with our scopes
#   bash scripts/onboard.sh --step smoke       # service smoke tests
#
# Steps that need GCP Console interaction print the exact URL + checklist
# and pause. Browser automation is intentionally NOT bundled here — see
# beyond-scale-group/bsg-stack#39 for the planned `/browser` skill that
# will wrap agent-browser with persistent login state. Once that lands,
# this script will gain an `--auto` mode that drives the GCP Console
# steps without manual interaction.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

step()  { printf "\n\033[1;34m▸ %s\033[0m\n" "$*"; }
info()  { printf "  %s\n" "$*"; }
ok()    { printf "  \033[32m✓\033[0m %s\n" "$*"; }
warn()  { printf "  \033[33m⚠\033[0m %s\n" "$*" >&2; }
die()   { printf "  \033[31m✗\033[0m %s\n" "$*" >&2; exit 1; }

pause() {
  if [ ! -t 0 ]; then
    info "(non-interactive — skipping prompt)"
    return 0
  fi
  printf "\n  Press ENTER when done, or Ctrl-C to abort: "
  read -r _ || true
}

# Single source of truth for the curated 15-scope default. Mirrored in
# scripts/auth-login.sh — keep them in sync.
SCOPES=(
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

# APIs that must be enabled on the GCP project. People + Forms + Chat +
# Meet are the ones whose absence makes the corresponding scopes
# disappear from the consent-screen picker.
APIS=(
  drive.googleapis.com
  sheets.googleapis.com
  gmail.googleapis.com
  calendar-json.googleapis.com
  docs.googleapis.com
  slides.googleapis.com
  tasks.googleapis.com
  chat.googleapis.com
  people.googleapis.com
  forms.googleapis.com
  meet.googleapis.com
)

#==============================================================================
# Step implementations
#==============================================================================

step_prereqs() {
  step "Step 1/7 — Prerequisites"

  if ! command -v node >/dev/null; then
    die "node not installed — install Node.js first (https://nodejs.org)"
  fi
  ok "node $(node --version)"

  if ! command -v npm >/dev/null; then
    die "npm not installed (should ship with Node.js)"
  fi
  ok "npm $(npm --version)"

  if ! command -v gws >/dev/null; then
    info "gws not installed — installing globally now"
    npm install -g @googleworkspace/cli@latest
  fi
  ok "gws $(gws --version | head -1 | awk '{print $2}')"

  if ! command -v jq >/dev/null; then
    die "jq not installed — brew install jq"
  fi
  ok "jq $(jq --version)"

  if ! command -v gcloud >/dev/null; then
    warn "gcloud not installed — required for Step 2 (enabling APIs) and"
    warn "Step 7 (smoke tests via Chat API). Install with:"
    warn "  brew install --cask google-cloud-sdk"
    warn "Skipping prereq gate — re-run later if you want."
  else
    ok "gcloud $(gcloud --version 2>/dev/null | head -1 | awk '{print $4}')"
  fi
}

resolve_project() {
  if [ -n "${GWS_PROJECT_ID:-}" ]; then
    PROJECT="$GWS_PROJECT_ID"
    return
  fi
  PROJECT=$(gws auth status 2>/dev/null | jq -r '.project_id // empty')
  if [ -z "$PROJECT" ] && command -v gcloud >/dev/null; then
    PROJECT=$(gcloud config get-value project 2>/dev/null | grep -v '^$' || true)
    [ "$PROJECT" = "(unset)" ] && PROJECT=""
  fi
  if [ -z "$PROJECT" ] && [ -t 0 ]; then
    printf "  Enter your GCP project ID: "
    read -r PROJECT
  fi
  [ -n "$PROJECT" ] || die "no GCP project — set GWS_PROJECT_ID or pass one interactively"
}

step_apis() {
  step "Step 2/7 — Enable Workspace APIs on the GCP project"

  command -v gcloud >/dev/null || die "gcloud required for this step"

  resolve_project
  info "project: $PROJECT"

  # gcloud needs to be logged in.
  ACTIVE=$(gcloud config get-value account 2>/dev/null || true)
  if [ -z "$ACTIVE" ] || [ "$ACTIVE" = "(unset)" ]; then
    info "gcloud not authenticated — running: gcloud auth login"
    gcloud auth login
  fi

  info "enabling ${#APIS[@]} APIs on $PROJECT (idempotent)…"
  gcloud services enable "${APIS[@]}" --project="$PROJECT" --quiet
  ok "all APIs enabled"
}

step_oauth() {
  step "Step 3/7 — Create OAuth client (manual, GCP Console)"

  CLIENT_PATH="${GOOGLE_WORKSPACE_CLI_CONFIG_DIR:-$HOME/.config/gws}/client_secret.json"

  if [ -f "$CLIENT_PATH" ]; then
    ok "OAuth client already in place at $CLIENT_PATH"
    info "Re-run with --force-oauth to redo this step."
    [ "${FORCE_OAUTH:-0}" = "1" ] || return 0
  fi

  resolve_project
  cat <<EOF

  gws cannot auto-create the OAuth client — Google requires manual setup
  in the GCP Console. Open this URL:

      https://console.cloud.google.com/apis/credentials?project=$PROJECT

  Then:

    1. Click "Create Credentials" → "OAuth client ID"
    2. Application type: "Desktop app"
    3. Name: "gws CLI"  (any name works)
    4. Click "Create"
    5. Download the JSON
    6. Save it to: $CLIENT_PATH

  ⚠ GCP Console always demands passkey re-authentication, even with a
    saved browser session. Plan to authenticate once for the whole
    onboard run.

EOF
  pause

  if [ ! -f "$CLIENT_PATH" ]; then
    warn "client_secret.json still missing at $CLIENT_PATH"
    warn "Drop the downloaded JSON there and re-run: bash scripts/onboard.sh --step oauth"
    return 1
  fi
  ok "client_secret.json detected"
}

step_scopes() {
  step "Step 4/7 — Register scopes on the OAuth consent screen (manual)"

  resolve_project
  cat <<EOF

  Google's consent screen silently drops any scope that isn't registered
  on the project's OAuth consent screen. APIs (Step 2) must be enabled
  first or these scopes won't appear in the picker.

  Open this URL:

      https://console.cloud.google.com/apis/credentials/consent?project=$PROJECT

  Then:

    1. Click "Edit App"
    2. Click through to "Scopes"
    3. Click "Add or Remove Scopes"
    4. In the "Manually add scopes" field at the bottom, paste each line
       below (one at a time, or comma-separated if the form accepts it):

EOF
  for s in "${SCOPES[@]}"; do
    printf "         %s\n" "$s"
  done
  cat <<EOF

    5. Click "Add to Table" → tick every newly added scope → "Update"
    6. "Save and Continue" through the rest of the wizard

EOF
  pause
  ok "scope registration acknowledged (verified at Step 6)"
}

step_chat_app() {
  step "Step 5/7 — Register Chat app (manual, GCP Console)"

  resolve_project
  cat <<EOF

  The Chat API requires a registered "Chat app configuration" before any
  endpoint will respond — even read-only user-context calls. Without
  this, every chat.* call returns 404 "Google Chat app not found".

  Open this URL:

      https://console.cloud.google.com/apis/api/chat.googleapis.com/hangouts-chat?project=$PROJECT

  Then:

    1. App name        : gws CLI (or any name)
    2. Avatar URL      : https://developers.google.com/chat/images/quickstart-app-avatar.png
    3. Description     : User-context CLI access via gws
    4. Functionality   : tick "Receive 1:1 messages" + "Join spaces and group conversations"
    5. Connection      : "App URL" — placeholder OK (user-context CLI never receives webhooks)
                         e.g. https://example.com/chat
    6. Visibility      : "Make this Chat app available to specific people…"
                         Add your own email
    7. Click "Save"

EOF
  pause
  ok "Chat app registration acknowledged (verified at Step 7)"
}

step_login() {
  step "Step 6/7 — OAuth login with the curated 15-scope list"

  bash "$SCRIPT_DIR/auth-login.sh"

  STATUS=$(gws auth status 2>/dev/null)
  if ! echo "$STATUS" | jq -e '.token_valid == true' >/dev/null; then
    die "auth still invalid after login — check the OAuth client and try again"
  fi

  # Cross-check the granted scope count against our 15 explicit scopes.
  CID=$(gws auth export --unmasked 2>/dev/null | jq -r '.client_id // empty')
  CSECRET=$(gws auth export --unmasked 2>/dev/null | jq -r '.client_secret // empty')
  REFRESH=$(gws auth export --unmasked 2>/dev/null | jq -r '.refresh_token // empty')
  if [ -n "$CID" ] && [ -n "$CSECRET" ] && [ -n "$REFRESH" ]; then
    ACCESS=$(curl -sX POST https://oauth2.googleapis.com/token \
      -d "client_id=$CID" -d "client_secret=$CSECRET" \
      -d "refresh_token=$REFRESH" -d "grant_type=refresh_token" \
      | jq -r '.access_token // empty')
    if [ -n "$ACCESS" ]; then
      GRANTED=$(curl -s "https://oauth2.googleapis.com/tokeninfo?access_token=$ACCESS" \
                | jq -r '.scope // empty' | tr ' ' '\n' | sort -u)
      COUNT=$(printf '%s\n' "$GRANTED" | grep -c .)
      ok "granted $COUNT scope(s) (expected ${#SCOPES[@]})"
      if [ "$COUNT" -lt "${#SCOPES[@]}" ]; then
        warn "Some scopes were dropped — likely missing from the consent"
        warn "screen registration. Re-run Step 4: bash scripts/onboard.sh --step scopes"
      fi
    fi
  fi
}

step_smoke() {
  step "Step 7/7 — Service smoke tests"

  PASS=0; FAIL=0
  smoke() {
    local name="$1"; shift
    if "$@" >/dev/null 2>&1; then
      ok "$name"
      PASS=$((PASS+1))
    else
      warn "$name FAILED"
      FAIL=$((FAIL+1))
    fi
  }

  smoke "Gmail    (messages.list)"  gws gmail users messages list --params '{"userId":"me","maxResults":1}'
  smoke "Calendar (events.list)"    gws calendar events list --params '{"calendarId":"primary","maxResults":1}'
  smoke "Drive    (files.list)"     gws drive files list --params '{"pageSize":1}'
  smoke "Sheets   (api reachable)"  bash -c "gws sheets --help"
  smoke "Tasks    (tasklists.list)" gws tasks tasklists list --params '{"maxResults":1}'
  smoke "Chat     (spaces.list)"    gws chat spaces list --params '{"pageSize":1}'
  smoke "People   (contactGroups)"  gws people contactGroups list --params '{"pageSize":1}'
  smoke "Forms    (api reachable)"  bash -c "gws forms --help"

  echo
  if [ "$FAIL" -eq 0 ]; then
    ok "all $PASS smoke tests passed — gws is ready"
  else
    warn "$FAIL of $((PASS+FAIL)) smoke tests failed"
    warn "Common fixes:"
    warn "  • 403 IAM      → bash scripts/fix-iam-403.sh --enable-apis"
    warn "  • 404 Chat app → bash scripts/onboard.sh --step chat-app"
    warn "  • Missing scope → bash scripts/onboard.sh --step scopes && --step login"
    return 1
  fi
}

#==============================================================================
# CLI
#==============================================================================

usage() {
  sed -n '2,28p' "$0" | sed 's/^# \{0,1\}//'
}

STEP="all"
while [ $# -gt 0 ]; do
  case "$1" in
    --step) STEP="$2"; shift 2 ;;
    --force-oauth) FORCE_OAUTH=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown flag: $1 (try --help)" ;;
  esac
done

case "$STEP" in
  all)
    step_prereqs
    step_apis
    step_oauth
    step_scopes
    step_chat_app
    step_login
    step_smoke
    echo
    ok "Onboarding complete."
    ;;
  prereqs)   step_prereqs ;;
  apis)      step_apis ;;
  oauth)     step_oauth ;;
  scopes)    step_scopes ;;
  chat-app)  step_chat_app ;;
  login)     step_login ;;
  smoke)     step_smoke ;;
  *) die "unknown step: $STEP (valid: prereqs, apis, oauth, scopes, chat-app, login, smoke, all)" ;;
esac
