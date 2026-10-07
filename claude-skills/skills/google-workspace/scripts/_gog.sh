#!/usr/bin/env bash
# _gog.sh — shared helpers for the google-workspace skill scripts (source me).
#
#   source "$(dirname "${BASH_SOURCE[0]}")/_gog.sh"
#
# Wraps the `gog` CLI (openclaw/gogcli >= 0.42). One place for the binary
# lookup, version gate, auth check and the Discovery-backed API call, so the
# scripts don't each re-implement them.
#
#   GOG_BIN        binary to run (default: gog) — tests point it at a fake
#   GOG_ACCOUNT    account email/alias, honoured by gog itself
#
# Part of the BSG google-workspace skill.

GOG_BIN="${GOG_BIN:-gog}"
GOG_MIN_VERSION="0.42.0"
# Install/upgrade hint: Homebrew when present, else the release installer.
if command -v brew >/dev/null 2>&1 || [[ "$(uname -s)" == "Darwin" ]]; then
  GOG_INSTALL_HINT="brew install openclaw/tap/gogcli"
  GOG_UPGRADE_HINT="brew upgrade openclaw/tap/gogcli"
else
  GOG_INSTALL_HINT="bash $(dirname "${BASH_SOURCE[0]}")/install-gog.sh"
  GOG_UPGRADE_HINT="$GOG_INSTALL_HINT"
fi

# pkg_hint <pkg> — OS-appropriate install command for a helper dependency.
pkg_hint() {
  if command -v brew >/dev/null 2>&1; then echo "brew install $1"
  elif command -v apt-get >/dev/null 2>&1; then echo "sudo apt-get install -y $1"
  elif command -v dnf >/dev/null 2>&1; then echo "sudo dnf install -y $1"
  elif command -v pacman >/dev/null 2>&1; then echo "sudo pacman -S $1"
  elif command -v apk >/dev/null 2>&1; then echo "sudo apk add $1"
  else echo "install $1 with your package manager"; fi
}

# gog_require — binary present and >= GOG_MIN_VERSION, else exit 3.
gog_require() {
  if ! command -v "$GOG_BIN" >/dev/null 2>&1; then
    echo "error: $GOG_BIN not installed ($GOG_INSTALL_HINT)" >&2
    exit 3
  fi
  local have
  have=$("$GOG_BIN" --version 2>/dev/null | head -1 | sed -E 's/^[^0-9]*([0-9]+\.[0-9]+\.[0-9]+).*/\1/')
  if [[ -z "$have" ]] || [[ "$(printf '%s\n%s\n' "$GOG_MIN_VERSION" "$have" | sort -V | head -1)" != "$GOG_MIN_VERSION" ]]; then
    echo "error: gog ${have:-unknown} is older than $GOG_MIN_VERSION ($GOG_UPGRADE_HINT)" >&2
    exit 3
  fi
}

# gog_account — email of the active account (GOG_ACCOUNT, else gog's default).
gog_account() {
  if [[ -n "${GOG_ACCOUNT:-}" && "$GOG_ACCOUNT" == *@* ]]; then
    printf '%s\n' "$GOG_ACCOUNT"
  else
    "$GOG_BIN" auth status --json --no-input 2>/dev/null | jq -r '.account.email // empty'
  fi
}

# gog_auth_ok — 0 when the active account's refresh token exchanges cleanly.
gog_auth_ok() {
  local email
  email=$(gog_account)
  [[ -n "$email" ]] || return 1
  "$GOG_BIN" auth doctor --check --json --no-input 2>/dev/null \
    | jq -e --arg e "$email" '[.checks[] | select(.name | startswith("refresh.") and endswith("." + $e))] | length > 0 and all(.status == "ok")' >/dev/null
}

# gog_api <api> <version> <method> [--params JSON] [--body JSON] [--write]
# Discovery-backed call returning the canonical Google JSON. Writes need
# --write (adds --allow-write --force); reads never prompt.
gog_api() {
  local api="$1" ver="$2" method="$3"; shift 3
  local args=() write=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --write) write=1; shift ;;
      *)       args+=("$1"); shift ;;
    esac
  done
  [[ "$write" -eq 1 ]] && args+=(--allow-write --force)
  "$GOG_BIN" api call "$api" "$ver" "$method" ${args[@]+"${args[@]}"} --json --no-input
}

# gog_email — primary address of the active account (Gmail profile).
gog_email() {
  gog_api gmail v1 users.getProfile --params '{"userId":"me"}' 2>/dev/null | jq -r '.emailAddress // empty'
}
