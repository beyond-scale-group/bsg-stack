#!/usr/bin/env bash
# fix-iam-403.sh — grant the current gog user
# `roles/serviceusage.serviceUsageConsumer` on the GCP project tied to the
# OAuth client, so Drive / Tasks / Chat / People / Sheets / Slides APIs
# stop returning 403 "Caller does not have required permission to use
# project …".
#
# OAuth scopes don't help — this is a GCP IAM problem. Gmail & Calendar
# work without the role because they skip the serviceusage.services.use
# check; the rest enforce it.
#
# Usage:
#   ./fix-iam-403.sh                       # auto-detect project + user
#   GOG_PROJECT_ID=my-proj ./fix-iam-403.sh   # (GWS_PROJECT_ID still accepted)
#   GOG_USER_EMAIL=me@x.com ./fix-iam-403.sh  # (GWS_USER_EMAIL still accepted)
#   ./fix-iam-403.sh --enable-apis         # also `gcloud services enable`
#                                          # the common workspace APIs

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_gog.sh
source "$SCRIPT_DIR/_gog.sh"

info() { printf "→ %s\n" "$*"; }
warn() { printf "⚠ %s\n" "$*" >&2; }
die()  { printf "❌ %s\n" "$*" >&2; exit 1; }

ENABLE_APIS=0
for arg in "$@"; do
  case "$arg" in
    --enable-apis) ENABLE_APIS=1 ;;
    -h|--help)
      sed -n '1,25p' "$0"; exit 0 ;;
  esac
done

( gog_require ) || die "gog missing or too old — $GOG_INSTALL_HINT"
command -v gcloud >/dev/null || die "gcloud not installed — brew install google-cloud-sdk"
command -v jq     >/dev/null || die "jq not installed — brew install jq"

# Project: from $GOG_PROJECT_ID, else from gog's stored OAuth client. gog keeps
# a flat {client_id, client_secret}: the project *number* is the client_id
# prefix, which gcloud accepts wherever it takes a project.
PROJECT="${GOG_PROJECT_ID:-${GWS_PROJECT_ID:-}}"
if [ -z "$PROJECT" ]; then
  CREDS=$("$GOG_BIN" auth status --json --no-input 2>/dev/null | jq -r '.account.credentials_path // empty')
  if [ -n "$CREDS" ] && [ -f "$CREDS" ]; then
    PROJECT=$(jq -r '(.installed // .web // .) | (.project_id // ((.client_id // "") | split("-")[0])) // empty' "$CREDS" 2>/dev/null)
  fi
fi
[ -n "$PROJECT" ] || die "could not determine project_id; set GOG_PROJECT_ID=… and retry"

# User email: every cheap lookup endpoint may itself 403 (that's what we're
# fixing), so cascade through several options.
EMAIL="${GOG_USER_EMAIL:-${GWS_USER_EMAIL:-}}"

# 1. Gmail getProfile — works when the 403 wave spares this one endpoint
if [ -z "$EMAIL" ]; then
  EMAIL=$(gog_email 2>/dev/null || true)
fi

# 2. Calendar — pick any event where an attendee has `self:true`
if [ -z "$EMAIL" ]; then
  EMAIL=$(gog_api calendar v3 events.list \
          --params '{"calendarId":"primary","maxResults":25,"singleEvents":true,"orderBy":"startTime","timeMin":"1970-01-01T00:00:00Z"}' \
          2>/dev/null \
          | jq -r '.items[]?.attendees[]? | select(.self==true) | .email' 2>/dev/null \
          | head -1 || true)
fi

# 3. gcloud's active account — only correct if it matches the gog user, but
#    a useful default to propose.
if [ -z "$EMAIL" ]; then
  GCLOUD_ACCOUNT=$(gcloud config get-value account 2>/dev/null | grep -v '^$' || true)
  if [ -n "$GCLOUD_ACCOUNT" ] && [ "$GCLOUD_ACCOUNT" != "(unset)" ]; then
    EMAIL="$GCLOUD_ACCOUNT"
    warn "using gcloud's active account as the gog user: $EMAIL"
    warn "override with GOG_USER_EMAIL=… if that's wrong."
  fi
fi

# 4. Interactive prompt — last resort
if [ -z "$EMAIL" ] && [ -t 0 ]; then
  printf "Enter the Workspace email of the gog user: "
  read -r EMAIL
fi

[ -n "$EMAIL" ] || die "could not determine user email; retry with GOG_USER_EMAIL=you@example.com"

info "project: $PROJECT"
info "user:    $EMAIL"

# Ensure gcloud is logged in (interactive — will open browser once).
ACTIVE=$(gcloud config get-value account 2>/dev/null || true)
if [ -z "$ACTIVE" ] || [ "$ACTIVE" = "(unset)" ]; then
  info "gcloud not authenticated — running: gcloud auth login"
  gcloud auth login
  ACTIVE=$(gcloud config get-value account 2>/dev/null || true)
fi

if [ -n "$ACTIVE" ] && [ "$ACTIVE" != "$EMAIL" ]; then
  warn "gcloud is logged in as $ACTIVE (≠ $EMAIL)"
  warn "IAM grant will be applied as $ACTIVE; ensure that account owns $PROJECT."
fi

# Grant the role (idempotent — gcloud silently no-ops if already bound).
info "granting roles/serviceusage.serviceUsageConsumer to user:$EMAIL on $PROJECT"
gcloud projects add-iam-policy-binding "$PROJECT" \
  --member="user:$EMAIL" \
  --role=roles/serviceusage.serviceUsageConsumer \
  --condition=None \
  --quiet >/dev/null

# Optionally enable the common Workspace APIs on the project.
if [ "$ENABLE_APIS" -eq 1 ]; then
  info "enabling common Workspace APIs (idempotent)"
  gcloud services enable \
    drive.googleapis.com \
    tasks.googleapis.com \
    chat.googleapis.com \
    people.googleapis.com \
    sheets.googleapis.com \
    slides.googleapis.com \
    docs.googleapis.com \
    forms.googleapis.com \
    keep.googleapis.com \
    meet.googleapis.com \
    --project="$PROJECT" --quiet || warn "one or more APIs failed to enable"
fi

info "waiting 15s for IAM propagation…"
sleep 15

# Verify: a Drive call should no longer 403.
# gog exits 6 (permission_denied) on the 403 this script is fixing.
if "$GOG_BIN" drive ls --max 1 --json --no-input >/dev/null 2>&1; then
  printf "✓ IAM elevated — Drive API now responds\n"
  exit 0
else
  warn "still 403 — propagation can take a couple minutes, or the APIs"
  warn "may need to be enabled. Retry:"
  warn "  gog drive ls --max 1"
  warn "  or re-run with: bash $(basename "$0") --enable-apis"
  exit 3
fi
