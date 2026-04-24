#!/usr/bin/env bash
# Install local dependencies for md-to-office.
#
# Usage:
#   install-local.sh [--dry-run]
#
# PR #1 scope: pandoc only. python-pptx and openpyxl install lines will
# be added by the PPTX / XLSX PRs per PRD-008 §12.

set -euo pipefail

dry_run=0
[[ "${1:-}" == "--dry-run" ]] && dry_run=1

run() {
  if [[ $dry_run -eq 1 ]]; then
    echo "+ $*"
  else
    "$@"
  fi
}

os="$(uname -s)"

if ! command -v pandoc >/dev/null 2>&1; then
  case "$os" in
    Darwin)
      if ! command -v brew >/dev/null 2>&1; then
        echo "Homebrew not found. Install from https://brew.sh first." >&2
        exit 1
      fi
      run brew install pandoc
      ;;
    Linux)
      if command -v apt-get >/dev/null 2>&1; then
        run sudo apt-get update
        run sudo apt-get install -y pandoc
      else
        echo "Unsupported Linux distro — install pandoc manually." >&2
        exit 1
      fi
      ;;
    *)
      echo "Unsupported OS: $os — install pandoc manually." >&2
      exit 1
      ;;
  esac
else
  echo "pandoc already installed: $(pandoc --version | head -n1)"
fi
