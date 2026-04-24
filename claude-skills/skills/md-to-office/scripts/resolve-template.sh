#!/usr/bin/env bash
# Resolve the Office template to use for a given target (docx|pptx|xlsx).
#
# Usage:
#   resolve-template.sh <target> [--override <path>]
#
# Prints the resolved template path on stdout, or nothing if no template
# was found. Exit code is 0 in both cases — "no template" is a valid
# state (unbranded rendering fallback, see PRD-008 §5.3).
#
# Resolution chain (first hit wins):
#   1. --override <path>                              explicit CLI override
#   2. $BSG_BRAND_TEMPLATES/<target>.{docx,pptx,xlsx} env var (tests / CI)
#   3. ./brand/templates/<target>.{docx,pptx,xlsx}    canonical per-repo
#   4. ./brand/templates/reference.docx               legacy pandoc alias (docx only)
#   5. (none)                                         prints nothing, exit 0

set -euo pipefail

target=""
override=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --override) override="${2:-}"; shift 2 ;;
    -*) echo "Unknown flag: $1" >&2; exit 2 ;;
    *)
      if [[ -z "$target" ]]; then target="$1"; shift
      else echo "Too many positional args: $1" >&2; exit 2
      fi
      ;;
  esac
done

case "$target" in
  docx|pptx|xlsx) ;;
  *) echo "Unknown target: '$target' (want docx|pptx|xlsx)" >&2; exit 2 ;;
esac

extension_for() {
  case "$1" in
    docx) echo "docx" ;;
    pptx) echo "pptx" ;;
    xlsx) echo "xlsx" ;;
  esac
}
ext="$(extension_for "$target")"

# 1. Explicit override.
if [[ -n "$override" ]]; then
  if [[ ! -f "$override" ]]; then
    echo "Template override not found: $override" >&2
    exit 2
  fi
  echo "$override"
  exit 0
fi

# 2. Env var pointing at a template directory.
if [[ -n "${BSG_BRAND_TEMPLATES:-}" ]]; then
  candidate="${BSG_BRAND_TEMPLATES%/}/${target}.${ext}"
  if [[ -f "$candidate" ]]; then
    echo "$candidate"
    exit 0
  fi
fi

# 3. Canonical per-repo convention.
candidate="./brand/templates/${target}.${ext}"
if [[ -f "$candidate" ]]; then
  echo "$candidate"
  exit 0
fi

# 4. Legacy alias — docx only.
if [[ "$target" == "docx" ]]; then
  legacy="./brand/templates/reference.docx"
  if [[ -f "$legacy" ]]; then
    echo "$legacy"
    exit 0
  fi
fi

# 5. No template found — success, empty output.
exit 0
