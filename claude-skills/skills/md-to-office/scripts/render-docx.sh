#!/usr/bin/env bash
# Render a markdown file to DOCX via pandoc.
#
# Usage:
#   render-docx.sh <input.md> <output.docx> [--template <path>]
#
# If --template is provided and the file exists, pandoc uses it as
# reference-doc so styles and branding flow through. Otherwise pandoc
# runs with its built-in default and prints a single-line warning to
# stderr — the render still succeeds.

set -euo pipefail

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

if ! command -v pandoc >/dev/null 2>&1; then
  echo "pandoc not installed. Run scripts/install-local.sh first." >&2
  exit 3
fi

args=(-f markdown -t docx -o "$output")
if [[ -n "$template" && -f "$template" ]]; then
  args+=(--reference-doc="$template")
fi

pandoc "${args[@]}" "$input"
echo "$output"
