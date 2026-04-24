#!/usr/bin/env bash
# md-to-office orchestrator.
#
# Usage:
#   md-to-office.sh <input.md> [--target docx] [--template <path>] [--out <path>] [--force]
#   md-to-office.sh --init [--force] [--tokens-only]
#   md-to-office.sh --install [--dry-run]
#
# --init scans this repo for brand signals (CSS variables, Tailwind config,
#   package.json, README…) and generates brand/templates/ so future renders
#   are automatically branded. Safe to re-run with --force after editing
#   brand/tokens.json.
#
# Writes <input>.docx next to the source by default (or --out if given).
# Idempotent: if output exists and is newer than input, skip unless
# --force is set.

set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"

usage() {
  sed -n '3,14p' "$0"
  exit "${1:-0}"
}

src=""
target="docx"
template=""
out=""
force=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help) usage 0 ;;
    --init)
      shift
      bash "$here/init-brand.sh" "$@"
      exit $?
      ;;
    --install)
      shift
      bash "$here/install-local.sh" "$@"
      exit $?
      ;;
    --target)   target="${2:?}";   shift 2 ;;
    --template) template="${2:?}"; shift 2 ;;
    --out)      out="${2:?}";      shift 2 ;;
    --force)    force=1;            shift ;;
    --)         shift; src="${1:?}"; shift ;;
    -*)         echo "Unknown flag: $1" >&2; usage 2 ;;
    *)
      if [[ -z "$src" ]]; then src="$1"; shift
      else echo "Too many positional args: $1" >&2; usage 2
      fi
      ;;
  esac
done

[[ -n "$src" ]] || usage 2
[[ -f "$src" ]] || { echo "File not found: $src" >&2; exit 2; }

case "$target" in
  docx) ;;
  pptx|xlsx)
    echo "Target '$target' is not implemented in v0.1 (PR #1 ships DOCX only). See PRD-008 §12." >&2
    exit 4
    ;;
  *)
    echo "Unknown target: '$target' (want docx|pptx|xlsx)" >&2
    exit 2
    ;;
esac

# Default output path: swap/append the target extension next to source.
if [[ -z "$out" ]]; then
  base="${src%.md}"
  [[ "$base" == "$src" ]] && base="$src"   # source had no .md suffix
  out="${base}.${target}"
fi

# Idempotency: skip if output is fresher than input.
if [[ -f "$out" && $force -eq 0 && "$out" -nt "$src" ]]; then
  echo "$out (cached; use --force to re-render)"
  exit 0
fi

mkdir -p "$(dirname "$out")"

# Resolve template (empty string = unbranded fallback).
resolve_args=("$target")
if [[ -n "$template" ]]; then
  resolve_args+=(--override "$template")
fi
resolved="$(bash "$here/resolve-template.sh" "${resolve_args[@]}")"

# No template found: show contextual onboarding message.
if [[ -z "$resolved" ]]; then
  if [[ ! -d "./brand" && ! -d "./brand/templates" ]]; then
    echo "" >&2
    echo "ℹ️  No brand standard found for this repo." >&2
    echo "   Run once to analyse it and generate branded templates:" >&2
    echo "   md-to-office.sh --init" >&2
    echo "   Rendering unbranded for now." >&2
    echo "" >&2
  else
    echo "⚠️  brand/templates/ not found. Run 'md-to-office.sh --init' to generate templates." >&2
  fi
fi

render_args=("$src" "$out")
if [[ -n "$resolved" ]]; then
  render_args+=(--template "$resolved")
fi

bash "$here/render-${target}.sh" "${render_args[@]}" >/dev/null
echo "$out"
