#!/usr/bin/env bash
# Emit a JSON description of the best available OCR engine on this system.
#
# Output shape:
#   {
#     "os": "Darwin" | "Linux" | ...,
#     "engine": "vision" | "tesseract" | "mistral" | "none",
#     "available": ["ocrit", "tesseract", ...],
#     "missing":   ["ocrmypdf", ...],
#     "mistral_key": true | false
#   }
#
# "engine" is the preferred engine in auto mode:
#   macOS with ocrit  → vision
#   tesseract present → tesseract
#   MISTRAL_API_KEY   → mistral
#   otherwise         → none

set -euo pipefail

has() { command -v "$1" >/dev/null 2>&1; }

os="$(uname -s)"

# Tools we care about, in a stable order. Each row: "name:is_relevant"
declare -a tools
if [[ "$os" == "Darwin" ]]; then
  tools=(ocrit pdftoppm tesseract ocrmypdf)
else
  tools=(tesseract ocrmypdf pdftoppm)
fi

available=()
missing=()
for t in "${tools[@]}"; do
  if has "$t"; then
    available+=("$t")
  else
    missing+=("$t")
  fi
done

mistral_key=false
[[ -n "${MISTRAL_API_KEY:-}" ]] && mistral_key=true

engine=none
if [[ "$os" == "Darwin" ]] && has ocrit; then
  engine=vision
elif has tesseract; then
  engine=tesseract
elif [[ "$mistral_key" == "true" ]]; then
  engine=mistral
fi

# Render JSON arrays safely even when empty.
to_json_array() {
  if (( $# == 0 )); then
    printf '[]'
  else
    printf '%s\n' "$@" | jq -R . | jq -s .
  fi
}

avail_json="$(to_json_array "${available[@]+"${available[@]}"}")"
missing_json="$(to_json_array "${missing[@]+"${missing[@]}"}")"

jq -n \
  --arg os "$os" \
  --arg engine "$engine" \
  --argjson available "$avail_json" \
  --argjson missing "$missing_json" \
  --argjson mistral_key "$mistral_key" \
  '{os:$os, engine:$engine, available:$available, missing:$missing, mistral_key:$mistral_key}'
