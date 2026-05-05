# _bsg-paths.sh — shared path resolution for BSG agent infrastructure.
#
# Sourced (not executed) by other scripts. Exports `BSG_AUTOPILOT_FILE`
# pointing at the autopilot config file, preferring the new `.bsg/`
# convention from ADR-001 over the legacy dotfile path.
#
# Resolution order:
#   1. .bsg/AUTOPILOT.yml         (ADR-001, .bsg/ directory convention)
#   2. .bsg-autopilot.yml         (legacy dotfile, kept during migration)
#
# When neither exists, BSG_AUTOPILOT_FILE points at the legacy path so
# `[[ -f "$BSG_AUTOPILOT_FILE" ]]` checks still work as a presence test.
#
# Usage from a sibling script:
#
#     # shellcheck source=_bsg-paths.sh disable=SC1091
#     source "$(dirname "${BASH_SOURCE[0]}")/_bsg-paths.sh"
#     # ... use "$BSG_AUTOPILOT_FILE" everywhere
#
# Resolves the path relative to the current working directory of the
# caller (matches the `[[ -f .bsg-autopilot.yml ]]` checks the legacy
# scripts use). Idempotent — sourcing twice does no harm.

bsg_autopilot_file() {
  if [[ -f .bsg/AUTOPILOT.yml ]]; then
    printf '%s\n' '.bsg/AUTOPILOT.yml'
  else
    printf '%s\n' '.bsg-autopilot.yml'
  fi
}

BSG_AUTOPILOT_FILE="$(bsg_autopilot_file)"
export BSG_AUTOPILOT_FILE
