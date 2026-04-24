#!/usr/bin/env bash
# Install local dependencies for md-to-office.
#
# Usage:
#   install-local.sh [--dry-run]
#
# Installs: pandoc (DOCX renderer) + python-docx, python-pptx, openpyxl
# (brand template generation via --init).

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

# Python packages for brand template generation (--init).
if ! command -v python3 >/dev/null 2>&1; then
  echo "python3 not found — skipping Python deps (install python3 to enable --init)" >&2
else
  PYTHON_DEPS=(python-docx python-pptx openpyxl)
  missing=()
  for dep in "${PYTHON_DEPS[@]}"; do
    pkg="${dep//-/_}"  # pip name → importable name heuristic
    python3 -c "import ${pkg%%[<>=]*}" 2>/dev/null || missing+=("$dep")
  done
  if [[ ${#missing[@]} -gt 0 ]]; then
    run python3 -m pip install --quiet "${missing[@]}"
  else
    echo "Python deps already installed: ${PYTHON_DEPS[*]}"
  fi
fi
