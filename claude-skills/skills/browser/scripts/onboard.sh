#!/usr/bin/env bash
set -euo pipefail

# BSG browser onboarding — log in to all services, save profiles for reuse.
#
# Walks the user through headed login for each BSG service, one at a time.
# Each login saves a named profile so future agent-browser calls can replay
# the session headlessly.
#
# Usage:
#   bash onboard.sh                  # full onboarding (all services + Chrome check)
#   bash onboard.sh --step google    # single service
#   bash onboard.sh --step chrome    # verify Chrome extension + native messaging
#   bash onboard.sh --list           # show services and profile status
#   bash onboard.sh --check          # verify all profiles are logged in + Chrome

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# ── Service catalog ──────────────────────────────────────────────────────
# Each entry: name|profile|login_url|post_login_pattern|description
SERVICES=(
  "google|google|https://accounts.google.com|**/myaccount.google.com/**|Google (Gmail, Drive, GCP Console)"
  "github|github|https://github.com/login|**/github.com|GitHub"
  "hubspot|hubspot|https://app.hubspot.com/login|**/app.hubspot.com/**|HubSpot (CRM, Marketing, Sales)"
  "yousign|yousign|https://yousign.app/login|**/yousign.app/**|Yousign (e-signatures)"
)

TIMEOUT=120000  # 2 minutes per login

# Chrome extension ID (Claude in Chrome)
CHROME_EXTENSION_ID="fcoeoabgfenejglbffodgkkbkcdhcgfn"

# ── Helpers ──────────────────────────────────────────────────────────────

parse_field() { echo "$1" | cut -d'|' -f"$2"; }

check_agent_browser() {
  command -v agent-browser >/dev/null 2>&1 || {
    echo "Error: agent-browser not installed." >&2
    echo "  npm install -g agent-browser && agent-browser install" >&2
    exit 1
  }
}

