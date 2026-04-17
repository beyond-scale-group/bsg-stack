#!/usr/bin/env bash
# Run OCR on an image or PDF using Apple Vision framework.
#
# Usage: run-vision.sh <source> <output.ocr.md>
#
# Images: ocrit (Vision-framework binary, brew install ocrit)
# PDFs:   pdftoppm -> PNG -> ocrit per page -> concatenate

set -euo pipefail

src="${1:?source file required}"
out="${2:?output path required}"

[[ "$(uname -s)" == "Darwin" ]] || { echo "run-vision.sh: macOS only" >&2; exit 2; }
command -v ocrit >/dev/null || { echo "ocrit not installed. brew install ocrit" >&2; exit 2; }

ext="$(printf '%s' "${src##*.}" | tr '[:upper:]' '[:lower:]')"

abs_src="$(cd "$(dirname "$src")" && pwd)/$(basename "$src")"
timestamp="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

write_header() {
  local engine="$1" pages="$2"
  {
    printf '# OCR: %s\n\n' "$(basename "$src")"
    printf '%s\n' "- Engine: $engine"
    printf '%s\n' "- Source: $abs_src"
    printf '%s\n' "- Run at: $timestamp"
    [[ -n "$pages" ]] && printf '%s\n' "- Pages: $pages"
    printf '\n---\n\n'
  } > "$out"
}

case "$ext" in
  png|jpg|jpeg|tiff|tif|heic|webp|bmp)
    tmpdir="$(mktemp -d -t ocrit-XXXXXX)"
    trap 'rm -rf "$tmpdir"' EXIT
    ocrit "$src" -o "$tmpdir" > /dev/null
    txt="$tmpdir/$(basename "${src%.*}").txt"
    [[ -s "$txt" ]] || { echo "ocrit produced no output for $src" >&2; exit 1; }
    write_header "vision" ""
    cat "$txt" >> "$out"
    ;;
  pdf)
    command -v pdftoppm >/dev/null || {
      echo "pdftoppm missing. brew install poppler" >&2; exit 2;
    }
    tmpdir="$(mktemp -d -t ocrit-pdf-XXXXXX)"
    trap 'rm -rf "$tmpdir"' EXIT
    pdftoppm -r 200 "$src" "$tmpdir/page" -png
    pages=("$tmpdir"/page-*.png)
    [[ -e "${pages[0]}" ]] || { echo "pdftoppm produced no pages for $src" >&2; exit 1; }
    write_header "vision" "${#pages[@]}"
    first=1
    for p in "${pages[@]}"; do
      ocrit "$p" -o "$tmpdir" > /dev/null
      txt="${p%.png}.txt"
      (( first )) || printf '\n\n---\n\n' >> "$out"
      first=0
      if [[ -s "$txt" ]]; then
        cat "$txt" >> "$out"
      else
        printf '_(empty page)_\n' >> "$out"
      fi
    done
    ;;
  *)
    echo "run-vision.sh: unsupported extension .$ext" >&2; exit 2
    ;;
esac

echo "$out"
