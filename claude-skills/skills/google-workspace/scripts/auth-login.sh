#!/usr/bin/env bash
# gws auth-login.sh — launch `gws auth login`, auto-open the OAuth URL in
# Chrome (or the OS default browser), wait for the flow to complete, and
# verify the token ends up valid.
#
# Accepts pass-through flags for `gws auth login`, e.g.:
#   ./auth-login.sh
#   ./auth-login.sh --services gmail,calendar,drive
#   ./auth-login.sh --readonly
#   ./auth-login.sh --full
#   ./auth-login.sh --scopes https://www.googleapis.com/auth/drive.readonly
#
# Exits 0 if auth is valid after the flow, otherwise non-zero.

set -euo pipefail

warn() { printf "⚠ %s\n" "$*" >&2; }

if ! command -v gws >/dev/null; then
  echo "❌ gws not installed: npm install -g @googleworkspace/cli@latest" >&2
  exit 1
fi
if ! command -v jq >/dev/null; then
  echo "❌ jq not installed: brew install jq" >&2
  exit 1
fi

LOG=$(mktemp -t gws-auth-login.XXXXXX)
trap 'rm -f "$LOG"' EXIT

# Curated scope list covering every Workspace API the skill exercises.
# Kept in sync with scripts/onboard.sh (single source of truth).
#
# Why not `--full`? gws's `--full` silently drops sensitive scopes
# (chat.spaces, contacts, directory.readonly, forms.body,
# meetings.space.created) that aren't pre-registered on the project's
# OAuth consent screen. Passing the explicit list surfaces the drop:
# Google still won't grant unregistered scopes, but at least the
# request matches the user's intent.
GWS_DEFAULT_SCOPES="\
https://www.googleapis.com/auth/drive,\
https://www.googleapis.com/auth/spreadsheets,\
https://www.googleapis.com/auth/gmail.modify,\
https://www.googleapis.com/auth/calendar,\
https://www.googleapis.com/auth/documents,\
https://www.googleapis.com/auth/presentations,\
https://www.googleapis.com/auth/tasks,\
https://www.googleapis.com/auth/chat.spaces,\
https://www.googleapis.com/auth/contacts,\
https://www.googleapis.com/auth/directory.readonly,\
https://www.googleapis.com/auth/forms.body,\
https://www.googleapis.com/auth/meetings.space.created,\
openid,\
https://www.googleapis.com/auth/userinfo.email,\
https://www.googleapis.com/auth/userinfo.profile"

# If the caller didn't specify a scope-shaping flag, request our explicit
# 15-scope list. Pass `--full`, `--readonly`, `--services …`, or
# `--scopes …` to override.
HAS_SCOPE_FLAG=0
for arg in "$@"; do
  case "$arg" in
    --full|--readonly|--services|-s|--scopes) HAS_SCOPE_FLAG=1; break ;;
  esac
done
if [ "$HAS_SCOPE_FLAG" -eq 0 ]; then
  set -- --scopes "$GWS_DEFAULT_SCOPES" "$@"
  echo "→ no scope flag given; requesting the curated 15-scope BSG default"
fi

# Start `gws auth login` in the background, capturing stdout+stderr.
# The process writes the OAuth URL, then blocks on the local callback server.
gws auth login "$@" >"$LOG" 2>&1 &
LOGIN_PID=$!

# Poll the log for the URL for up to ~20s.
URL=""
for _ in $(seq 1 40); do
  if ! kill -0 "$LOGIN_PID" 2>/dev/null; then
    # login process already exited — probably an error
    break
  fi
  URL=$(grep -Eom1 'https://accounts\.google\.com/[^[:space:]]+' "$LOG" 2>/dev/null || true)
  [ -n "$URL" ] && break
  sleep 0.5
done

if [ -z "$URL" ]; then
  echo "❌ could not extract OAuth URL from gws auth login output:" >&2
  cat "$LOG" >&2
  kill "$LOGIN_PID" 2>/dev/null || true
  wait "$LOGIN_PID" 2>/dev/null || true
  exit 2
fi

