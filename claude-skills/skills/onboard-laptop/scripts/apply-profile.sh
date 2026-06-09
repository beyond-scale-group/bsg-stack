#!/usr/bin/env bash
# apply-profile.sh — read a YAML profile and install everything declared
# in it on macOS. Idempotent: skips items already present, logs failures
# without aborting the whole run.
#
# Usage:
#   bash apply-profile.sh <profile.yml>           # apply everything
#   bash apply-profile.sh --dry-run <profile.yml> # print what would happen
#   bash apply-profile.sh --only brew <profile.yml>
#                                                # apply just one section

set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
PARSER="$SCRIPT_DIR/_parse-profile.py"
FAIL_LOG="${TMPDIR:-/tmp}/onboard-laptop-failures.log"
: > "$FAIL_LOG"

# Exported so `post_install:` commands in a profile can reference
# bundled helpers without hard-coding the install path. Example:
#   post_install:
#     - 'bash "$ONBOARD_SCRIPT_DIR/install-oh-my-zsh.sh"'
export ONBOARD_SCRIPT_DIR="$SCRIPT_DIR"
export ONBOARD_SKILL_DIR
ONBOARD_SKILL_DIR=$(cd "$SCRIPT_DIR/.." && pwd)

DRY=0
ONLY=""
PROFILE=""
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY=1 ;;
    --only) ONLY="__pending__" ;;
    --only=*) ONLY="${arg#--only=}" ;;
    -h|--help)
      sed -n '1,16p' "$0"; exit 0 ;;
    *)
      if [ "$ONLY" = "__pending__" ]; then ONLY="$arg"
      else PROFILE="$arg"; fi
      ;;
  esac
done

if [ -z "$PROFILE" ]; then
  echo "error: no profile path provided" >&2
  echo "usage: bash apply-profile.sh <profile.yml>" >&2
  exit 2
fi
if [ ! -f "$PROFILE" ]; then
  echo "error: profile not found: $PROFILE" >&2
  exit 2
fi

OS=$(bash "$SCRIPT_DIR/detect-os.sh" --ensure-brew)
if [ "$OS" != "mac" ]; then
  echo "error: apply-profile.sh runs on macOS only (detected: $OS)" >&2
  echo "       → use scripts/apply-profile.ps1 on Windows" >&2
  exit 2
fi

# Stream records into temp file so we can iterate multiple times.
RECORDS=$(mktemp)
trap 'rm -f "$RECORDS"' EXIT
if ! python3 "$PARSER" "$PROFILE" > "$RECORDS"; then
  echo "error: failed to parse profile" >&2
  exit 2
fi

want_section() {
  [ -z "$ONLY" ] && return 0
  [ "$ONLY" = "$1" ]
}

run() {
  if [ "$DRY" -eq 1 ]; then
    echo "  [dry-run] $*"
    return 0
  fi
  if "$@"; then
    return 0
  fi
  echo "  ✗ failed: $*" | tee -a "$FAIL_LOG" >&2
  return 1
}

# --- meta ---
NAME=$(awk -F'\t' '$1=="meta" && $2=="name" {print $3; exit}' "$RECORDS")
DESC=$(awk -F'\t' '$1=="meta" && $2=="description" {print $3; exit}' "$RECORDS")
echo "=== Applying profile: ${NAME:-<unnamed>} ==="
[ -n "$DESC" ] && echo "    $DESC"
echo ""

# --- warnings ---
while IFS=$'\t' read -r section payload _; do
  [ "$section" = "warn" ] && echo "⚠️  $payload"
done < "$RECORDS"

# --- brew ---
if want_section brew; then
  echo "--- Homebrew formulae ---"
  while IFS=$'\t' read -r section pkg _; do
    [ "$section" = "brew" ] || continue
    if brew list --formula "$pkg" >/dev/null 2>&1; then
      echo "  ✓ $pkg (already installed)"
    else
      echo "  → installing $pkg"
      run brew install "$pkg" || true
    fi
  done < "$RECORDS"
fi

# --- brew_cask ---
if want_section brew_cask; then
  echo "--- Homebrew casks (GUI apps) ---"
  while IFS=$'\t' read -r section pkg _; do
    [ "$section" = "brew_cask" ] || continue
    if brew list --cask "$pkg" >/dev/null 2>&1; then
      echo "  ✓ $pkg (already installed)"
    else
      echo "  → installing $pkg"
      run brew install --cask "$pkg" || true
    fi
  done < "$RECORDS"
fi

