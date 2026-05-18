#!/usr/bin/env bash
# collect.sh — SEO snapshot.
#
# Enumerates pages, extracts meta tags and internal links, parses
# sitemap/robots, loads KEYWORDS.md (resolved via _bsg-paths.sh —
# `.bsg/KEYWORDS.md` preferred, legacy `seo/KEYWORDS.md` fallback per
# ADR-001). Outputs a single JSON document.

set -euo pipefail

REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
cd "$REPO_ROOT"

# Shared path resolver. Lives at <repo>/claude-skills/scripts/_bsg-paths.sh,
# i.e. three levels up from this skill's scripts/ dir. It can be absent in a
# stripped Donna install (the skill is synced without the sibling scripts/
# tree) — fail loud rather than crash mid-pipeline with an opaque error.
BSG_PATHS="$(dirname "$0")/../../../scripts/_bsg-paths.sh"
if [[ ! -f "$BSG_PATHS" ]]; then
  echo "ERROR: _bsg-paths.sh not found at $BSG_PATHS" >&2
  echo "       expected <repo>/claude-skills/scripts/_bsg-paths.sh relative to the skill dir;" >&2
  echo "       the seo-report skill must be installed with its sibling scripts/ tree." >&2
  exit 1
fi
# shellcheck source=../../../scripts/_bsg-paths.sh disable=SC1091
source "$BSG_PATHS"

# Read stdin lines into a JSON string array, always emitting valid JSON even
# on empty input. Plain `grep ... | jq -Rn '[inputs]'` crashes `jq --argjson`
# under `set -euo pipefail` when grep finds nothing (e.g. JSX/TSX files with
# no raw href attributes): the failed grep trips pipefail and the empty/garbled
# value reaches --argjson. Routing through this helper guarantees a valid array.
to_json_array() {
  local out
  out=$(jq -Rn '[inputs]' 2>/dev/null) || out='[]'
  printf '%s' "${out:-[]}"
}

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

  # Pull out internal link targets. Matches plain `<a href="/x">` as well as
  # Next.js / JSX forms: `<Link href="/x">`, `href={'/x'}`, `href={"/x"}`,
  # and `to="/x"` (react-router). Each grep is `|| true`-guarded so a no-match
  # never trips pipefail; to_json_array always yields a valid array.
  q="[\"']"
  targets=$(
    { grep -oE "(href|to)=\{?${q}[^\"'>} ]+" "$f" 2>/dev/null || true; } \
      | sed -E "s/^(href|to)=\{?${q}//" \
      | { grep -E '^/' || true; } \
      | { grep -v '^#' || true; } \
      | sort -u \
      | to_json_array
  )

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
  SITEMAP_URLS_JSON=$(
    { grep -oE '<loc>[^<]+</loc>' "$SITEMAP_PATH" 2>/dev/null || true; } \
      | sed -E 's|<loc>||; s|</loc>||' \
      | to_json_array
  )
fi

ROBOTS_BLANKET="false"
if [[ -n "$ROBOTS_PATH" ]]; then
  if grep -qiE '^Disallow:[[:space:]]*/[[:space:]]*$' "$ROBOTS_PATH" 2>/dev/null; then
    ROBOTS_BLANKET="true"
  fi
fi

# ---------------------------------------------------- keywords

KEYWORDS_PATH="$(bsg_doc_path keywords)"
KEYWORDS_JSON='null'
if [[ -f "$KEYWORDS_PATH" ]]; then
  KEYWORDS_JSON=$(
    { grep -oE '^-[[:space:]]+.+' "$KEYWORDS_PATH" || true; } \
      | sed -E 's/^-[[:space:]]+//' \
      | to_json_array
  )
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