# Open in Chrome (preferred), then fall back to OS-default browser.
OS="$(uname -s)"
OPENED=0
case "$OS" in
  Darwin)
    if open -a "Google Chrome" "$URL" 2>/dev/null; then
      OPENED=1
    elif open "$URL" 2>/dev/null; then
      OPENED=1
    fi
    ;;
  Linux)
    if command -v google-chrome >/dev/null && google-chrome "$URL" >/dev/null 2>&1 & then
      OPENED=1
    elif command -v chromium >/dev/null && chromium "$URL" >/dev/null 2>&1 & then
      OPENED=1
    elif command -v xdg-open >/dev/null && xdg-open "$URL" >/dev/null 2>&1; then
      OPENED=1
    fi
    ;;
  MINGW*|MSYS*|CYGWIN*)
    if start chrome "$URL" 2>/dev/null; then
      OPENED=1
    elif start "" "$URL" 2>/dev/null; then
      OPENED=1
    fi
    ;;
esac

if [ "$OPENED" -eq 1 ]; then
  echo "→ opened OAuth consent in your browser — complete the flow"
else
  echo "⚠ could not auto-open browser; paste this URL manually:"
  echo ""
  echo "  $URL"
  echo ""
fi

# Wait for the gws auth login process to finish (success = OAuth callback hit).
LOGIN_RC=0
wait "$LOGIN_PID" || LOGIN_RC=$?

# Double-check: the token is actually stored and valid.
if ! gws auth status 2>/dev/null | jq -e '.token_valid == true and .encrypted_credentials_exists == true' >/dev/null; then
  echo "⚠ gws auth still invalid after login (exit code: $LOGIN_RC)"
  gws auth status 2>/dev/null | jq '{token_valid, has_refresh_token, token_error}' >&2
  exit "${LOGIN_RC:-1}"
fi

# Verify scopes — Google's consent screen silently drops scopes the user
# doesn't tick. Mint an access token and list what was actually granted so
# the caller can see drift between requested and granted scopes.
CID=$(gws auth export --unmasked 2>/dev/null | jq -r '.client_id // empty')
CSECRET=$(gws auth export --unmasked 2>/dev/null | jq -r '.client_secret // empty')
REFRESH=$(gws auth export --unmasked 2>/dev/null | jq -r '.refresh_token // empty')
if [ -n "$CID" ] && [ -n "$CSECRET" ] && [ -n "$REFRESH" ] && command -v curl >/dev/null; then
  ACCESS=$(curl -sX POST https://oauth2.googleapis.com/token \
    -d "client_id=$CID" -d "client_secret=$CSECRET" \
    -d "refresh_token=$REFRESH" -d "grant_type=refresh_token" \
    | jq -r '.access_token // empty')
  if [ -n "$ACCESS" ]; then
    GRANTED=$(curl -s "https://oauth2.googleapis.com/tokeninfo?access_token=$ACCESS" \
              | jq -r '.scope // empty' | tr ' ' '\n' | sort -u)
    COUNT=$(printf '%s\n' "$GRANTED" | grep -c .)
    echo "→ granted $COUNT scope(s)"

    # Warn on notable omissions when the caller asked for --full or our
    # curated default list. Drops here usually mean the scope isn't
    # registered on the project's OAuth consent screen.
    REQUESTED_BROAD=0
    if printf "%s\n" "$@" | grep -q -- '--full'; then
      REQUESTED_BROAD=1
    elif printf "%s\n" "$@" | grep -q -- "$GWS_DEFAULT_SCOPES"; then
      REQUESTED_BROAD=1
    fi
    if [ "$REQUESTED_BROAD" -eq 1 ]; then
      MISSING=""
      for needle in chat. contacts people directory forms keep meet; do
        if ! printf "%s" "$GRANTED" | grep -q "$needle"; then
          MISSING="$MISSING $needle"
        fi
      done
      if [ -n "$MISSING" ]; then
        warn "consent dropped:$MISSING"
        warn "Google's consent screen shows sensitive scopes as individual"
        warn "checkboxes. Either (a) re-run and TICK EVERY BOX, or (b) add"
        warn "the missing scopes on the OAuth consent screen first:"
        warn "  bash scripts/onboard.sh --step scopes"
      fi
    fi
  fi
fi

echo "✓ gws auth valid"
exit 0
