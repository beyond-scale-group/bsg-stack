# _bsg-script-path.sh — resolve a BSG script name to a usable path.
#
# Sourced (not executed) by machine-scoped tools that may run from any
# directory, including outside a git repository.
#
# The repo copy is the source of truth and is preferred when present, so
# editing a script inside bsg-stack takes effect immediately. Everywhere
# else the installed copy under CLAUDE_CONFIG_DIR (default ~/.claude) is
# the only one that exists — target repos do not vendor claude-skills/.
#
# Usage from a sibling script:
#
#     # shellcheck source=_bsg-script-path.sh disable=SC1091
#     source "$(dirname "${BASH_SOURCE[0]}")/_bsg-script-path.sh"
#     resolver="$(bsg_script_path session-state.sh)"
#
# Idempotent — sourcing twice does no harm.

bsg_script_path() {
  local name="${1:?bsg_script_path: script name required}" root
  root="$(git rev-parse --show-toplevel 2>/dev/null)" || root=""
  if [ -n "$root" ] && [ -f "$root/claude-skills/scripts/$name" ]; then
    printf '%s\n' "$root/claude-skills/scripts/$name"
  else
    printf '%s\n' "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/scripts/$name"
  fi
}
