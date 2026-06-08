#!/usr/bin/env bash
# imap-doctor.sh — preflight check for the email-imap skill.
#
# Verifies python3 is available, env vars (or credentials.env) are present,
# the IMAP server is TCP-reachable, login succeeds, and INBOX selects.
#
#   bash scripts/imap-doctor.sh             # full report
#   bash scripts/imap-doctor.sh --quiet     # exit codes only, silent on green
#   bash scripts/imap-doctor.sh --env-file PATH
#
# Exit codes:
#   0  all green
#   1  warning (file perms, missing optional bits)
#   2  hard failure (login refused, host unreachable)

set -uo pipefail

QUIET=0
ENV_FILE=""

while [ $# -gt 0 ]; do
  case "$1" in
    --quiet) QUIET=1; shift ;;
    --env-file) ENV_FILE="$2"; shift 2 ;;
    -h|--help)
      sed -n '2,14p' "$0" | sed 's/^# \{0,1\}//'
      exit 0 ;;
    *) echo "unknown arg: $1" >&2; exit 1 ;;
  esac
done

BUF=$(mktemp -t imap-doctor.XXXXXX)
trap 'rm -f "$BUF"' EXIT
say()  { printf "%s\n" "$*" >>"$BUF"; }
ok()   { say "  ✓ $*"; }
warn() { say "  ⚠ $*"; }
bad()  { say "  ✗ $*"; }

EXIT=0
WARN=0

say "[python] runtime"
if command -v python3 >/dev/null; then
  ok "python3 $(python3 --version 2>&1 | awk '{print $2}')"
else
  bad "python3 not found — install python 3.7+"
  EXIT=2
fi

# Load .env if present, before checking env vars
DEFAULT_ENV="$HOME/.config/email-imap/credentials.env"
CHOSEN_ENV=""
if [ -n "$ENV_FILE" ] && [ -f "$ENV_FILE" ]; then
  CHOSEN_ENV="$ENV_FILE"
elif [ -n "${IMAP_ENV_FILE:-}" ] && [ -f "$IMAP_ENV_FILE" ]; then
  CHOSEN_ENV="$IMAP_ENV_FILE"
elif [ -f "$DEFAULT_ENV" ]; then
  CHOSEN_ENV="$DEFAULT_ENV"
elif [ -f ".env" ]; then
  CHOSEN_ENV=".env"
fi

say ""
say "[creds] credentials"
if [ -n "$CHOSEN_ENV" ]; then
  ok "loaded $CHOSEN_ENV"
  perms=$(stat -f "%OLp" "$CHOSEN_ENV" 2>/dev/null || stat -c "%a" "$CHOSEN_ENV" 2>/dev/null)
  if [ "$perms" != "600" ]; then
    warn "perms are $perms — should be 600 (run: chmod 600 $CHOSEN_ENV)"
    WARN=1
  fi
  # Parse KEY=VALUE without shell sourcing — unquoted spaces in values
  # (e.g. Gmail app passwords) would otherwise be interpreted as commands.
  while IFS= read -r kv_line; do
    case "$kv_line" in ""|\#*) continue ;; esac
    key="${kv_line%%=*}"
    val="${kv_line#*=}"
    # Strip a single layer of surrounding quotes
    case "$val" in
      \"*\") val="${val#\"}"; val="${val%\"}" ;;
      \'*\') val="${val#\'}"; val="${val%\'}" ;;
    esac
    # Don't override already-exported vars
    if [ -z "$(eval echo "\${$key+x}")" ]; then
      export "$key=$val"
    fi
  done < "$CHOSEN_ENV"
else
  warn "no credentials file found at $DEFAULT_ENV (relying on env vars)"
  WARN=1
fi

[ -n "${IMAP_USER:-}" ]         && ok "IMAP_USER = $IMAP_USER"           || { bad "IMAP_USER missing";         EXIT=2; }
[ -n "${IMAP_APP_PASSWORD:-}" ] && ok "IMAP_APP_PASSWORD = (set, $(printf %s "$IMAP_APP_PASSWORD" | wc -c | tr -d ' ') chars)" \
                                || { bad "IMAP_APP_PASSWORD missing";  EXIT=2; }

# Host auto-detect (mirrors imap-fetch.py logic)
detect_host() {
  case "${1##*@}" in
    gmail.com|googlemail.com) echo "imap.gmail.com" ;;
    outlook.com|hotmail.com|live.com|office365.com) echo "outlook.office365.com" ;;
    icloud.com|me.com|mac.com) echo "imap.mail.me.com" ;;
    yahoo.com) echo "imap.mail.yahoo.com" ;;
    fastmail.com) echo "imap.fastmail.com" ;;
    *) echo "" ;;
  esac
}

if [ -z "${IMAP_HOST:-}" ] && [ -n "${IMAP_USER:-}" ]; then
  IMAP_HOST=$(detect_host "$IMAP_USER")
fi
IMAP_PORT="${IMAP_PORT:-993}"

if [ -n "${IMAP_HOST:-}" ]; then
  ok "IMAP_HOST = $IMAP_HOST"
  ok "IMAP_PORT = $IMAP_PORT"
else
  bad "IMAP_HOST missing and no default for domain '${IMAP_USER##*@}'"
  EXIT=2
fi

if [ "$EXIT" -ne 2 ]; then
  say ""
  say "[net] connectivity + login"

  if python3 -c "import socket,sys; s=socket.socket(); s.settimeout(5); s.connect(('${IMAP_HOST}', ${IMAP_PORT})); s.close()" 2>/dev/null; then
    ok "TCP reachable: ${IMAP_HOST}:${IMAP_PORT}"
  else
    bad "TCP unreachable: ${IMAP_HOST}:${IMAP_PORT}"
    EXIT=2
  fi

  if [ "$EXIT" -ne 2 ]; then
    LOGIN_RESULT=$(IMAP_USER="$IMAP_USER" IMAP_APP_PASSWORD="$IMAP_APP_PASSWORD" \
        IMAP_HOST="$IMAP_HOST" IMAP_PORT="$IMAP_PORT" \
        python3 - <<'PYEOF' 2>&1
import imaplib, os, sys
u = os.environ["IMAP_USER"]
p = os.environ["IMAP_APP_PASSWORD"].replace(" ", "")
host = os.environ["IMAP_HOST"]
port = int(os.environ["IMAP_PORT"])
try:
    m = imaplib.IMAP4_SSL(host, port)
    m.login(u, p)
    typ, data = m.select("INBOX", readonly=True)
    if typ == "OK" and data and data[0]:
        print(f"OK {data[0].decode()}")
    else:
        print("OK ?")
    m.logout()
except imaplib.IMAP4.error as e:
    print(f"LOGIN_ERR {e}")
    sys.exit(1)
except Exception as e:
    print(f"ERR {e}")
    sys.exit(1)
PYEOF
)
    case "$LOGIN_RESULT" in
      "OK "*) ok "IMAP login + INBOX select OK (${LOGIN_RESULT#OK } messages)" ;;
      "LOGIN_ERR "*) bad "login refused: ${LOGIN_RESULT#LOGIN_ERR }"; EXIT=2 ;;
      *) bad "$LOGIN_RESULT"; EXIT=2 ;;
    esac
  fi
fi

[ "$EXIT" -eq 0 ] && [ "$WARN" -eq 1 ] && EXIT=1

if [ "$QUIET" -eq 1 ] && [ "$EXIT" -eq 0 ]; then
  exit 0
fi
cat "$BUF"
exit "$EXIT"
