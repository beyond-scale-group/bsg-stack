#!/usr/bin/env bash
# gws-switch.sh — multi-profile switcher for `gws`.
#
# Background: `gws` keeps credentials under `$GOOGLE_WORKSPACE_CLI_CONFIG_DIR`
# (default `~/.config/gws`) and only authenticates one account at a time.
# Pointing that env var at a per-profile directory gives you N parallel
# accounts; switching is then a single `export` away. This script wraps
# that pattern with a clean CLI.
#
# USAGE
#   bash scripts/gws-switch.sh list
#       List every profile under ~/.config/gws* with email + token status.
#
#   bash scripts/gws-switch.sh whoami
#       Show the active profile (default or named) and the bound email.
#
#   bash scripts/gws-switch.sh init <name> [auth-login-args...]
#       Create profile <name> at ~/.config/gws-<name> and run the OAuth
#       consent flow against it. Extra args pass through to auth-login.sh
#       (e.g. --readonly, --services gmail,calendar).
#
#   eval "$(bash scripts/gws-switch.sh use <name>)"
#       Activate profile <name> in the current shell.
#       <name> = `default` resets to ~/.config/gws (unsets the env var).
#
#   bash scripts/gws-switch.sh install
#       Print a shell function `gws-switch` that wraps the eval pattern
#       so users can type `gws-switch prizoners` without the eval shim.
#       Append to ~/.zshrc.user or equivalent.
#
#   bash scripts/gws-switch.sh remove <name>
#       Delete profile <name> (asks for confirmation; --yes to skip).
#
# Exit codes:
#   0  ok
#   1  invalid args / unknown profile
#   2  auth flow failed
#   3  unsupported environment

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROFILE_PREFIX="$HOME/.config/gws"
DEFAULT_DIR="$HOME/.config/gws"

die()  { printf "❌ %s\n" "$*" >&2; exit "${2:-1}"; }
warn() { printf "⚠ %s\n" "$*" >&2; }
note() { printf "ℹ %s\n" "$*" >&2; }

require_bin() {
  command -v "$1" >/dev/null || die "$1 not installed${2:+ — $2}" 3
}

profile_dir_for() {
  local name="$1"
  if [ "$name" = "default" ]; then
    printf "%s" "$DEFAULT_DIR"
  else
    printf "%s-%s" "$PROFILE_PREFIX" "$name"
  fi
}

profile_email() {
  # Read email from a profile dir without disturbing the active env.
  local dir="$1" email
  [ -f "$dir/credentials.enc" ] || { printf "(no creds)"; return; }
  email=$(GOOGLE_WORKSPACE_CLI_CONFIG_DIR="$dir" \
    gws gmail users getProfile --params '{"userId":"me"}' 2>/dev/null \
    | jq -r '.emailAddress // empty' 2>/dev/null)
  if [ -n "$email" ]; then
    printf "%s" "$email"
  else
    printf "(auth invalid)"
  fi
}

profile_token_valid() {
  local dir="$1"
  GOOGLE_WORKSPACE_CLI_CONFIG_DIR="$dir" gws auth status 2>/dev/null \
    | jq -e '.token_valid == true' >/dev/null
}

list_profiles() {
  require_bin gws
  require_bin jq
  printf "%-20s  %-32s  %s\n" "PROFILE" "EMAIL" "DIR"
  printf "%-20s  %-32s  %s\n" "-------" "-----" "---"
  # Default profile
  local email_default
  if [ -d "$DEFAULT_DIR" ]; then
    email_default=$(profile_email "$DEFAULT_DIR")
    printf "%-20s  %-32s  %s\n" "default" "$email_default" "$DEFAULT_DIR"
  fi
  # Named profiles
  local dir name email
  for dir in "$PROFILE_PREFIX"-*; do
    [ -d "$dir" ] || continue
    name="${dir##*/gws-}"
    email=$(profile_email "$dir")
    printf "%-20s  %-32s  %s\n" "$name" "$email" "$dir"
  done
}

cmd_whoami() {
  require_bin gws
  require_bin jq
  local active="${GOOGLE_WORKSPACE_CLI_CONFIG_DIR:-$DEFAULT_DIR}" name email
  if [ "$active" = "$DEFAULT_DIR" ]; then
    name="default"
  else
    name="${active##*/gws-}"
  fi
  email=$(profile_email "$active")
  printf "active profile : %s\n" "$name"
  printf "email          : %s\n" "$email"
  printf "config dir     : %s\n" "$active"
}

