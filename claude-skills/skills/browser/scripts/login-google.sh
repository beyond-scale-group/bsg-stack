#!/usr/bin/env bash
set -euo pipefail

# Google account login helper for agent-browser.
# Saves session under the "google" profile for headless reuse.
#
# Usage:
#   bash login-google.sh [email@example.com]

PROFILE="google"
EMAIL="${1:-}"
URL="https://accounts.google.com"

if [ -n "$EMAIL" ]; then
  URL="https://accounts.google.com/AccountChooser?Email=${EMAIL}"
fi

command -v agent-browser >/dev/null 2>&1 || {
  echo "Error: agent-browser not installed. Run: npm install -g agent-browser" >&2
  exit 1
}

echo "Opening Google login in headed mode..."
echo "Complete authentication in the browser window (including 2FA / passkey)."
echo ""

agent-browser --profile "$PROFILE" open "$URL" --headed

echo ""
echo "Waiting for login to complete (watching for myaccount.google.com or accounts.google.com/Default)..."
echo "You have 2 minutes to complete authentication."

agent-browser wait --url "**/myaccount.google.com/**" --timeout 120000 2>/dev/null \
  || agent-browser wait --url "**/accounts.google.com/Default**" --timeout 120000 2>/dev/null \
  || agent-browser wait --url "**/console.cloud.google.com/**" --timeout 120000 2>/dev/null \
  || {
    echo ""
    echo "Warning: timed out waiting for expected post-login URL."
    echo "If you completed login, the session may still be saved."
  }

CURRENT_URL=$(agent-browser get url 2>/dev/null || echo "unknown")
echo ""
echo "Current URL: $CURRENT_URL"

agent-browser close 2>/dev/null || true

echo ""
echo "Google session saved under profile '$PROFILE'."
echo "Future runs with --profile $PROFILE will reuse this session."
echo ""
echo "Test it:"
echo "  agent-browser --profile $PROFILE open https://console.cloud.google.com"
