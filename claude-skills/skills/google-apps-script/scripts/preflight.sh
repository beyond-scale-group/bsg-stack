#!/usr/bin/env bash
set -euo pipefail

# Preflight check for clasp — run once per session before any clasp command.
# Auto-triggers onboard.sh when clasp is missing or not authenticated.
#
# Exit codes: 0 = ready, 1 = project context missing (warning only),
#             2 = fatal (binary or auth failed after remediation).

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ONBOARD="$SCRIPT_DIR/onboard.sh"

# Resolve credentials file: CLASP_AUTH > local .clasprc.json > global
if [ -n "${CLASP_AUTH:-}" ]; then
  CREDS_FILE="$CLASP_AUTH"
elif [ -f .clasprc.json ]; then
  CREDS_FILE=".clasprc.json"
else
  CREDS_FILE="$HOME/.clasprc.json"
fi

# --- 1. Binary ---
if ! command -v clasp >/dev/null 2>&1; then
  echo "⚠ clasp not found — running onboard to install..."
  bash "$ONBOARD" --step install || true
  if ! command -v clasp >/dev/null 2>&1; then
    echo "✗ clasp still not found after install attempt"
    exit 2
  fi
fi

echo "✓ clasp $(clasp --version 2>/dev/null || echo '(version unknown)')"

# --- 2. Auth ---
if [ ! -f "$CREDS_FILE" ]; then
  echo "⚠ Not authenticated (checked $CREDS_FILE) — running onboard login..."
  bash "$ONBOARD" --step login || true
  if [ ! -f "$CREDS_FILE" ]; then
    echo "✗ Authentication failed — $CREDS_FILE not created"
    exit 2
  fi
fi

echo "✓ Authenticated ($CREDS_FILE)"

# --- 3. Project context (informational — not fatal) ---
if [ -f .clasp.json ]; then
  script_id=$(grep -o '"scriptId"[[:space:]]*:[[:space:]]*"[^"]*"' .clasp.json 2>/dev/null \
    | head -1 | sed 's/.*"scriptId"[[:space:]]*:[[:space:]]*"//' | sed 's/"//')
  echo "✓ Project bound (scriptId: ${script_id:0:16}...)"
else
  echo "ℹ No .clasp.json — clone a project or cd to one before push/pull/run"
fi

echo ""
echo "Preflight passed — ready to use clasp."
