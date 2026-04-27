#!/usr/bin/env bash
# Brand initialization orchestrator.
#
# Usage:
#   init-brand.sh [--force] [--tokens-only] [--dry-run]
#
# --force         Overwrite existing brand/tokens.json and templates.
# --tokens-only   Only run the repo scan; skip template generation.
#                 Useful to review what was detected before committing.
# --dry-run       Scan and show what would be extracted without writing
#                 templates. Writes tokens.json and brand-audit.md only.
#
# Flow:
#   1. Scan the repo for brand signals  → brand/tokens.json
#   2. Generate brand audit             → brand/templates/brand-audit.md
#   3. Generate Office templates        → brand/templates/{reference.docx,template.pptx,template.xlsx}
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

while [[ $# -gt 0 ]]; do
  case "$1" in
    --force)       force=1;       shift ;;
    --tokens-only) tokens_only=1; shift ;;
    --dry-run)     dry_run=1;     shift ;;
    -*) echo "Unknown flag: $1" >&2; exit 2 ;;
    *)  echo "Unexpected argument: $1" >&2; exit 2 ;;
  esac
done

brand_dir="./brand"
tokens_path="${brand_dir}/tokens.json"
templates_dir="${brand_dir}/templates"
audit_path="${templates_dir}/brand-audit.md"

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

echo "Scanning repo for brand signals…"

scan_args=(--audit "$audit_path")
python3 "$here/scan-brand.py" "${scan_args[@]}" > "$tokens_path"
echo ""
echo "Tokens written to ${tokens_path}"

if [[ $dry_run -eq 1 ]]; then
  echo ""
  echo "Dry run — no templates generated."
  echo "Review:"
  echo "  ${tokens_path}  (extracted tokens)"
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
echo "  1. Review brand/tokens.json (edit primary colour, font, etc.)"
echo "  2. Review brand/templates/brand-audit.md for discovery details"
echo "  3. Open brand/templates/ files and apply your team's final brand"
echo "     (logo, exact palette, slide backgrounds, footer text)"
echo "  4. Re-run with --force after editing tokens.json to regenerate"
echo "  5. git add brand/ && git commit -m 'brand: initialize office templates'"