check_chrome_integration() {
  local all_ok=true

  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "  Step: Chrome integration (Claude in Chrome)"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""

  # 1. Check Claude Code version
  printf "  Claude Code version: "
  if command -v claude >/dev/null 2>&1; then
    local cc_version
    cc_version=$(claude --version 2>/dev/null | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' || echo "unknown")
    echo "$cc_version"
  else
    echo "NOT FOUND"
    echo "    Install: https://claude.com/claude-code"
    all_ok=false
  fi

  # 2. Check Chrome extension
  printf "  Chrome extension:    "
  local ext_found=false
  local ext_dir=""

  if [[ "$(uname)" == "Darwin" ]]; then
    # macOS: check both Chrome and Edge
    for browser_dir in \
      "$HOME/Library/Application Support/Google/Chrome" \
      "$HOME/Library/Application Support/Microsoft Edge"; do
      if [ -d "$browser_dir" ]; then
        # Search across all profiles (Default, Profile 1, etc.)
        local match
        match=$(find "$browser_dir" -path "*/Extensions/$CHROME_EXTENSION_ID" -maxdepth 4 2>/dev/null | head -1)
        if [ -n "$match" ]; then
          ext_found=true
          local ext_version
          ext_version=$(ls -1 "$(dirname "$match")/$CHROME_EXTENSION_ID/" 2>/dev/null | sort -V | tail -1 | sed 's/_0$//')
          echo "OK (v${ext_version:-unknown})"
          break
        fi
      fi
    done
  elif [[ "$(uname)" == "Linux" ]]; then
    for browser_dir in \
      "$HOME/.config/google-chrome" \
      "$HOME/.config/microsoft-edge"; do
      if [ -d "$browser_dir" ]; then
        local match
        match=$(find "$browser_dir" -path "*/Extensions/$CHROME_EXTENSION_ID" -maxdepth 4 2>/dev/null | head -1)
        if [ -n "$match" ]; then
          ext_found=true
          local ext_version
          ext_version=$(ls -1 "$(dirname "$match")/$CHROME_EXTENSION_ID/" 2>/dev/null | sort -V | tail -1 | sed 's/_0$//')
          echo "OK (v${ext_version:-unknown})"
          break
        fi
      fi
    done
  fi

  if [ "$ext_found" = false ]; then
    echo "NOT FOUND"
    echo "    Install from Chrome Web Store:"
    echo "    https://chromewebstore.google.com/detail/claude/$CHROME_EXTENSION_ID"
    all_ok=false
  fi

  # 3. Check native messaging host
  printf "  Native messaging:    "
  local nmh_found=false

  if [[ "$(uname)" == "Darwin" ]]; then
    for nmh_path in \
      "$HOME/Library/Application Support/Google/Chrome/NativeMessagingHosts/com.anthropic.claude_code_browser_extension.json" \
      "$HOME/Library/Application Support/Microsoft Edge/NativeMessagingHosts/com.anthropic.claude_code_browser_extension.json"; do
      if [ -f "$nmh_path" ]; then
        nmh_found=true
        echo "OK"
        break
      fi
    done
  elif [[ "$(uname)" == "Linux" ]]; then
    for nmh_path in \
      "$HOME/.config/google-chrome/NativeMessagingHosts/com.anthropic.claude_code_browser_extension.json" \
      "$HOME/.config/microsoft-edge/NativeMessagingHosts/com.anthropic.claude_code_browser_extension.json"; do
      if [ -f "$nmh_path" ]; then
        nmh_found=true
        echo "OK"
        break
      fi
    done
  fi

  if [ "$nmh_found" = false ]; then
    echo "NOT FOUND"
    echo "    Run 'claude --chrome' once to generate the native messaging host config,"
    echo "    then restart Chrome."
    all_ok=false
  fi

  echo ""
  if [ "$all_ok" = true ]; then
    echo "  Chrome integration is ready. Use 'claude --chrome' or '/chrome' in-session."
  else
    echo "  Chrome integration needs setup. Follow the steps above, then re-run:"
    echo "    bash onboard.sh --step chrome"
  fi
  echo ""

  [ "$all_ok" = true ]
}

list_services() {
  echo "BSG browser profiles:"
  echo ""
  printf "  %-12s %-12s %s\n" "SERVICE" "PROFILE" "DESCRIPTION"
  printf "  %-12s %-12s %s\n" "-------" "-------" "-----------"
  for entry in "${SERVICES[@]}"; do
    local name profile login_url pattern desc
    name=$(parse_field "$entry" 1)
    profile=$(parse_field "$entry" 2)
    desc=$(parse_field "$entry" 5)
    printf "  %-12s %-12s %s\n" "$name" "$profile" "$desc"
  done
  printf "  %-12s %-12s %s\n" "chrome" "—" "Chrome integration (extension + native messaging)"
}

check_profiles() {
  echo "Checking saved profiles..."
  echo ""
  local all_ok=true
  for entry in "${SERVICES[@]}"; do
    local name profile login_url pattern desc
    name=$(parse_field "$entry" 1)
    profile=$(parse_field "$entry" 2)
    login_url=$(parse_field "$entry" 3)
    pattern=$(parse_field "$entry" 4)
    desc=$(parse_field "$entry" 5)

    # Try opening the login URL with the profile in headless mode
    # and check if we land on a post-login page (not redirected to login)
    printf "  %-12s " "$name"
    if agent-browser --profile "$profile" open "$login_url" 2>/dev/null; then
      sleep 2
      local current_url
      current_url=$(agent-browser get url 2>/dev/null || echo "")
      agent-browser close 2>/dev/null || true
      if echo "$current_url" | grep -qi "login\|signin\|authenticate"; then
        echo "NOT LOGGED IN  ($current_url)"
        all_ok=false
      else
        echo "OK  ($current_url)"
      fi
    else
      echo "FAILED (could not open)"
      all_ok=false
    fi
  done

  # Also check Chrome integration
  echo ""
  echo "Checking Chrome integration..."
  echo ""
  if ! check_chrome_integration 2>/dev/null; then
    all_ok=false
  fi

  if [ "$all_ok" = true ]; then
    echo "All profiles are logged in and Chrome integration is ready."
  else
    echo "Some items need attention. Run: bash onboard.sh"
  fi
}

login_service() {
  local name="$1" profile="$2" login_url="$3" pattern="$4" desc="$5"

  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "  Step: $desc"
  echo "  Profile: $profile"
  echo "  URL: $login_url"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""
  echo "A browser window will open. Log in and complete any 2FA prompts."
  echo "You have 2 minutes."
  echo ""

  agent-browser --profile "$profile" open "$login_url" --headed

  # Wait for post-login URL pattern
  if agent-browser wait --url "$pattern" --timeout "$TIMEOUT" 2>/dev/null; then
    local current_url
    current_url=$(agent-browser get url 2>/dev/null || echo "unknown")
    echo ""
    echo "  Login detected: $current_url"
  else
    local current_url
    current_url=$(agent-browser get url 2>/dev/null || echo "unknown")
    echo ""
    echo "  Warning: timed out waiting for post-login URL."
    echo "  Current URL: $current_url"
    echo "  The session may still be saved if you completed login."
  fi

  agent-browser close 2>/dev/null || true

  echo "  Profile '$profile' saved."
  echo ""
}

# ── Main ─────────────────────────────────────────────────────────────────

check_agent_browser

# Parse arguments
SINGLE_STEP=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --list)
      list_services
      exit 0
      ;;
    --check)
      check_profiles
      exit 0
      ;;
    --step)
      SINGLE_STEP="$2"
      shift 2
      ;;
    *)
      echo "Usage: onboard.sh [--step <service>] [--list] [--check]" >&2
      exit 1
      ;;
  esac
