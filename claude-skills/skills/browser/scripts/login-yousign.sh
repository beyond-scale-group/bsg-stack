#!/usr/bin/env bash
set -euo pipefail

# Yousign account login helper for agent-browser.
# Saves session under the "yousign" profile for headless reuse.
#
# Usage:
#   bash login-yousign.sh [email@example.com]

PROFILE="yousign"
EMAIL="${1:-}"
URL="https://yousign.app/login"

if [ -n "$EMAIL" ]; then
  URL="https://yousign.app/login?email=${EMAIL}"
fi

command -v agent-browser >/dev/null 2>&1 || {
  echo "Error: agent-browser not installed. Run: npm install -g agent-browser" >&2
  exit 1
}

echo "Opening Yousign login in headed mode..."
echo "Complete authentication in the browser window."
echo ""

agent-browser --profile "$PROFILE" open "$URL" --headed

echo ""
echo "Waiting for login to complete (watching for yousign.app dashboard)..."
echo "You have 2 minutes to complete authentication."

agent-browser wait --url "**/yousign.app/**" --timeout 120000 2>/dev/null \
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
echo "Yousign session saved under profile '$PROFILE'."
echo "Future runs with --profile $PROFILE will reuse this session."
echo ""
echo "Test it:"
echo "  agent-browser --profile $PROFILE open https://yousign.app"
