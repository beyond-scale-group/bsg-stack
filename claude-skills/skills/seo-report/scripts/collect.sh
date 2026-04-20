#!/usr/bin/env bash
# collect.sh — SEO snapshot.
#
# Enumerates pages, extracts meta tags and internal links, parses
# sitemap/robots, loads KEYWORDS.md. Outputs a single JSON document.

set -euo pipefail

REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
cd "$REPO_ROOT"

# -------------------------------------------- page file enumeration

# Extensions that can host page-level meta tags.
PAGE_EXT_REGEX='\.(html|htm|jsx|tsx|vue|svelte|astro)$'

PAGE_FILES=$(git ls-files 2>/dev/null | grep -E "$PAGE_EXT_REGEX" || true)

# Map a file path to an inferred route. Supports Next.js-style
# `pages/` and `app/`, Astro `src/pages/`, and plain .html.
infer_route() {
  local f=$1
  # Common framework roots
  local route="$f"
  for root in "src/pages" "app" "pages" "public" ""; do
    [[ -z "$root" ]] && break
    if [[ "$route" == "$root"/* ]]; then
      route="${route#"$root"/}"
      break
    fi
  done
  # Strip extension and index-ish basenames
  route=${route%.*}
  route=${route%/index}
  [[ "$route" == "index" ]] && route=""
  printf '/%s' "$route"
}

# ------------------------------------------- per-page meta extraction

PAGES_JSON='[]'
while IFS= read -r f; do
  [[ -z "$f" || ! -f "$f" ]] && continue
  route=$(infer_route "$f")

  # Extract the raw strings via grep.
  title=$(grep -oEi '<title>[^<]+</title>' "$f" 2>/dev/null \
    | head -1 | sed -E 's|<title>||I; s|</title>||I' \
    || true)
  description=$(grep -oEi '<meta[^>]*name="description"[^>]*>' "$f" 2>/dev/null \
    | head -1 | grep -oE 'content="[^"]*"' | sed 's/content="//; s/"$//' \
    || true)
  canonical=$(grep -oEi '<link[^>]*rel="canonical"[^>]*>' "$f" 2>/dev/null \
    | head -1 | grep -oE 'href="[^"]*"' | sed 's/href="//; s/"$//' \
    || true)
  og_title=$(grep -oEi '<meta[^>]*property="og:title"[^>]*>' "$f" 2>/dev/null | head -1 || true)
  og_desc=$(grep -oEi '<meta[^>]*property="og:description"[^>]*>' "$f" 2>/dev/null | head -1 || true)
  og_image=$(grep -oEi '<meta[^>]*property="og:image"[^>]*>' "$f" 2>/dev/null | head -1 || true)

  # Pull out internal link targets: href="/something" (not starting with http: or mailto: or tel:).
  targets=$(grep -oE 'href="[^"]+"' "$f" 2>/dev/null \
    | sed 's/href="//; s/"$//' \
    | grep -E '^/' \
    | grep -v '^#' \
    | sort -u \
    | jq -Rn '[inputs]' 2>/dev/null || echo '[]')

  has_jsonld="false"
  if grep -qE 'type="application/ld\+json"' "$f" 2>/dev/null; then
    has_jsonld="true"
  fi

  PAGES_JSON=$(jq \
    --arg file "$f" \
    --arg route "$route" \
    --arg title "$title" \
    --arg description "$description" \
    --arg canonical "$canonical" \
    --arg og_title "$og_title" \
    --arg og_desc "$og_desc" \
    --arg og_image "$og_image" \
    --argjson targets "$targets" \
    --arg has_jsonld "$has_jsonld" '
    . + [{
      file: $file,
      route: $route,
      title: (if $title == "" then null else $title end),
      description: (if $description == "" then null else $description end),
      canonical: (if $canonical == "" then null else $canonical end),
      og: {
        title: ($og_title != ""),
        description: ($og_desc != ""),
        image: ($og_image != "")
      },
      internalLinks: $targets,
      hasJsonLd: ($has_jsonld == "true")
    }]
  ' <<<"$PAGES_JSON")
done <<< "$PAGE_FILES"

# ---------------------------------------------------- sitemap / robots

find_first() {
  for p in "$@"; do
    if [[ -f "$p" ]]; then
      printf '%s' "$p"
      return 0
    fi
  done
  return 1
}

SITEMAP_PATH=$(find_first sitemap.xml public/sitemap.xml static/sitemap.xml dist/sitemap.xml || true)
ROBOTS_PATH=$(find_first robots.txt public/robots.txt static/robots.txt dist/robots.txt || true)

SITEMAP_URLS_JSON='[]'
if [[ -n "$SITEMAP_PATH" ]]; then
  SITEMAP_URLS_JSON=$(grep -oE '<loc>[^<]+</loc>' "$SITEMAP_PATH" 2>/dev/null \
    | sed -E 's|<loc>||; s|</loc>||' \
    | jq -Rn '[inputs]' 2>/dev/null || echo '[]')
fi

ROBOTS_BLANKET="false"
if [[ -n "$ROBOTS_PATH" ]]; then
  if grep -qiE '^Disallow:[[:space:]]*/[[:space:]]*$' "$ROBOTS_PATH" 2>/dev/null; then
    ROBOTS_BLANKET="true"
  fi
fi

# ---------------------------------------------------- keywords

KEYWORDS_JSON='null'
if [[ -f seo/KEYWORDS.md ]]; then
  KEYWORDS_JSON=$({ grep -oE '^-[[:space:]]+.+' seo/KEYWORDS.md || true; } \
    | sed -E 's/^-[[:space:]]+//' \
    | jq -Rn '[inputs]' 2>/dev/null || echo '[]')
fi

# ---------------------------------------------------------- emit

jq -n \
  --arg repoRoot "$REPO_ROOT" \
  --arg generatedAt "$(date -u +%FT%TZ)" \
  --argjson pages "$PAGES_JSON" \
  --arg sitemapPath "${SITEMAP_PATH:-}" \
  --argjson sitemapUrls "$SITEMAP_URLS_JSON" \
  --arg robotsPath "${ROBOTS_PATH:-}" \
  --arg robotsBlanket "$ROBOTS_BLANKET" \
  --argjson keywords "$KEYWORDS_JSON" \
  '{
    repoRoot: $repoRoot,
    generatedAt: $generatedAt,
    pages: $pages,
    sitemap: {
      path: (if $sitemapPath == "" then null else $sitemapPath end),
      urls: $sitemapUrls
    },
    robots: {
      path: (if $robotsPath == "" then null else $robotsPath end),
      blanketDisallow: ($robotsBlanket == "true")
    },
    keywords: $keywords
  }'
