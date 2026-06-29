#!/usr/bin/env bash
# md-to-word.sh — generic branded markdown → .docx converter
# Reads brand tokens from .bsg/DESIGN.md in the repo root.
#
# Usage: md-to-word.sh <file.md> [--force-template] [--logo /path/to/logo.png]
#   --force-template  Regenerate brand/templates/reference.docx even if present
#   --logo PATH       Override the cover logo (else: DESIGN.md company match,
#                     then generic discovery). Also settable via $MD_TO_WORD_LOGO.
set -euo pipefail

FILE="${1:-}"
if [[ -z "$FILE" || ! -f "$FILE" ]]; then
  echo "Usage: md-to-word.sh <file.md> [--force-template] [--logo PATH]" >&2
  exit 1
fi
shift

FORCE_TEMPLATE=false
LOGO="${MD_TO_WORD_LOGO:-}"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --force-template) FORCE_TEMPLATE=true; shift ;;
    --logo)           LOGO="${2:-}"; shift 2 ;;
    *)                shift ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
FILE_ABS="$(cd "$(dirname "$FILE")" && pwd)/$(basename "$FILE")"

# Walk up to repo root (.git or .claude directory)
REPO_ROOT="$(cd "$(dirname "$FILE_ABS")" && pwd)"
while [[ "$REPO_ROOT" != "/" ]]; do
  [[ -d "$REPO_ROOT/.git" || -d "$REPO_ROOT/.claude" ]] && break
  REPO_ROOT="$(dirname "$REPO_ROOT")"
done

TEMPLATE_PATH="$REPO_ROOT/brand/templates/reference.docx"
OUTPUT="${FILE_ABS%.md}.docx"
PANDOC=$(command -v pandoc 2>/dev/null || echo /opt/homebrew/bin/pandoc)

# 1. Generate branded reference.docx from .bsg/DESIGN.md
if [[ ! -f "$TEMPLATE_PATH" || "$FORCE_TEMPLATE" == true ]]; then
  echo "→ Génération du template depuis .bsg/DESIGN.md…"
  python3 "$SKILL_DIR/scripts/generate-template.py" \
    "$TEMPLATE_PATH" \
    --repo "$REPO_ROOT"
fi

# 2. Extract document title
#    Priority: YAML front matter title: > first # heading
TITLE=$(grep -m1 '^title:' "$FILE_ABS" | sed "s/^title:[[:space:]]*//" | tr -d '"' || true)
if [[ -z "$TITLE" ]]; then
  TITLE=$(grep -m1 '^# ' "$FILE_ABS" | sed 's/^# //' || true)
fi

# 3. pandoc: TOC in French, --- → vertical gap, title metadata
PANDOC_ARGS=(
  --from=markdown
  --to=docx
  "--reference-doc=$TEMPLATE_PATH"
  "--lua-filter=$SKILL_DIR/scripts/pagebreak.lua"
  --toc
  --toc-depth=3
  "--metadata=toc-title:Sommaire"
  "--output=$OUTPUT"
)
[[ -n "$TITLE" ]] && PANDOC_ARGS+=("--metadata=title:$TITLE")

echo "→ Conversion pandoc…"
"$PANDOC" "$FILE_ABS" "${PANDOC_ARGS[@]}"

# 4. Post-process: logo + full-width branded tables
echo "→ Post-traitement…"
POST_ARGS=("$OUTPUT" --repo "$REPO_ROOT")
[[ -n "$LOGO" ]] && POST_ARGS+=(--logo "$LOGO")
python3 "$SKILL_DIR/scripts/post-process.py" "${POST_ARGS[@]}"

echo "✓ Exporté : $OUTPUT"
