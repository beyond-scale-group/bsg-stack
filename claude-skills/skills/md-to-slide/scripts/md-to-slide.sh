#!/usr/bin/env bash
# md-to-slide.sh — branded markdown → HTML + PowerPoint slides via Marp
# Reads brand tokens from .bsg/DESIGN.md in the repo root and generates
# the Marp theme CSS automatically (brand/templates/marp-theme.css).
#
# Usage: md-to-slide.sh <file.md> [--html] [--pptx] [--pdf] [--editable]
#                       [--theme PATH] [--force-theme] [--no-footer]
#   (no format flag)  Export both HTML and PPTX (the default)
#   --html            Export HTML only (self-contained bespoke deck)
#   --pptx            Export PowerPoint only
#   --pdf             Also export a PDF
#   --editable        PPTX with editable text (experimental Marp feature;
#                     requires LibreOffice Impress)
#   --theme PATH      Use a custom Marp theme CSS instead of the generated one
#   --force-theme     Regenerate brand/templates/marp-theme.css even if present
#   --no-footer       Don't inject the DESIGN.md company name as slide footer
set -euo pipefail

FILE="${1:-}"
if [[ -z "$FILE" || ! -f "$FILE" ]]; then
  echo "Usage: md-to-slide.sh <file.md> [--html] [--pptx] [--pdf] [--editable] [--theme PATH] [--force-theme] [--no-footer]" >&2
  exit 1
fi
shift

WANT_HTML=false
WANT_PPTX=false
WANT_PDF=false
EDITABLE=false
THEME=""
FORCE_THEME=false
NO_FOOTER=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --html)        WANT_HTML=true; shift ;;
    --pptx)        WANT_PPTX=true; shift ;;
    --pdf)         WANT_PDF=true; shift ;;
    --editable)    EDITABLE=true; shift ;;
    --theme)       THEME="${2:-}"; shift 2 ;;
    --force-theme) FORCE_THEME=true; shift ;;
    --no-footer)   NO_FOOTER=true; shift ;;
    *)
      echo "Unknown option: $1" >&2
      exit 1
      ;;
  esac
done

# Default: both HTML and PPTX
if [[ "$WANT_HTML" == false && "$WANT_PPTX" == false && "$WANT_PDF" == false ]]; then
  WANT_HTML=true
  WANT_PPTX=true
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FILE_ABS="$(cd "$(dirname "$FILE")" && pwd)/$(basename "$FILE")"
BASE="${FILE_ABS%.md}"

# Walk up to repo root (.git or .claude directory)
REPO_ROOT="$(cd "$(dirname "$FILE_ABS")" && pwd)"
while [[ "$REPO_ROOT" != "/" ]]; do
  [[ -d "$REPO_ROOT/.git" || -d "$REPO_ROOT/.claude" ]] && break
  REPO_ROOT="$(dirname "$REPO_ROOT")"
done

# 1. Resolve the theme: --theme flag > generated brand/templates/marp-theme.css
if [[ -z "$THEME" ]]; then
  THEME="$REPO_ROOT/brand/templates/marp-theme.css"
  # Canonical custom-doc path (ADR-001); $BSG_DESIGN_MD overrides for repos
  # that relocate their design doc.
  DESIGN_MD="${BSG_DESIGN_MD:-$REPO_ROOT/.bsg/DESIGN.md}"
  if [[ ! -f "$THEME" || "$FORCE_THEME" == true || ( -f "$DESIGN_MD" && "$DESIGN_MD" -nt "$THEME" ) ]]; then
    echo "→ Génération du thème Marp depuis .bsg/DESIGN.md…"
    python3 "$SCRIPT_DIR/generate-theme.py" "$THEME" --repo "$REPO_ROOT"
  fi
fi
if [[ ! -f "$THEME" ]]; then
  echo "⚠ Thème introuvable : $THEME" >&2
  exit 1
fi

# 2. Prepare the input: ensure marp/paginate/footer directives on a temp copy
#    (the source file is never mutated; author directives always win)
FOOTER=""
if [[ "$NO_FOOTER" == false ]]; then
  FOOTER="$(python3 "$SCRIPT_DIR/generate-theme.py" --print-company --repo "$REPO_ROOT")"
fi
WORK_DIR="$(mktemp -d -t md-to-slide-XXXXXX)"
trap 'rm -rf "$WORK_DIR"' EXIT
WORK_MD="$WORK_DIR/$(basename "$FILE_ABS")"
PREP_ARGS=("$FILE_ABS" "$WORK_MD")
[[ -n "$FOOTER" ]] && PREP_ARGS+=(--footer "$FOOTER")
python3 "$SCRIPT_DIR/prepare-input.py" "${PREP_ARGS[@]}"

# 3. Locate Marp CLI: local install > npx (auto-download)
if command -v marp >/dev/null 2>&1; then
  MARP=(marp)
elif command -v npx >/dev/null 2>&1; then
  MARP=(npx -y @marp-team/marp-cli@latest)
else
  echo "⚠ Marp CLI introuvable. Installez Node.js (brew install node) ou marp-cli :" >&2
  echo "  npm install -g @marp-team/marp-cli" >&2
  exit 1
fi

# --allow-local-files: local images in the deck must survive the
# browser-based PPTX/PDF conversion (trusted repo content only).
MARP_ARGS=(--theme "$THEME" --allow-local-files)

convert() {
  local out="$1"; shift
  # Run from the source directory so relative image paths keep resolving.
  # stdin from /dev/null: marp-cli blocks waiting on an open stdin pipe
  # (headless/background invocations) even when given a file argument.
  (cd "$(dirname "$FILE_ABS")" && "${MARP[@]}" "$WORK_MD" "${MARP_ARGS[@]}" "$@" -o "$out" < /dev/null)
  echo "✓ Exporté : $out"
}

[[ "$WANT_HTML" == true ]] && convert "$BASE.html"
if [[ "$WANT_PPTX" == true ]]; then
  PPTX_ARGS=()
  [[ "$EDITABLE" == true ]] && PPTX_ARGS+=(--pptx-editable)
  convert "$BASE.pptx" "${PPTX_ARGS[@]}"
fi
[[ "$WANT_PDF" == true ]] && convert "$BASE.pdf"

exit 0
