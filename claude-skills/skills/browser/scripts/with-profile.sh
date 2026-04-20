#!/usr/bin/env bash
set -euo pipefail

# Thin wrapper that injects --profile into agent-browser commands.
#
# Usage:
#   bash with-profile.sh <profile-name> [agent-browser args...]
#
# Examples:
#   bash with-profile.sh github open https://github.com --headed
#   bash with-profile.sh notion open https://notion.so --headed
#   bash with-profile.sh github screenshot /tmp/gh.png

if [ $# -lt 2 ]; then
  echo "Usage: with-profile.sh <profile-name> <agent-browser-command> [args...]" >&2
  echo "" >&2
  echo "Examples:" >&2
  echo "  with-profile.sh github open https://github.com --headed" >&2
  echo "  with-profile.sh notion open https://notion.so --headed" >&2
  echo "  with-profile.sh github screenshot /tmp/gh.png" >&2
  exit 1
fi

PROFILE="$1"
shift

command -v agent-browser >/dev/null 2>&1 || {
  echo "Error: agent-browser not installed. Run: npm install -g agent-browser" >&2
  exit 1
}

exec agent-browser --profile "$PROFILE" "$@"