cmd_init() {
  local name="${1:-}"
  [ -z "$name" ] && die "init requires a profile name (e.g. 'prizoners')"
  [ "$name" = "default" ] && die "use plain 'gws auth login' for the default profile"
  shift
  local dir; dir=$(profile_dir_for "$name")
  if [ -f "$dir/credentials.enc" ]; then
    warn "profile '$name' already exists at $dir — re-running auth-login will replace its credentials."
  fi
  mkdir -p "$dir"
  # Reuse the OAuth client from the default profile (same GCP app, multiple
  # users). Without this, the new dir has no client_secret.json and `gws auth
  # login` errors out with "No OAuth client configured". Skip silently if
  # the default profile isn't bootstrapped — auth-login.sh will surface the
  # missing client to the user with the documented remediation paths.
  if [ -f "$DEFAULT_DIR/client_secret.json" ] && [ ! -f "$dir/client_secret.json" ]; then
    cp "$DEFAULT_DIR/client_secret.json" "$dir/client_secret.json"
    note "copied OAuth client from default profile → $dir/client_secret.json"
  fi
  note "running auth-login against profile '$name' (dir=$dir)…"
  GOOGLE_WORKSPACE_CLI_CONFIG_DIR="$dir" bash "$SCRIPT_DIR/auth-login.sh" "$@" \
    || die "auth-login failed for profile '$name'" 2
  local email; email=$(profile_email "$dir")
  printf "\n✅ profile '%s' ready — bound to %s\n" "$name" "$email"
  printf "   activate with: eval \"\$(bash %s use %s)\"\n" "$SCRIPT_DIR/gws-switch.sh" "$name"
  printf "   or install the shell function: bash %s install\n" "$SCRIPT_DIR/gws-switch.sh"
}

cmd_use() {
  local name="${1:-}"
  [ -z "$name" ] && die "use requires a profile name (or 'default')"
  if [ "$name" = "default" ]; then
    # Emit export lines that unset the override in the parent shell.
    printf "unset GOOGLE_WORKSPACE_CLI_CONFIG_DIR\n"
    printf "echo '→ gws profile: default'\n"
    return 0
  fi
  local dir; dir=$(profile_dir_for "$name")
  [ -d "$dir" ] || die "profile '$name' does not exist (init it first: gws-switch.sh init $name)"
  printf "export GOOGLE_WORKSPACE_CLI_CONFIG_DIR=%q\n" "$dir"
  printf "echo '→ gws profile: %s'\n" "$name"
}

cmd_install() {
  # Print a shell function the user can append to ~/.zshrc.
  cat <<'SHELL'
# --- gws multi-profile switcher (installed by gws-switch.sh) -----------------
# Usage:
#   gws-switch list
#   gws-switch whoami
#   gws-switch init <name> [-- auth-login-args...]
#   gws-switch <name>          # shorthand for `use <name>`
#   gws-switch default         # back to ~/.config/gws
gws-switch() {
  local script="$HOME/.claude/skills/google-workspace/scripts/gws-switch.sh"
  [ -f "$script" ] || { echo "gws-switch.sh not found at $script" >&2; return 1; }
  case "${1:-}" in
    "" | -h | --help | help)
      bash "$script" --help
      ;;
    list | whoami | init | install | remove)
      bash "$script" "$@"
      ;;
    use)
      shift
      eval "$(bash "$script" use "$@")"
      ;;
    *)
      # Shorthand: `gws-switch prizoners` == `gws-switch use prizoners`
      eval "$(bash "$script" use "$@")"
      ;;
  esac
}
# --- /gws multi-profile switcher --------------------------------------------
SHELL
}

cmd_remove() {
  local name="${1:-}" yes=0
  [ -z "$name" ] && die "remove requires a profile name"
  [ "$name" = "default" ] && die "refusing to delete the default profile dir"
  shift || true
  for arg in "$@"; do
    [ "$arg" = "--yes" ] && yes=1
  done
  local dir; dir=$(profile_dir_for "$name")
  [ -d "$dir" ] || die "profile '$name' does not exist"
  if [ "$yes" -ne 1 ]; then
    printf "About to delete: %s\nConfirm? [y/N] " "$dir" >&2
    local reply; read -r reply
    case "$reply" in y|Y|yes|YES) ;; *) die "aborted" 0 ;; esac
  fi
  rm -rf "$dir"
  printf "✓ profile '%s' removed\n" "$name"
}

usage() {
  sed -n '2,38p' "$0" | sed 's/^# \{0,1\}//'
}

case "${1:-}" in
  list)    shift; list_profiles "$@" ;;
  whoami)  shift; cmd_whoami "$@" ;;
  init)    shift; cmd_init "$@" ;;
  use)     shift; cmd_use "$@" ;;
  install) shift; cmd_install "$@" ;;
  remove)  shift; cmd_remove "$@" ;;
  -h | --help | "" | help) usage ;;
  *) die "unknown subcommand: $1 (run with --help)" ;;
esac
