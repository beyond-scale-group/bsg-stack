#!/usr/bin/env bash
# OCR orchestrator.
#
# Usage:
#   ocr.sh <source-file> [--engine auto|vision|tesseract|mistral] [--force]
#   ocr.sh --detect
#   ocr.sh --install [--dry-run]
#
# Writes <source>.ocr.md next to the source. In auto mode, cascades:
#   1. Apple Vision (macOS only)
#   2. Tesseract
#   3. Mistral OCR API (only if MISTRAL_API_KEY is set)
# and stops at the first engine that produces a non-trivial output.

set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"

usage() {
  sed -n '3,13p' "$0"
  exit "${1:-0}"
}

# ------- arg parsing -----------------------------------------------------

src=""
engine="auto"
force=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help) usage 0 ;;
    --detect)
      bash "$here/detect-engine.sh"
      exit 0
      ;;
    --install)
      shift
      bash "$here/install-local.sh" "$@"
      exit $?
      ;;
    --engine) engine="${2:?}"; shift 2 ;;
    --force)  force=1; shift ;;
    --)       shift; src="${1:?}"; shift ;;
    -*)       echo "Unknown flag: $1" >&2; usage 2 ;;
    *)
      if [[ -z "$src" ]]; then src="$1"; shift
      else echo "Too many positional args: $1" >&2; usage 2
      fi
      ;;
  esac
done

[[ -n "$src" ]] || usage 2
[[ -f "$src" ]] || { echo "File not found: $src" >&2; exit 2; }

out="${src}.ocr.md"

if [[ -f "$out" && $force -eq 0 ]]; then
  echo "$out (cached; use --force to re-run)"
  exit 0
fi

# Validate: non-empty file with at least 10 non-whitespace characters.
# This catches "ocrit produced 2 bytes of garbage" failure modes.
validate() {
  local f="$1"
  [[ -s "$f" ]] || return 1
  local nonws
  nonws="$(tr -d '[:space:]' < "$f" | wc -c | tr -d ' ')"
  [[ "$nonws" -ge 10 ]]
}

try() {
  local eng="$1"
  case "$eng" in
    vision)    bash "$here/run-vision.sh"    "$src" "$out" >/dev/null ;;
    tesseract) bash "$here/run-tesseract.sh" "$src" "$out" >/dev/null ;;
    mistral)   bash "$here/run-mistral.sh"   "$src" "$out" >/dev/null ;;
    *) return 2 ;;
  esac
}

run_single() {
  local eng="$1"
  if try "$eng" && validate "$out"; then
    printf '%s (%s)\n' "$out" "$eng"
    return 0
  fi
  return 1
}

# ------- execution -------------------------------------------------------

if [[ "$engine" != "auto" ]]; then
  # Pinned engine: either it works or it fails. No cascade.
  if run_single "$engine"; then exit 0; fi
  echo "Engine '$engine' failed. Inspect $out (if written) or rerun with --engine auto." >&2
  exit 1
fi

# Auto mode: cascade.
detect_json="$(bash "$here/detect-engine.sh")"
os="$(printf '%s' "$detect_json" | jq -r .os)"
mistral_available="$(printf '%s' "$detect_json" | jq -r .mistral_key)"

tried=()

if [[ "$os" == "Darwin" ]] && command -v ocrit >/dev/null 2>&1; then
  tried+=(vision)
  if run_single vision; then exit 0; fi
fi

if command -v tesseract >/dev/null 2>&1 || command -v ocrmypdf >/dev/null 2>&1; then
  tried+=(tesseract)
  if run_single tesseract; then exit 0; fi
fi

if [[ "$mistral_available" == "true" ]]; then
  tried+=(mistral)
  if run_single mistral; then exit 0; fi
fi

# Nothing worked.
if (( ${#tried[@]} == 0 )); then
  cat >&2 <<EOF
No OCR engine available. Run:

  bash $here/install-local.sh

to install local engines, or set MISTRAL_API_KEY to use the Mistral OCR API.
EOF
else
  echo "All OCR engines failed: ${tried[*]}" >&2
  printf 'Detection:\n%s\n' "$detect_json" >&2
fi
exit 1
