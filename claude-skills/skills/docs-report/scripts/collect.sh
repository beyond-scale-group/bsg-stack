#!/usr/bin/env bash
# collect.sh — single discovery pass for docs-report.
#
# Emits a JSON snapshot covering every tracked markdown file, the
# repo's README/CHANGELOG/.bsg/ classification, package.json scripts,
# Makefile targets, and git tags. Every other reporter in this skill
# consumes this snapshot rather than re-walking the tree.

set -euo pipefail

REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
cd "$REPO_ROOT"

GENERATED_AT=$(date -u +%Y-%m-%dT%H:%M:%SZ)

# --- markdown inventory -----------------------------------------------------
# git ls-files keeps us in sync with the repo's idea of "tracked", which
# excludes generated docs (site/, _build/, etc.) without us having to
# duplicate .gitignore logic.
MD_FILES=$(git ls-files '*.md' '*.markdown' 2>/dev/null || true)

# Build markdownFiles[] as JSON. Each entry: { path, links[], lastModified }.
# Link extraction uses the inline markdown form: [text](target). We strip
# fragments (#anchor) and query strings — file existence is all we care about.
MD_JSON='[]'
while IFS= read -r f; do
  [ -z "$f" ] && continue
  [ -f "$f" ] || continue
  LINKS=$( { grep -oE '\[[^]]*\]\([^)]+\)' "$f" 2>/dev/null || true; } \
    | sed -E 's/.*\(([^)]+)\)/\1/' \
    | sed -E 's/[#?].*$//' \
    | awk 'NF' \
    | jq -R -s -c 'split("\n") | map(select(length > 0))')
  LAST_MOD=$(git log -1 --format=%cs -- "$f" 2>/dev/null || echo "")
  MD_JSON=$(jq --arg path "$f" --argjson links "$LINKS" --arg lm "$LAST_MOD" \
    '. + [{path: $path, links: $links, lastModified: $lm}]' <<<"$MD_JSON")
done <<<"$MD_FILES"

# --- READMEs / CHANGELOG / .bsg/ docs --------------------------------------
READMES=$(jq -c '[.[] | .path | select(test("(^|/)README\\.md$"; "i"))]' <<<"$MD_JSON")
CHANGELOG=$(jq -r '[.[] | .path | select(test("(^|/)CHANGELOG\\.md$"; "i"))] | .[0] // ""' <<<"$MD_JSON")
BSG_DOCS=$(jq -c '[.[] | .path | select(startswith(".bsg/")) | select(startswith(".bsg/adr/") | not)]' <<<"$MD_JSON")

# --- package.json scripts ---------------------------------------------------
PKG_SCRIPTS='[]'
if [ -f package.json ]; then
  PKG_SCRIPTS=$(jq -c '(.scripts // {}) | keys' package.json 2>/dev/null || echo '[]')
fi

# --- Makefile targets -------------------------------------------------------
MAKE_TARGETS='[]'
if [ -f Makefile ]; then
  MAKE_TARGETS=$( { grep -E '^[a-zA-Z0-9_.-]+:([^=]|$)' Makefile 2>/dev/null || true; } \
    | sed -E 's/^([a-zA-Z0-9_.-]+):.*/\1/' \
    | sort -u \
    | jq -R -s -c 'split("\n") | map(select(length > 0))')
fi

# --- git tags ---------------------------------------------------------------
GIT_TAGS=$( { git tag --list 2>/dev/null || true; } \
  | jq -R -s -c 'split("\n") | map(select(length > 0))')

# --- compose ----------------------------------------------------------------
jq -n \
  --arg generatedAt "$GENERATED_AT" \
  --arg repoRoot "$REPO_ROOT" \
  --arg changelog "$CHANGELOG" \
  --argjson markdownFiles "$MD_JSON" \
  --argjson readmes "$READMES" \
  --argjson bsgDocs "$BSG_DOCS" \
  --argjson packageScripts "$PKG_SCRIPTS" \
  --argjson makefileTargets "$MAKE_TARGETS" \
  --argjson gitTags "$GIT_TAGS" \
  '{
    generatedAt: $generatedAt,
    repoRoot: $repoRoot,
    markdownFiles: $markdownFiles,
    readmes: $readmes,
    changelog: (if $changelog == "" then null else $changelog end),
    bsgDocs: $bsgDocs,
    packageScripts: $packageScripts,
    makefileTargets: $makefileTargets,
    gitTags: $gitTags
  }'