done

if [ -n "$SINGLE_STEP" ]; then
  if [ "$SINGLE_STEP" = "chrome" ]; then
    check_chrome_integration
    exit $?
  fi
  # Run a single service
  found=false
  for entry in "${SERVICES[@]}"; do
    name=$(parse_field "$entry" 1)
    if [ "$name" = "$SINGLE_STEP" ]; then
      login_service \
        "$name" \
        "$(parse_field "$entry" 2)" \
        "$(parse_field "$entry" 3)" \
        "$(parse_field "$entry" 4)" \
        "$(parse_field "$entry" 5)"
      found=true
      break
    fi
  done
  if [ "$found" = false ]; then
    echo "Unknown service: $SINGLE_STEP" >&2
    echo "Available services:" >&2
    for entry in "${SERVICES[@]}"; do
      echo "  $(parse_field "$entry" 1)" >&2
    done
    echo "  chrome" >&2
    exit 1
  fi
else
  # Full onboarding — all services in order
  echo ""
  echo "╔══════════════════════════════════════════════════════════════╗"
  echo "║             BSG Browser Onboarding                         ║"
  echo "╠══════════════════════════════════════════════════════════════╣"
  echo "║  Log in to each BSG service once. A browser window will    ║"
  echo "║  open for each service — complete login + 2FA in the       ║"
  echo "║  window. Sessions are saved as named profiles for          ║"
  echo "║  automatic headless reuse.                                 ║"
  echo "╚══════════════════════════════════════════════════════════════╝"
  echo ""
  total=$(( ${#SERVICES[@]} + 1 ))  # services + Chrome check
  echo "Steps to complete: $total"
  for entry in "${SERVICES[@]}"; do
    echo "  - $(parse_field "$entry" 5)"
  done
  echo "  - Chrome integration (extension + native messaging)"
  echo ""

  completed=0
  for entry in "${SERVICES[@]}"; do
    login_service \
      "$(parse_field "$entry" 1)" \
      "$(parse_field "$entry" 2)" \
      "$(parse_field "$entry" 3)" \
      "$(parse_field "$entry" 4)" \
      "$(parse_field "$entry" 5)"
    completed=$((completed + 1))
    remaining=$(( total - completed ))
    if [ "$remaining" -gt 0 ]; then
      echo "  ($remaining step(s) remaining)"
    fi
  done

  # Final step: Chrome integration check
  check_chrome_integration || true

  echo ""
  echo "╔══════════════════════════════════════════════════════════════╗"
  echo "║  Onboarding complete!                                      ║"
  echo "╠══════════════════════════════════════════════════════════════╣"
  echo "║  All profiles saved. Future agent-browser calls using      ║"
  echo "║  --profile <name> will reuse these sessions headlessly.    ║"
  echo "║  Chrome integration checked — use claude --chrome or       ║"
  echo "║  /chrome in-session for anti-bot fallback.                 ║"
  echo "╚══════════════════════════════════════════════════════════════╝"
  echo ""
  echo "Profiles created:"
  for entry in "${SERVICES[@]}"; do
    printf "  %-12s -> %s\n" "$(parse_field "$entry" 2)" "$(parse_field "$entry" 5)"
  done
  echo ""
  echo "Verify with:  bash onboard.sh --check"
  echo "Re-run one:   bash onboard.sh --step <service>"
  echo "              bash onboard.sh --step chrome"
fi
