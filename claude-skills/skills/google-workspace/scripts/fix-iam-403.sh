#!/usr/bin/env bash
# fix-iam-403.sh — grant the current gws user
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
#   GWS_PROJECT_ID=my-proj ./fix-iam-403.sh
#   GWS_USER_EMAIL=me@x.com ./fix-iam-403.sh
#   ./fix-iam-403.sh --enable-apis         # also `gcloud services enable`
#                                          # the common workspace APIs

set -euo pipefail

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

command -v gws    >/dev/null || die "gws not installed"
command -v gcloud >/dev/null || die "gcloud not installed — brew install google-cloud-sdk"
command -v jq     >/dev/null || die "jq not installed — brew install jq"

# Project: from $GWS_PROJECT_ID, else from gws auth status.
PROJECT="${GWS_PROJECT_ID:-$(gws auth status 2>/dev/null | jq -r '.project_id // empty')}"
[ -n "$PROJECT" ] || die "could not determine project_id; set GWS_PROJECT_ID=… and retry"

# User email: every cheap lookup endpoint may itself 403 (that's what we're
# fixing), so cascade through several options.
EMAIL="${GWS_USER_EMAIL:-}"

# 1. Gmail getProfile — works when the 403 wave spares this one endpoint
if [ -z "$EMAIL" ]; then
  EMAIL=$(gws gmail users getProfile --params '{"userId":"me"}' 2>/dev/null \
          | jq -r '.emailAddress // empty' 2>/dev/null || true)
fi

# 2. Calendar — pick any event where an attendee has `self:true`
if [ -z "$EMAIL" ]; then
  EMAIL=$(gws calendar events list \
          --params '{"calendarId":"primary","maxResults":25,"singleEvents":true,"orderBy":"startTime","timeMin":"1970-01-01T00:00:00Z"}' \
          2>/dev/null \
          | jq -r '.items[]?.attendees[]? | select(.self==true) | .email' 2>/dev/null \
          | head -1 || true)
fi

# 3. gcloud's active account — only correct if it matches the gws user, but
#    a useful default to propose.
if [ -z "$EMAIL" ]; then
  GCLOUD_ACCOUNT=$(gcloud config get-value account 2>/dev/null | grep -v '^$' || true)
  if [ -n "$GCLOUD_ACCOUNT" ] && [ "$GCLOUD_ACCOUNT" != "(unset)" ]; then
    EMAIL="$GCLOUD_ACCOUNT"
    warn "using gcloud's active account as the gws user: $EMAIL"
    warn "override with GWS_USER_EMAIL=… if that's wrong."
  fi
fi

# 4. Interactive prompt — last resort
if [ -z "$EMAIL" ] && [ -t 0 ]; then
  printf "Enter the Workspace email of the gws user: "
  read -r EMAIL
fi

[ -n "$EMAIL" ] || die "could not determine user email; retry with GWS_USER_EMAIL=you@example.com"

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
if gws drive files list --params '{"pageSize":1,"fields":"files(id)"}' 2>/dev/null \
   | jq -e 'has("files")' >/dev/null 2>&1; then
  printf "✓ IAM elevated — Drive API now responds\n"
  exit 0
else
  warn "still 403 — propagation can take a couple minutes, or the APIs"
  warn "may need to be enabled. Retry:"
  warn "  gws drive files list --params '{\"pageSize\":1}'"
  warn "  or re-run with: bash $(basename "$0") --enable-apis"
  exit 3
fi