# --- npm_global ---
if want_section npm_global; then
  echo "--- npm global packages ---"
  if ! command -v npm >/dev/null 2>&1; then
    echo "  ⚠️  npm not on PATH — declare 'node' in brew: first" | tee -a "$FAIL_LOG"
  else
    while IFS=$'\t' read -r section pkg _; do
      [ "$section" = "npm_global" ] || continue
      if npm ls -g --depth=0 "$pkg" >/dev/null 2>&1; then
        echo "  ✓ $pkg (already installed)"
      else
        echo "  → installing $pkg"
        run npm install -g "$pkg" || true
      fi
    done < "$RECORDS"
  fi
fi

# --- pip_global ---
if want_section pip_global; then
  echo "--- pip global packages ---"
  PIPCMD=""
  if command -v pip3 >/dev/null 2>&1; then PIPCMD="pip3"
  elif command -v pip >/dev/null 2>&1; then PIPCMD="pip"
  fi
  if [ -z "$PIPCMD" ]; then
    echo "  ⚠️  pip not on PATH — declare a python in brew: first" | tee -a "$FAIL_LOG"
  else
    while IFS=$'\t' read -r section pkg _; do
      [ "$section" = "pip_global" ] || continue
      if "$PIPCMD" show "$pkg" >/dev/null 2>&1; then
        echo "  ✓ $pkg (already installed)"
      else
        echo "  → installing $pkg"
        # --user falls back gracefully when PEP 668 forbids global installs.
        run "$PIPCMD" install --user "$pkg" || run "$PIPCMD" install "$pkg" || true
      fi
    done < "$RECORDS"
  fi
fi

# --- mas (Mac App Store) ---
if want_section mas; then
  HAS_MAS=$(awk -F'\t' '$1=="mas" {found=1} END {print found+0}' "$RECORDS")
  if [ "$HAS_MAS" = "1" ]; then
    echo "--- Mac App Store apps ---"
    if ! command -v mas >/dev/null 2>&1; then
      echo "  → installing mas first"
      run brew install mas || true
    fi
    if ! mas account >/dev/null 2>&1; then
      echo "  ⚠️  Not signed in to the Mac App Store."
      echo "      Open the App Store app, sign in, then re-run."
    else
      while IFS=$'\t' read -r section id name; do
        [ "$section" = "mas" ] || continue
        if mas list | awk '{print $1}' | grep -qx "$id"; then
          echo "  ✓ $name ($id) already installed"
        else
          echo "  → installing $name ($id)"
          run mas install "$id" || true
        fi
      done < "$RECORDS"
    fi
  fi
fi

# --- post_install ---
if want_section post_install; then
  HAS_POST=$(awk -F'\t' '$1=="post_install" {found=1} END {print found+0}' "$RECORDS")
  if [ "$HAS_POST" = "1" ]; then
    echo "--- post_install commands ---"
    while IFS=$'\t' read -r section cmd _; do
      [ "$section" = "post_install" ] || continue
      echo "  → $cmd"
      if [ "$DRY" -eq 1 ]; then
        echo "  [dry-run]"
      else
        bash -c "$cmd" || {
          echo "  ✗ failed: $cmd" | tee -a "$FAIL_LOG" >&2
        }
      fi
    done < "$RECORDS"
  fi
fi

# --- accounts (printed only) ---
if want_section accounts; then
  HAS_ACCT=$(awk -F'\t' '$1=="accounts" {found=1} END {print found+0}' "$RECORDS")
  if [ "$HAS_ACCT" = "1" ]; then
    echo ""
    echo "--- Account checklist (manual — printed for you) ---"
    while IFS=$'\t' read -r section name url notes; do
      [ "$section" = "accounts" ] || continue
      echo "  [ ] $name — $url"
      [ -n "$notes" ] && echo "      note: $notes"
    done < "$RECORDS"
    echo "  → also see references/CHECKLIST-ACCOUNTS.md"
  fi
fi

# --- security (printed only) ---
if want_section security; then
  HAS_SEC=$(awk -F'\t' '$1=="security" {found=1} END {print found+0}' "$RECORDS")
  if [ "$HAS_SEC" = "1" ]; then
    echo ""
    echo "--- Security checklist (manual — printed for you) ---"
    while IFS=$'\t' read -r section token _; do
      [ "$section" = "security" ] || continue
      echo "  [ ] $token"
    done < "$RECORDS"
    echo "  → step-by-step instructions in references/CHECKLIST-SECURITY.md"
  fi
fi

echo ""
if [ -s "$FAIL_LOG" ]; then
  echo "⚠️  Some steps failed. See $FAIL_LOG"
  echo "    Re-run after fixing — apply-profile.sh is idempotent."
  exit 1
fi
echo "✓ Profile applied. Run doctor.sh to verify."
