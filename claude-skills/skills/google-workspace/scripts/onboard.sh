#!/usr/bin/env bash
# onboard.sh — zero-to-working `gog` (gogcli) setup, in one orchestrated flow.
#
# Solves the friction stack discovered in beyond-scale-group/bsg-stack#38:
# missing prereqs, OAuth client to be created by hand, scopes silently
# dropped because they aren't registered on the consent screen, and the
# Chat API requiring a separate app registration.
#
# gog can also prepare the GCP project itself (`gog auth setup`); this script
# keeps the explicit, idempotent steps so each one can be re-run alone.
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
#   bash scripts/onboard.sh --step login       # `gog auth add` with the BSG services
#   bash scripts/onboard.sh --step smoke       # service smoke tests
#
# Env: GOG_PROJECT_ID (GCP project), GOG_ACCOUNT (account to authorize),
#      GOG_CLIENT_SECRET_FILE (downloaded OAuth client JSON to register).
#
# Steps that need GCP Console interaction print the exact URL + checklist
# and pause. Browser automation is intentionally NOT bundled here — see
# beyond-scale-group/bsg-stack#39 for the planned `/browser` skill that
# will wrap agent-browser with persistent login state. Once that lands,
# this script will gain an `--auto` mode that drives the GCP Console
# steps without manual interaction.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_gog.sh
source "$SCRIPT_DIR/_gog.sh"

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

# Scopes to register on the OAuth consent screen (Step 4) — what gog requests
# for the BSG service set (`bash auth-login.sh --print-services`). Cross-check
# with `gog auth services`.
SCOPES=(
  https://www.googleapis.com/auth/gmail.modify
  https://www.googleapis.com/auth/gmail.settings.basic
  https://www.googleapis.com/auth/gmail.settings.sharing
  https://www.googleapis.com/auth/calendar
  https://www.googleapis.com/auth/drive
  https://www.googleapis.com/auth/documents
  https://www.googleapis.com/auth/spreadsheets
  https://www.googleapis.com/auth/presentations
  https://www.googleapis.com/auth/contacts
  https://www.googleapis.com/auth/contacts.other.readonly
  https://www.googleapis.com/auth/directory.readonly
  https://www.googleapis.com/auth/tasks
  https://www.googleapis.com/auth/chat.spaces
  https://www.googleapis.com/auth/chat.messages
  https://www.googleapis.com/auth/chat.memberships
  https://www.googleapis.com/auth/forms.body
  https://www.googleapis.com/auth/forms.responses.readonly
  https://www.googleapis.com/auth/meetings.space.created
  https://www.googleapis.com/auth/meetings.space.readonly
  https://www.googleapis.com/auth/meetings.space.settings
  openid
  https://www.googleapis.com/auth/userinfo.email
  profile
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

  if ! command -v "$GOG_BIN" >/dev/null; then
    if command -v brew >/dev/null; then
      info "gog not installed — installing: $GOG_INSTALL_HINT"
      brew install openclaw/tap/gogcli
    else
      die "gog not installed — see https://github.com/openclaw/gogcli#install"
    fi
  fi
  ( gog_require ) || die "gog too old — brew upgrade openclaw/tap/gogcli"
  ok "gog $("$GOG_BIN" --version | head -1 | awk '{print $1}')"

  if ! command -v jq >/dev/null; then
    die "jq not installed — brew install jq"
  fi
  ok "jq $(jq --version)"

  if ! command -v gcloud >/dev/null; then
    warn "gcloud not installed — required for Step 2 (enabling APIs)."
    warn "Install with:"
    warn "  brew install --cask google-cloud-sdk"
    warn "Skipping prereq gate — re-run later if you want."
  else
    ok "gcloud $(gcloud --version 2>/dev/null | head -1 | awk '{print $4}')"
  fi
}

