#!/usr/bin/env bash
# Render a markdown file to PPTX via python-pptx.
#
# Usage:
#   render-pptx.sh <input.md> <output.pptx> [--template <path>]
#
# If --template is provided and the file exists, python-pptx uses it as
# the base presentation so slide masters and branding flow through.
# Otherwise a blank default presentation is used.

set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"

input=""
output=""
template=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --template) template="${2:-}"; shift 2 ;;
    -*) echo "Unknown flag: $1" >&2; exit 2 ;;
    *)
      if [[ -z "$input" ]]; then input="$1"; shift
      elif [[ -z "$output" ]]; then output="$1"; shift
      else echo "Too many positional args: $1" >&2; exit 2
      fi
      ;;
  esac
done

[[ -n "$input"  ]] || { echo "Missing input path"  >&2; exit 2; }
[[ -n "$output" ]] || { echo "Missing output path" >&2; exit 2; }
[[ -f "$input"  ]] || { echo "Input not found: $input" >&2; exit 2; }

if ! python3 -c "import pptx" 2>/dev/null; then
  echo "python-pptx not installed. Run scripts/install-local.sh first." >&2
  exit 3
fi

args=("$here/render-pptx.py" "$input" "$output")
if [[ -n "$template" && -f "$template" ]]; then
  args+=(--template "$template")
fi

python3 "${args[@]}"
echo "$output"
