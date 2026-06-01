#!/usr/bin/env bash
# Detect the host OS for the onboard-laptop skill.
# Prints one of: mac | windows | linux | unknown
# Exit code: 0 if a supported OS is detected, 1 otherwise.
#
# Side effect (macOS only): if --ensure-brew is passed, installs Homebrew
# when missing so apply-profile.sh can proceed.

set -euo pipefail

ENSURE_BREW=0
for arg in "$@"; do
  case "$arg" in
    --ensure-brew) ENSURE_BREW=1 ;;
    -h|--help)
      sed -n '1,12p' "$0"; exit 0 ;;
  esac
done

case "$(uname -s 2>/dev/null || echo unknown)" in
  Darwin)
    echo "mac"
    if [ "$ENSURE_BREW" -eq 1 ] && ! command -v brew >/dev/null 2>&1; then
      echo "→ Homebrew not found. Installing…" >&2
      /bin/bash -c \
        "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" \
        || { echo "✗ Homebrew install failed" >&2; exit 2; }
      if [ -x /opt/homebrew/bin/brew ]; then
        echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> "${HOME}/.zprofile"
        eval "$(/opt/homebrew/bin/brew shellenv)"
      fi
    fi
    exit 0
    ;;
  Linux)
    echo "linux"
    echo "✗ Linux is not supported by onboard-laptop yet — PRs welcome." >&2
    exit 1
    ;;
  MINGW*|MSYS*|CYGWIN*)
    echo "windows"
    echo "→ Running from a POSIX shell on Windows. Prefer PowerShell + detect-os.ps1." >&2
    exit 0
    ;;
  *)
    echo "unknown"
    echo "✗ Unrecognized OS: $(uname -s 2>/dev/null || echo '?')" >&2
    exit 1
    ;;
esac
