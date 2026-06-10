#!/usr/bin/env bash
# env-setup.sh — interactive setup for the email-imap credentials file.
#
# Writes ~/.config/email-imap/credentials.env (chmod 600), auto-detects the
# IMAP host from the user's email domain, and runs a quick login test.
#
# Usage:
#   bash scripts/env-setup.sh              # interactive
#   bash scripts/env-setup.sh --check      # just verify an existing file
#   bash scripts/env-setup.sh --path PATH  # write somewhere other than the default

set -uo pipefail

DEFAULT_PATH="$HOME/.config/email-imap/credentials.env"
ENV_PATH="$DEFAULT_PATH"
CHECK_ONLY=0

while [ $# -gt 0 ]; do
  case "$1" in
    --path) ENV_PATH="$2"; shift 2 ;;
    --check) CHECK_ONLY=1; shift ;;
    -h|--help)
      sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'
      exit 0 ;;
    *) echo "unknown arg: $1" >&2; exit 1 ;;
  esac
done

ask() {
  local prompt="$1" default="${2:-}" answer
  if [ -n "$default" ]; then
    printf "%s [%s]: " "$prompt" "$default" >&2
  else
    printf "%s: " "$prompt" >&2
  fi
  read -r answer
  echo "${answer:-$default}"
}

ask_password() {
  local prompt="$1" answer
  printf "%s: " "$prompt" >&2
  stty -echo
  read -r answer
  stty echo
  printf "\n" >&2
  echo "$answer"
}

detect_host() {
  local domain="${1##*@}"
  case "$domain" in
    gmail.com|googlemail.com) echo "imap.gmail.com" ;;
    outlook.com|hotmail.com|live.com|office365.com) echo "outlook.office365.com" ;;
    icloud.com|me.com|mac.com) echo "imap.mail.me.com" ;;
    yahoo.com) echo "imap.mail.yahoo.com" ;;
    fastmail.com) echo "imap.fastmail.com" ;;
    *) echo "" ;;
  esac
}

if [ "$CHECK_ONLY" -eq 1 ]; then
  if [ ! -f "$ENV_PATH" ]; then
    echo "❌ no credentials file at $ENV_PATH" >&2
    exit 2
  fi
  perms=$(stat -f "%OLp" "$ENV_PATH" 2>/dev/null || stat -c "%a" "$ENV_PATH" 2>/dev/null)
  [ "$perms" != "600" ] && echo "⚠ permissions are $perms — should be 600" >&2
  echo "✓ file present : $ENV_PATH"
  grep -E "^IMAP_(USER|HOST|PORT)=" "$ENV_PATH" | sed 's/=.*$/=…/'
  grep -E "^IMAP_APP_PASSWORD=" "$ENV_PATH" >/dev/null && echo "IMAP_APP_PASSWORD=*** (set)"
  exit 0
fi

if [ -f "$ENV_PATH" ]; then
  echo "ℹ a credentials file already exists at $ENV_PATH" >&2
  reply=$(ask "Overwrite? [y/N]" "N")
  case "$reply" in y|Y|yes|YES) ;; *) echo "aborted"; exit 0 ;; esac
fi

echo ""
echo "── email-imap setup ────────────────────────────────────────"
USER_EMAIL=$(ask "Email address (e.g. grenoble@prizoners.com)")
[ -z "$USER_EMAIL" ] && { echo "❌ email required" >&2; exit 1; }

DETECTED_HOST=$(detect_host "$USER_EMAIL")
IMAP_HOST=$(ask "IMAP host" "${DETECTED_HOST:-imap.gmail.com}")
IMAP_PORT=$(ask "IMAP port" "993")

echo ""
echo "App password: generate one at the provider's account-security page."
echo "  • Gmail/Workspace : https://myaccount.google.com/apppasswords"
echo "  • iCloud          : https://appleid.apple.com → App-Specific Passwords"
echo "  • Outlook/M365    : https://account.microsoft.com/security → App passwords"
echo "  • Fastmail        : Settings → Privacy & Security → App Passwords"
echo ""
APP_PWD=$(ask_password "App password (input hidden)")
[ -z "$APP_PWD" ] && { echo "❌ app password required" >&2; exit 1; }

mkdir -p "$(dirname "$ENV_PATH")"
umask 077
# Quote values so unquoted spaces (e.g. Gmail app passwords like
# 'rvpe qgvf ygtq xlst') survive bash sourcing by callers. Python loaders
# strip the outer quotes.
cat > "$ENV_PATH" <<EOF
# email-imap credentials — chmod 600, do not commit
IMAP_USER="$USER_EMAIL"
IMAP_APP_PASSWORD="$APP_PWD"
IMAP_HOST="$IMAP_HOST"
IMAP_PORT="$IMAP_PORT"
EOF
chmod 600 "$ENV_PATH"

echo ""
echo "✓ wrote $ENV_PATH (chmod 600)"

echo ""
echo "→ smoke test…"
if command -v python3 >/dev/null; then
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  if [ -x "$SCRIPT_DIR/imap-doctor.sh" ] || [ -f "$SCRIPT_DIR/imap-doctor.sh" ]; then
    bash "$SCRIPT_DIR/imap-doctor.sh"
  else
    python3 -c "
import imaplib, os
m=imaplib.IMAP4_SSL('$IMAP_HOST', $IMAP_PORT)
try:
    m.login('$USER_EMAIL', '''$APP_PWD'''.replace(' ',''))
    print('✓ IMAP login successful')
    m.logout()
except Exception as e:
    print(f'❌ login failed: {e}')
    raise SystemExit(2)
"
  fi
else
  echo "⚠ python3 not found — install it then run imap-doctor.sh to verify"
fi

echo ""
echo "Setup done. Next steps:"
echo "  bash scripts/imap-folders.py                       # list folders"
echo "  python3 scripts/imap-fetch.py --since-days 60      # download"
