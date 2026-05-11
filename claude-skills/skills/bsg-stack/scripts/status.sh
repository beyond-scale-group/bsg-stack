#!/usr/bin/env bash
# status.sh — one-line summary of BSG agent configuration health.
#
# Thin wrapper around `doctor.sh --status` so the `/bsg-stack status`
# verb has a stable entry point. Read-only per ADR-002.
#
# Usage:
#   bash status.sh           # one-line summary
#   bash status.sh --json    # machine-readable JSON output

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

case "${1:-}" in
  --json) exec bash "$SCRIPT_DIR/doctor.sh" --json ;;
  -h|--help)
    sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'
    exit 0
    ;;
esac

exec bash "$SCRIPT_DIR/doctor.sh" --status "$@"
