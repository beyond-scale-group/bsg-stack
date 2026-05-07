#!/usr/bin/env bash
set -euo pipefail

# Onboard: install clasp, authenticate, verify.
# Usage:
#   bash onboard.sh              # run all steps
#   bash onboard.sh --step install
#   bash onboard.sh --step login
#   bash onboard.sh --step verify

STEP="${1:-all}"
[ "$STEP" = "--step" ] && STEP="${2:-all}"

step_install() {
  echo "=== Step 1/3: Install clasp ==="
  if command -v clasp >/dev/null 2>&1; then
    local ver
    ver=$(clasp --version 2>/dev/null || echo "unknown")
    echo "✓ clasp already installed (version: $ver)"
  else
    echo "Installing @google/clasp globally..."
    npm install -g @google/clasp
    echo "✓ clasp installed (version: $(clasp --version 2>/dev/null))"
  fi
}

step_login() {
  echo "=== Step 2/3: Authenticate ==="
  if [ -f ~/.clasprc.json ]; then
    echo "✓ ~/.clasprc.json exists — credentials found"
    echo "  (To re-authenticate, run: clasp login)"
  else
    echo "Opening browser for Google OAuth..."
    echo "  Grant access to manage your Apps Script projects."
    clasp login
    if [ -f ~/.clasprc.json ]; then
      echo "✓ Login successful"
    else
      echo "✗ Login failed — ~/.clasprc.json not created"
      exit 2
    fi
  fi
}

step_verify() {
  echo "=== Step 3/3: Verify ==="
  if ! command -v clasp >/dev/null 2>&1; then
    echo "✗ clasp binary not found"
    exit 2
  fi
  if [ ! -f ~/.clasprc.json ]; then
    echo "✗ Not authenticated (no ~/.clasprc.json)"
    exit 2
  fi
  echo "✓ clasp is installed and authenticated"
  echo "  Version: $(clasp --version 2>/dev/null)"
  echo ""
  echo "Next steps:"
  echo "  clasp clone <scriptId>   — clone an existing project"
  echo "  clasp create --title X   — create a new project"
}

case "$STEP" in
  all)
    step_install
    echo ""
    step_login
    echo ""
    step_verify
    ;;
  install) step_install ;;
  login)   step_login ;;
  verify)  step_verify ;;
  *)
    echo "Unknown step: $STEP"
    echo "Valid steps: install, login, verify"
    exit 1
    ;;
esac
