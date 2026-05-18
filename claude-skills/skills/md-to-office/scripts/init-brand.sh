#!/usr/bin/env bash
# Brand initialization orchestrator.
#
# Usage:
#   init-brand.sh [--force] [--tokens-only] [--dry-run] [--no-scan]
#
# --force         Overwrite existing brand/tokens.json and templates.
# --tokens-only   Only run the repo scan; skip template generation.
#                 Useful to review what was detected before committing.
# --dry-run       Scan and show what would be extracted without writing
#                 templates. Writes tokens.json and brand-audit.md only.
# --no-scan       Skip scan-brand.py and use the existing tokens.json as-is.
#                 Preserves manual edits to tokens.json. Errors if tokens.json
#                 is missing. Composes with --force (template regen only).
#
# Flow:
#   1. Scan the repo for brand signals  → brand/tokens.json
#   2. Generate design-system spec      → .bsg/DESIGN.md (Google Stitch format)
#   3. Generate brand audit             → brand/templates/brand-audit.md
#   4. Generate Office templates        → brand/templates/{reference.docx,template.pptx,template.xlsx}
#
# .bsg/DESIGN.md is the canonical design-system source (#237); brand/tokens.json
# is derived from the same scan. With --no-scan both are preserved as-is.
#
# Templates are discovered from:
#   CSS custom properties, tailwind.config.*, design-token JSON files,
#   @font-face / Google Fonts imports, logo files, identity documents,
#   package.json / pyproject.toml / stack.yaml / README.md, git remote.

set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"

force=0
tokens_only=0
dry_run=0
no_scan=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --force)       force=1;       shift ;;
    --tokens-only) tokens_only=1; shift ;;
    --dry-run)     dry_run=1;     shift ;;
    --no-scan)     no_scan=1;     shift ;;
    -*) echo "Unknown flag: $1" >&2; exit 2 ;;
    *)  echo "Unexpected argument: $1" >&2; exit 2 ;;
  esac
done

brand_dir="./brand"
tokens_path="${brand_dir}/tokens.json"
templates_dir="${brand_dir}/templates"
audit_path="${templates_dir}/brand-audit.md"
design_path="./.bsg/DESIGN.md"

# Guard: require --force if already initialized (skip for --dry-run).
if [[ $dry_run -eq 0 ]] && [[ -d "$templates_dir" ]] && [[ -n "$(ls -A "$templates_dir" 2>/dev/null)" ]] && [[ $force -eq 0 ]]; then
  echo "Brand templates already exist at ${templates_dir}/."
  echo "Use --force to overwrite."
  exit 0
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "python3 not found. Install it first." >&2
  exit 1
fi

mkdir -p "$brand_dir"

if [[ $no_scan -eq 1 ]]; then
  if [[ ! -f "$tokens_path" ]]; then
    echo "Error: --no-scan requires an existing ${tokens_path} but none was found." >&2
    exit 1
  fi
  echo "Skipping scan — using existing ${tokens_path}"
else
  echo "Scanning repo for brand signals…"
  mkdir -p "$(dirname "$design_path")"
  scan_args=(--audit "$audit_path" --design "$design_path")
  python3 "$here/scan-brand.py" "${scan_args[@]}" > "$tokens_path"
  echo ""
  echo "Tokens written to ${tokens_path}"
  echo "Design system written to ${design_path}"
fi

if [[ $dry_run -eq 1 ]]; then
  echo ""
  echo "Dry run — no templates generated."
  echo "Review:"
  echo "  ${tokens_path}  (extracted tokens)"
  echo "  ${design_path}  (design-system spec)"
  echo "  ${audit_path}   (full audit of what was found)"
  exit 0
fi

if [[ $tokens_only -eq 1 ]]; then
  echo ""
  echo "Review ${tokens_path}, then run without --tokens-only to generate Office templates."
  exit 0
fi

echo ""
echo "Generating Office templates…"
python3 "$here/generate-templates.py" 2>&1 | sed 's/^/  /'

echo ""
echo "Brand standard initialized."
echo ""
echo "Next steps:"
echo "  1. Review .bsg/DESIGN.md — the canonical design-system spec"
echo "     (palette, typography, spacing, components, accessibility)"
echo "  2. Review brand/tokens.json (derived; edit primary colour, font, etc.)"
echo "  3. Review brand/templates/brand-audit.md for discovery details"
echo "  4. Open brand/templates/ files and apply your team's final brand"
echo "     (logo, exact palette, slide backgrounds, footer text)"
echo "  5. Re-run with --force after editing to regenerate"
echo "  6. git add .bsg/DESIGN.md brand/ && git commit -m 'brand: initialize design system'"
