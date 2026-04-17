#!/usr/bin/env bash
# Run OCR on an image or PDF using Tesseract (+ OCRmyPDF for PDFs).
#
# Usage: run-tesseract.sh <source> <output.ocr.md>

set -euo pipefail

src="${1:?source file required}"
out="${2:?output path required}"

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
  png|jpg|jpeg|tiff|tif|bmp|webp)
    command -v tesseract >/dev/null || {
      echo "tesseract not installed." >&2; exit 2;
    }
    write_header "tesseract" ""
    tesseract "$src" - 2>/dev/null >> "$out"
    ;;
  pdf)
    command -v ocrmypdf >/dev/null || {
      echo "ocrmypdf not installed." >&2; exit 2;
    }
    command -v pdftotext >/dev/null || {
      echo "pdftotext missing. Install poppler-utils / poppler." >&2; exit 2;
    }
    tmp_pdf="$(mktemp -t ocr-pdf-XXXXXX).pdf"
    trap 'rm -f "$tmp_pdf"' EXIT
    # --skip-text is safer for already-OCR'd PDFs; --force-ocr re-OCRs.
    # Use --skip-text first, fall back to --force-ocr if OCRmyPDF refuses.
    if ! ocrmypdf --skip-text --quiet "$src" "$tmp_pdf" 2>/dev/null; then
      ocrmypdf --force-ocr --quiet "$src" "$tmp_pdf" >/dev/null
    fi
    pages="$(pdfinfo "$tmp_pdf" 2>/dev/null | awk '/^Pages:/ {print $2}')"
    write_header "tesseract" "${pages:-}"
    pdftotext -layout "$tmp_pdf" - >> "$out"
    ;;
  *)
    echo "run-tesseract.sh: unsupported extension .$ext" >&2; exit 2
    ;;
esac

echo "$out"
