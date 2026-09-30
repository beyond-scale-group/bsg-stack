#!/usr/bin/env bash
# auth-login.sh — authorize a Google account for gog with the BSG service set,
# then verify the stored refresh token and report which services were granted.
#
# Thin wrapper around `gog auth add`: gog opens the browser itself, keeps the
# tokens in the OS keyring, and supports several accounts side by side (pick
# one later with `--account` / GOG_ACCOUNT / `gog auth alias set`).
#
# Usage:
#   ./auth-login.sh you@example.com
#   ./auth-login.sh you@example.com --services gmail,calendar,drive
#   ./auth-login.sh you@example.com --readonly
#   ./auth-login.sh you@example.com --manual          # headless: paste the redirect URL
#   GOG_ACCOUNT=you@example.com ./auth-login.sh       # email from the environment
#
# Any other flag is passed through to `gog auth add` (e.g. --gmail-scope send,
# --drive-scope readonly, --client NAME). Without --services the full BSG set
# below is requested; --force-consent is added so Google re-issues a refresh
# token that covers every service.
#
# Exit codes: 0 auth valid after the flow, 1 auth failed, 3 gog missing/too old.
#
# Part of the BSG google-workspace skill.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_gog.sh
source "$SCRIPT_DIR/_gog.sh"

warn() { printf "⚠ %s\n" "$*" >&2; }

command -v jq >/dev/null || { echo "❌ jq not installed: brew install jq" >&2; exit 1; }
gog_require

# Single source of truth for the services the skill exercises (onboard.sh and
# doctor.sh read this via `auth-login.sh --print-services`).
BSG_SERVICES="gmail,calendar,drive,docs,sheets,slides,contacts,tasks,chat,forms,meet,people"

if [[ "${1:-}" == "--print-services" ]]; then
  printf '%s\n' "$BSG_SERVICES"
  exit 0
fi

# ---------- split the email off the pass-through flags ----------
EMAIL=""
PASS=()
for arg in "$@"; do
  if [[ -z "$EMAIL" && "$arg" == *@* && "$arg" != -* ]]; then
    EMAIL="$arg"
  else
    PASS+=("$arg")
  fi
done
EMAIL="${EMAIL:-${GOG_ACCOUNT:-}}"
if [[ -z "$EMAIL" || "$EMAIL" != *@* ]]; then
  echo "❌ account email required: auth-login.sh you@example.com  (or set GOG_ACCOUNT)" >&2
  exit 1
fi

HAS_SERVICES=0
for arg in ${PASS[@]+"${PASS[@]}"}; do
  case "$arg" in --services|--services=*) HAS_SERVICES=1 ;; esac
done
if [[ "$HAS_SERVICES" -eq 0 ]]; then
  PASS+=(--services "$BSG_SERVICES" --force-consent)
  echo "→ no --services given; requesting the BSG set: $BSG_SERVICES"
fi

# ---------- run the OAuth flow ----------
LOGIN_RC=0
"$GOG_BIN" auth add "$EMAIL" ${PASS[@]+"${PASS[@]}"} || LOGIN_RC=$?

# ---------- verify ----------
if ! GOG_ACCOUNT="$EMAIL" gog_auth_ok; then
  echo "⚠ gog auth still invalid for $EMAIL after login (exit code: $LOGIN_RC)"
  "$GOG_BIN" auth doctor --check --json --no-input 2>/dev/null \
    | jq --arg e "$EMAIL" '[.checks[] | select(.status != "ok" and (.name | endswith($e)))]' >&2 || true
  exit "${LOGIN_RC:-1}"
fi

# Google's consent screen lets the user untick individual scopes, so list what
# was actually granted and flag the services that came back missing.
GRANTED=$("$GOG_BIN" auth list --json --no-input 2>/dev/null \
  | jq -r --arg e "$EMAIL" '.accounts[] | select(.email == $e) | .services[]' | sort -u)
echo "→ $EMAIL authorized for: $(printf '%s' "$GRANTED" | paste -sd, -)"

if [[ "$HAS_SERVICES" -eq 0 ]]; then
  MISSING=""
  IFS=',' read -ra WANT <<< "$BSG_SERVICES"
  for svc in "${WANT[@]}"; do
    printf '%s\n' "$GRANTED" | grep -qx "$svc" || MISSING="$MISSING $svc"
  done
  if [[ -n "$MISSING" ]]; then
    warn "not granted:$MISSING"
    warn "Either re-run and TICK EVERY BOX on the consent screen, or (if Google"
    warn "refuses the scope) add it on the OAuth consent screen first:"
    warn "  bash scripts/onboard.sh --step scopes"
  fi
fi

echo "✓ gog auth valid for $EMAIL"
exit 0