resolve_project() {
  PROJECT="${GOG_PROJECT_ID:-${GWS_PROJECT_ID:-}}"
  [ -n "$PROJECT" ] && return
  # project_id lives in the OAuth client JSON that gog stored.
  local creds
  creds=$("$GOG_BIN" auth status --json --no-input 2>/dev/null | jq -r '.account.credentials_path // empty')
  if [ -n "$creds" ] && [ -f "$creds" ]; then
    # gog stores a flat {client_id, client_secret}; the project *number* is the
    # client_id prefix (gcloud accepts it wherever it takes a project).
    PROJECT=$(jq -r '(.installed // .web // .) | (.project_id // ((.client_id // "") | split("-")[0])) // empty' "$creds" 2>/dev/null)
  fi
  if [ -z "$PROJECT" ] && command -v gcloud >/dev/null; then
    PROJECT=$(gcloud config get-value project 2>/dev/null | grep -v '^$' || true)
    [ "$PROJECT" = "(unset)" ] && PROJECT=""
  fi
  if [ -z "$PROJECT" ] && [ -t 0 ]; then
    printf "  Enter your GCP project ID: "
    read -r PROJECT
  fi
  [ -n "$PROJECT" ] || die "no GCP project — set GOG_PROJECT_ID or pass one interactively"
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

client_ready() {
  "$GOG_BIN" auth status --json --no-input 2>/dev/null | jq -e '.account.credentials_exists == true' >/dev/null
}

step_oauth() {
  step "Step 3/7 — Create OAuth client (manual, GCP Console)"

  if client_ready; then
    ok "OAuth client already registered with gog"
    info "Re-run with --force-oauth to redo this step."
    [ "${FORCE_OAUTH:-0}" = "1" ] || return 0
  fi

  resolve_project
  cat <<EOF

  Google requires the OAuth client to be created by hand in the GCP Console
  (or let gog drive the project prep: gog auth setup). Open this URL:

      https://console.cloud.google.com/apis/credentials?project=$PROJECT

  Then:

    1. Click "Create Credentials" → "OAuth client ID"
    2. Application type: "Desktop app"
    3. Name: "gog CLI"  (any name works)
    4. Click "Create"
    5. Download the JSON
    6. Register it: gog auth credentials set ~/Downloads/client_secret_*.json
       (or pass the path via GOG_CLIENT_SECRET_FILE to this script)

  ⚠ GCP Console always demands passkey re-authentication, even with a
    saved browser session. Plan to authenticate once for the whole
    onboard run.

EOF
  pause

  if [ -n "${GOG_CLIENT_SECRET_FILE:-}" ] && [ -f "$GOG_CLIENT_SECRET_FILE" ]; then
    "$GOG_BIN" auth credentials set "$GOG_CLIENT_SECRET_FILE"
  fi

  if ! client_ready; then
    warn "no OAuth client registered with gog yet"
    warn "Run: gog auth credentials set <client_secret.json>, then: bash scripts/onboard.sh --step oauth"
    return 1
  fi
  ok "OAuth client registered"
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

    1. App name        : gog CLI (or any name)
    2. Avatar URL      : https://developers.google.com/chat/images/quickstart-app-avatar.png
    3. Description     : User-context CLI access via gog
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
  step "Step 6/7 — OAuth login with the BSG service set"

  local email="${GOG_ACCOUNT:-}"
  if [ -z "$email" ] || [[ "$email" != *@* ]]; then
    if [ -t 0 ]; then
      printf "  Google account to authorize (email): "
      read -r email
    fi
  fi
  [ -n "$email" ] || die "no account — set GOG_ACCOUNT=you@example.com or run interactively"

  # auth-login.sh runs `gog auth add`, verifies the token and reports any
  # service Google's consent screen dropped.
  bash "$SCRIPT_DIR/auth-login.sh" "$email" || die "auth still invalid after login — check the OAuth client and try again"
  ok "$email authorized"
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

  smoke "Gmail    (search)"         "$GOG_BIN" gmail search 'in:inbox' --max 1 --json --no-input
  smoke "Calendar (events)"         "$GOG_BIN" calendar events --today --max 1 --json --no-input
  smoke "Drive    (ls)"             "$GOG_BIN" drive ls --max 1 --json --no-input
  smoke "Sheets   (api reachable)"  "$GOG_BIN" sheets --help
  smoke "Tasks    (lists)"          "$GOG_BIN" tasks lists list --json --no-input
  smoke "Chat     (spaces)"         "$GOG_BIN" chat spaces list --json --no-input
  smoke "People   (contacts)"       "$GOG_BIN" contacts list --max 1 --json --no-input
  smoke "Forms    (api reachable)"  "$GOG_BIN" forms --help
  smoke "Meet     (api reachable)"  "$GOG_BIN" meet --help

  echo
  if [ "$FAIL" -eq 0 ]; then
    ok "all $PASS smoke tests passed — gog is ready"
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
  sed -n '2,29p' "$0" | sed 's/^# \{0,1\}//'
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
