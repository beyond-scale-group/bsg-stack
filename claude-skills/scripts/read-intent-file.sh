#!/usr/bin/env bash
# read-intent-file.sh — reads a per-repo agent intent file.
#
# Usage:
#   bash claude-skills/scripts/read-intent-file.sh <filename>
#
# Reads <filename> from the repo root (or from INTENT_FILE_BASEDIR if set,
# for testing). Prints the file contents to stdout. Exits 0 with empty
# output when the file does not exist. Exits 1 when called without an argument.
#
# Agents source this helper rather than reading intent files directly so the
# helper can later add caching, validation, or fallbacks without touching every
# agent. See docs/intent-files-spec.md for the full convention.
#
# Example:
#   roadmap="$(bash claude-skills/scripts/read-intent-file.sh ROADMAP.md)"
#   if [ -n "$roadmap" ]; then
#     echo "ROADMAP.md found — adjusting defaults from intent signals"
#   fi

set -euo pipefail

if [ $# -lt 1 ]; then
  echo "Usage: read-intent-file.sh <filename>" >&2
  exit 1
fi

filename="$1"

# Allow tests to override the base directory without chdir.
basedir="${INTENT_FILE_BASEDIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"

filepath="$basedir/$filename"

if [ -f "$filepath" ]; then
  cat "$filepath"
fi

# Absent file is not an error — agents skip silently when a file is missing.
exit 0
