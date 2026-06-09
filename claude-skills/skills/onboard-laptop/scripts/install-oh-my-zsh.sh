#!/usr/bin/env bash
# install-oh-my-zsh.sh — idempotent Oh My Zsh installer.
#
# Behavior:
#   - If $HOME/.oh-my-zsh already exists → no-op, exit 0.
#   - Else run the official installer in --unattended mode, which
#       * does NOT overwrite an existing $HOME/.zshrc
#       * does NOT call chsh (the user keeps their current login shell)
#   - Then, if --with-starter-zshrc is passed AND no .zshrc exists,
#     install the bundled starter from references/dotfiles/zshrc-starter.
#     (We never touch an existing .zshrc.)
#
# Usage:
#   bash install-oh-my-zsh.sh
#   bash install-oh-my-zsh.sh --with-starter-zshrc
#
# Designed to be invoked from a profile's post_install: block, so the
# orchestrator's idempotency guarantee holds end-to-end.

set -uo pipefail

WITH_STARTER=0
for arg in "$@"; do
  case "$arg" in
    --with-starter-zshrc) WITH_STARTER=1 ;;
    -h|--help) sed -n '1,18p' "$0"; exit 0 ;;
  esac
done

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
STARTER="$SCRIPT_DIR/../references/dotfiles/zshrc-starter"

# Step 1: Oh My Zsh itself.
if [ -d "$HOME/.oh-my-zsh" ]; then
  echo "✓ Oh My Zsh already installed at $HOME/.oh-my-zsh"
else
  if ! command -v zsh >/dev/null 2>&1; then
    echo "✗ zsh not on PATH — install it first (brew install zsh, or system zsh on macOS)" >&2
    exit 2
  fi
  if ! command -v curl >/dev/null 2>&1; then
    echo "✗ curl not on PATH" >&2
    exit 2
  fi
  echo "→ Installing Oh My Zsh (--unattended: no .zshrc overwrite, no chsh)"
  # RUNZSH=no    → don't drop into a zsh sub-shell at the end
  # KEEP_ZSHRC=yes → never overwrite a pre-existing .zshrc
  # CHSH=no      → never call chsh; user controls their login shell
  RUNZSH=no KEEP_ZSHRC=yes CHSH=no \
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" \
    "" --unattended
  if [ -d "$HOME/.oh-my-zsh" ]; then
    echo "✓ Oh My Zsh installed"
  else
    echo "✗ Oh My Zsh install did not create $HOME/.oh-my-zsh" >&2
    exit 2
  fi
fi

# Step 2: starter .zshrc — only when explicitly requested AND no .zshrc.
if [ "$WITH_STARTER" -eq 1 ]; then
  if [ -e "$HOME/.zshrc" ]; then
    echo "↻ $HOME/.zshrc already exists — leaving it alone."
    echo "  → diff against the starter at: $STARTER"
  elif [ ! -f "$STARTER" ]; then
    echo "✗ starter not found at $STARTER" >&2
    exit 2
  else
    cp "$STARTER" "$HOME/.zshrc"
    echo "✓ Installed starter .zshrc → $HOME/.zshrc"
    echo "  Tweak it freely — it is yours from now on."
  fi
fi

echo ""
echo "Next steps:"
echo "  1. Open a new terminal (or run: exec zsh -l)"
echo "  2. If zsh is not your login shell yet: chsh -s \"\$(which zsh)\""
echo "  3. Customize \$HOME/.zshrc — Oh My Zsh themes live in ~/.oh-my-zsh/themes/"
