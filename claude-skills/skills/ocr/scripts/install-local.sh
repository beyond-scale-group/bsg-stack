#!/usr/bin/env bash
# Install local OCR engines for this system.
#
# Usage:
#   install-local.sh            # install missing tools
#   install-local.sh --dry-run  # print what would be installed, don't run it
#
# Supported OS: macOS (Homebrew), Debian/Ubuntu (apt-get).
# Other Linux distros: prints manual instructions and exits 0.

set -euo pipefail

dry_run=0
[[ "${1:-}" == "--dry-run" ]] && dry_run=1

os="$(uname -s)"
has() { command -v "$1" >/dev/null 2>&1; }

run() {
  if (( dry_run )); then
    printf '[dry-run] %s\n' "$*"
  else
    echo "+ $*"
    "$@"
  fi
}

case "$os" in
  Darwin)
    if ! has brew; then
      echo "Homebrew is required. Install from https://brew.sh and re-run." >&2
      exit 2
    fi
    pkgs=()
    has ocrit     || pkgs+=(ocrit)       # Apple Vision CLI for images
    has tesseract || pkgs+=(tesseract)   # Fallback for images
    has ocrmypdf  || pkgs+=(ocrmypdf)    # PDF wrapper (uses Tesseract by default)
    has pdftoppm  || pkgs+=(poppler)     # pdftoppm for PDF → PNG rasterization
    if (( ${#pkgs[@]} == 0 )); then
      echo "All OCR tools already installed."
    else
      run brew install "${pkgs[@]}"
    fi
    ;;
  Linux)
    if has apt-get; then
      pkgs=()
      has tesseract || pkgs+=(tesseract-ocr)
      has ocrmypdf  || pkgs+=(ocrmypdf)
      has pdftoppm  || pkgs+=(poppler-utils)
      if (( ${#pkgs[@]} == 0 )); then
        echo "All OCR tools already installed."
      else
        run sudo apt-get update
        run sudo apt-get install -y "${pkgs[@]}"
      fi
    else
      cat >&2 <<'EOF'
Unsupported Linux package manager. Install manually:
  - tesseract-ocr (or equivalent)
  - ocrmypdf
  - poppler-utils (for pdftoppm)
EOF
      exit 2
    fi
    ;;
  *)
    echo "Unsupported OS: $os. Install tesseract + ocrmypdf + poppler manually." >&2
    exit 2
    ;;
esac

echo
echo "Done. Run 'bash $(dirname "$0")/detect-engine.sh | jq' to verify."
