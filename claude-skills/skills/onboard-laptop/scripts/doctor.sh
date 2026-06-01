#!/usr/bin/env bash
# doctor.sh — re-read a profile and verify every declared item is present.
# Exit codes:
#   0 → everything verified
#   1 → warnings only (manual checklists, post_install can't be verified)
#   2 → at least one declared package is missing

set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
PARSER="$SCRIPT_DIR/_parse-profile.py"

PROFILE="${1:-}"
if [ -z "$PROFILE" ] || [ ! -f "$PROFILE" ]; then
  echo "usage: bash doctor.sh <profile.yml>" >&2
  exit 2
fi

OS=$(bash "$SCRIPT_DIR/detect-os.sh")
if [ "$OS" != "mac" ]; then
  echo "error: doctor.sh runs on macOS only (detected: $OS)" >&2
  echo "       → use scripts/doctor.ps1 on Windows" >&2
  exit 2
fi

RECORDS=$(mktemp)
trap 'rm -f "$RECORDS"' EXIT
python3 "$PARSER" "$PROFILE" > "$RECORDS"

MISSING=0
WARN=0

NAME=$(awk -F'\t' '$1=="meta" && $2=="name" {print $3; exit}' "$RECORDS")
echo "=== Doctor: ${NAME:-<unnamed profile>} ==="

# brew
HAS=$(awk -F'\t' '$1=="brew" {found=1} END {print found+0}' "$RECORDS")
if [ "$HAS" = "1" ]; then
  echo "--- Homebrew formulae ---"
  while IFS=$'\t' read -r section pkg _; do
    [ "$section" = "brew" ] || continue
    if brew list --formula "$pkg" >/dev/null 2>&1; then
      ver=$(brew list --formula --versions "$pkg" 2>/dev/null | awk '{print $2}')
      echo "  ✓ $pkg ($ver)"
    else
      echo "  ✗ $pkg MISSING — re-run apply-profile.sh"
      MISSING=$((MISSING+1))
    fi
  done < "$RECORDS"
fi

# brew_cask
HAS=$(awk -F'\t' '$1=="brew_cask" {found=1} END {print found+0}' "$RECORDS")
if [ "$HAS" = "1" ]; then
  echo "--- Homebrew casks ---"
  while IFS=$'\t' read -r section pkg _; do
    [ "$section" = "brew_cask" ] || continue
    if brew list --cask "$pkg" >/dev/null 2>&1; then
      echo "  ✓ $pkg"
    else
      echo "  ✗ $pkg MISSING"
      MISSING=$((MISSING+1))
    fi
  done < "$RECORDS"
fi

# npm_global
HAS=$(awk -F'\t' '$1=="npm_global" {found=1} END {print found+0}' "$RECORDS")
if [ "$HAS" = "1" ]; then
  echo "--- npm global ---"
  while IFS=$'\t' read -r section pkg _; do
    [ "$section" = "npm_global" ] || continue
    if npm ls -g --depth=0 "$pkg" >/dev/null 2>&1; then
      echo "  ✓ $pkg"
    else
      echo "  ✗ $pkg MISSING"
      MISSING=$((MISSING+1))
    fi
  done < "$RECORDS"
fi

# pip_global
HAS=$(awk -F'\t' '$1=="pip_global" {found=1} END {print found+0}' "$RECORDS")
if [ "$HAS" = "1" ]; then
  echo "--- pip global ---"
  PIPCMD="pip3"
  command -v pip3 >/dev/null || PIPCMD="pip"
  while IFS=$'\t' read -r section pkg _; do
    [ "$section" = "pip_global" ] || continue
    if "$PIPCMD" show "$pkg" >/dev/null 2>&1; then
      echo "  ✓ $pkg"
    else
      echo "  ✗ $pkg MISSING"
      MISSING=$((MISSING+1))
    fi
  done < "$RECORDS"
fi

# mas
HAS=$(awk -F'\t' '$1=="mas" {found=1} END {print found+0}' "$RECORDS")
if [ "$HAS" = "1" ]; then
  echo "--- Mac App Store ---"
  if command -v mas >/dev/null 2>&1; then
    while IFS=$'\t' read -r section id name; do
      [ "$section" = "mas" ] || continue
      if mas list | awk '{print $1}' | grep -qx "$id"; then
        echo "  ✓ $name ($id)"
      else
        echo "  ✗ $name ($id) MISSING"
        MISSING=$((MISSING+1))
      fi
    done < "$RECORDS"
  else
    echo "  ⚠️  mas CLI not installed; can't verify"
    WARN=$((WARN+1))
  fi
fi

# post_install — not verifiable
HAS=$(awk -F'\t' '$1=="post_install" {found=1} END {print found+0}' "$RECORDS")
if [ "$HAS" = "1" ]; then
  COUNT=$(awk -F'\t' '$1=="post_install"' "$RECORDS" | wc -l | tr -d ' ')
  echo "--- post_install ---"
  echo "  ↻ $COUNT command(s) — not verifiable, trust the apply-profile run"
  WARN=$((WARN+1))
fi

# accounts / security — printed only
COUNT_A=$(awk -F'\t' '$1=="accounts"' "$RECORDS" | wc -l | tr -d ' ')
COUNT_S=$(awk -F'\t' '$1=="security"' "$RECORDS" | wc -l | tr -d ' ')
if [ "$COUNT_A" -gt 0 ]; then
  echo "=== Account checklist ==="
  echo "  ↻ $COUNT_A item(s) — verify manually in references/CHECKLIST-ACCOUNTS.md"
  WARN=$((WARN+1))
fi
if [ "$COUNT_S" -gt 0 ]; then
  echo "=== Security checklist ==="
  echo "  ↻ $COUNT_S item(s) — verify manually in references/CHECKLIST-SECURITY.md"
  WARN=$((WARN+1))
fi

echo ""
if [ "$MISSING" -gt 0 ]; then
  echo "Exit: 2 ($MISSING missing package(s)) — re-run apply-profile.sh"
  exit 2
fi
if [ "$WARN" -gt 0 ]; then
  echo "Exit: 1 ($WARN manual-check warning(s))"
  exit 1
fi
echo "Exit: 0 (all clear)"
exit 0
