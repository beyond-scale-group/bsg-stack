#!/usr/bin/env bash
# prod-checks.sh — opt-in production verification for the SEO audit.
#
# Source-at-rest analysis (collect.sh) cannot tell what is actually
# deployed: missing env vars, 404 on the OG image, 307-vs-301 host
# redirects, JSON-LD that exists in source but is stripped at build,
# analytics that never shipped. This script makes a small number of
# targeted, read-only HTTP requests against the live site and emits a
# `## Production checks` markdown section for generate-report.sh.
#
# It is OPT-IN (never runs during the default source-at-rest audit) and
# NON-FATAL: any failure degrades to a reported warning rather than
# aborting the report, so `@seo tick` stays robust.
#
# Usage:
#   bash prod-checks.sh https://www.example.com
#
# Exit code is always 0 — findings are in the markdown, not the status.

set -uo pipefail

UA='bsg-seo-report/1.0 (+https://github.com/beyond-scale-group/bsg-stack)'
CONNECT_TIMEOUT=10
MAX_TIME=20

emit_section_header() { printf '## Production checks\n\n'; }

BASE="${1:-}"

if [[ -z "$BASE" ]]; then
  emit_section_header
  printf '_Skipped: no production URL resolved (pass `--prod <url>`, or set '
  printf '`SEO_SITE_URL`/`SITE_URL`, or add `site_url:` to AUTOPILOT.yml)._\n'
  exit 0
fi

if ! command -v curl >/dev/null 2>&1; then
  emit_section_header
  printf '_Skipped: `curl` is not available in this environment._\n'
  exit 0
fi

# Normalise: strip trailing slash, ensure scheme.
BASE="${BASE%/}"
[[ "$BASE" =~ ^https?:// ]] || BASE="https://$BASE"

# host without scheme, and the apex/www counterpart for the redirect check.
HOST="${BASE#*://}"
HOST="${HOST%%/*}"
SCHEME="${BASE%%://*}"
if [[ "$HOST" == www.* ]]; then
  ALT_HOST="${HOST#www.}"
else
  ALT_HOST="www.$HOST"
fi

# ----------------------------------------------------------- http helpers

# http_status URL -> "000" on transport failure, else the HTTP code.
# curl already prints "000" on connection failure; capture once and
# default — appending `|| echo 000` would double-emit ("000000").
http_status() {
  local c
  c=$(curl -s -o /dev/null -w '%{http_code}' -A "$UA" -L \
    --connect-timeout "$CONNECT_TIMEOUT" --max-time "$MAX_TIME" \
    "$1" 2>/dev/null)
  printf '%s' "${c:-000}"
}

# http_body URL -> response body (follows redirects).
http_body() {
  curl -sS -A "$UA" -L \
    --connect-timeout "$CONNECT_TIMEOUT" --max-time "$MAX_TIME" \
    "$1" 2>/dev/null || true
}

# redirect_status URL -> "<code> <location>" WITHOUT following redirects.
redirect_status() {
  local out code loc
  out=$(curl -s -o /dev/null \
    -w '%{http_code} %{redirect_url}' -A "$UA" \
    --connect-timeout "$CONNECT_TIMEOUT" --max-time "$MAX_TIME" \
    "$1" 2>/dev/null)
  out="${out:-000 }"
  code="${out%% *}"
  loc="${out#* }"
  printf '%s|%s' "$code" "$loc"
}

ok() { [[ "$1" == "200" ]] && printf 'ok' || printf '**HTTP %s**' "$1"; }

# --------------------------------------------------------- sitemap / robots

SITEMAP_URL="$BASE/sitemap.xml"
ROBOTS_URL="$BASE/robots.txt"

SITEMAP_CODE=$(http_status "$SITEMAP_URL")
SITEMAP_BODY=""
SITEMAP_COUNT=0
if [[ "$SITEMAP_CODE" == "200" ]]; then
  SITEMAP_BODY=$(http_body "$SITEMAP_URL")
  SITEMAP_COUNT=$(printf '%s' "$SITEMAP_BODY" | grep -c '<loc>' 2>/dev/null || true)
  SITEMAP_COUNT=${SITEMAP_COUNT:-0}
fi

ROBOTS_CODE=$(http_status "$ROBOTS_URL")
ROBOTS_HAS_SITEMAP="no"
if [[ "$ROBOTS_CODE" == "200" ]]; then
  if http_body "$ROBOTS_URL" | grep -qiE '^[[:space:]]*sitemap:' 2>/dev/null; then
    ROBOTS_HAS_SITEMAP="yes"
  fi
fi

# --------------------------------------------------- homepage-derived data

HOME_BODY=$(http_body "$BASE/")
HOME_CODE=$(http_status "$BASE/")

# Canonical: prefer rel="canonical" link; must be an absolute URL.
extract_canonical() {
  printf '%s' "$1" \
    | grep -oiE '<link[^>]*rel=["'\'']canonical["'\''][^>]*>' 2>/dev/null \
    | head -1 \
    | grep -oiE 'href=["'\''][^"'\'']*["'\'']' 2>/dev/null \
    | head -1 \
    | sed -E 's/^href=["'\'']//; s/["'\'']$//' || true
}

HOME_CANONICAL=$(extract_canonical "$HOME_BODY")
if [[ -z "$HOME_CANONICAL" ]]; then
  HOME_CANON_STATUS='**missing**'
elif [[ "$HOME_CANONICAL" =~ ^https?:// ]]; then
  HOME_CANON_STATUS="absolute (\`$HOME_CANONICAL\`)"
else
  HOME_CANON_STATUS="**relative** (\`$HOME_CANONICAL\`)"
fi

# JSON-LD @type values present in the rendered HTML.
JSONLD_TYPES=$(printf '%s' "$HOME_BODY" \
  | grep -oiE '"@type"[[:space:]]*:[[:space:]]*"[^"]+"' 2>/dev/null \
  | sed -E 's/.*:[[:space:]]*"//; s/"$//' \
  | sort -u | paste -sd ',' - 2>/dev/null || true)
[[ -n "$JSONLD_TYPES" ]] || JSONLD_TYPES=""

# OG image URL + reachability.
OG_IMAGE=$(printf '%s' "$HOME_BODY" \
  | grep -oiE '<meta[^>]*property=["'\'']og:image["'\''][^>]*>' 2>/dev/null \
  | head -1 \
  | grep -oiE 'content=["'\''][^"'\'']*["'\'']' 2>/dev/null \
  | sed -E 's/^content=["'\'']//; s/["'\'']$//' || true)
OG_STATUS='**missing**'
if [[ -n "$OG_IMAGE" ]]; then
  [[ "$OG_IMAGE" =~ ^https?:// ]] || OG_IMAGE="$BASE/${OG_IMAGE#/}"
  OG_CODE=$(http_status "$OG_IMAGE")
  OG_STATUS="$(ok "$OG_CODE")"
fi

# Analytics: GA4 / Meta Pixel signatures in rendered HTML.
ANALYTICS=()
if printf '%s' "$HOME_BODY" | grep -qiE 'googletagmanager\.com/gtag/js|gtag\(|G-[A-Z0-9]{6,}' 2>/dev/null; then
  ANALYTICS+=("GA4")
fi
if printf '%s' "$HOME_BODY" | grep -qiE 'connect\.facebook\.net|fbq\(' 2>/dev/null; then
  ANALYTICS+=("Meta Pixel")
fi
if [[ ${#ANALYTICS[@]} -gt 0 ]]; then
  ANALYTICS_STATUS="detected ($(IFS=,; echo "${ANALYTICS[*]}"))"
else
  ANALYTICS_STATUS='**none detected**'
fi

# ------------------------------------------- internal / pillar page checks

# Derive a few internal pages from the live sitemap (excludes homepage).
mapfile -t SITEMAP_URLS < <(printf '%s' "$SITEMAP_BODY" \
  | grep -oE '<loc>[^<]+</loc>' 2>/dev/null \
  | sed -E 's|<loc>||; s|</loc>||' \
  | grep -vE "^${BASE}/?$" \
  | head -5 || true)

CANON_INTERNAL_ROWS=""
checked=0
for u in "${SITEMAP_URLS[@]:-}"; do
  [[ -z "$u" ]] && continue
  [[ $checked -ge 2 ]] && break
  body=$(http_body "$u")
  c=$(extract_canonical "$body")
  if [[ -z "$c" ]]; then
    st='**missing**'
  elif [[ "$c" =~ ^https?:// ]]; then
    st='absolute'
  else
    st='**relative**'
  fi
  CANON_INTERNAL_ROWS+="| Canonical — \`$u\` | $st |"$'\n'
  checked=$((checked + 1))
done
[[ -n "$CANON_INTERNAL_ROWS" ]] || CANON_INTERNAL_ROWS="| Canonical — internal pages | _no sitemap URLs to sample_ |"$'\n'

PILLAR_ROWS=""
PILLAR_FAIL=0
PILLAR_TARGETS=("$BASE/")
for u in "${SITEMAP_URLS[@]:-}"; do
  [[ -z "$u" ]] && continue
  PILLAR_TARGETS+=("$u")
done
for u in "${PILLAR_TARGETS[@]}"; do
  code=$(http_status "$u")
  [[ "$code" == "200" ]] || PILLAR_FAIL=$((PILLAR_FAIL + 1))
  PILLAR_ROWS+="| \`$u\` | $(ok "$code") |"$'\n'
done

# www vs apex: hitting the non-canonical host should 301 (not 307/302).
ALT_URL="$SCHEME://$ALT_HOST/"
REDIR=$(redirect_status "$ALT_URL")
REDIR_CODE="${REDIR%%|*}"
REDIR_LOC="${REDIR#*|}"
if [[ "$REDIR_CODE" == "301" ]]; then
  REDIR_STATUS="301 → \`${REDIR_LOC:-?}\`"
elif [[ "$REDIR_CODE" =~ ^30[0-9]$ ]]; then
  REDIR_STATUS="**$REDIR_CODE (expected 301)** → \`${REDIR_LOC:-?}\`"
elif [[ "$REDIR_CODE" == "200" ]]; then
  REDIR_STATUS="**200 (no redirect — duplicate host)**"
else
  REDIR_STATUS="**HTTP $REDIR_CODE**"
fi

# ------------------------------------------------------------------- emit

emit_section_header

printf '_Live checks against `%s` (read-only, opt-in)._\n\n' "$BASE"

printf '| Check | Result |\n|-------|--------|\n'
printf '| Homepage | %s |\n' "$(ok "$HOME_CODE")"
printf '| sitemap.xml | %s%s |\n' "$(ok "$SITEMAP_CODE")" \
  "$( [[ "$SITEMAP_CODE" == "200" ]] && printf ' — %s URLs' "$SITEMAP_COUNT" )"
printf '| robots.txt | %s%s |\n' "$(ok "$ROBOTS_CODE")" \
  "$( [[ "$ROBOTS_CODE" == "200" ]] && { [[ "$ROBOTS_HAS_SITEMAP" == "yes" ]] && printf ' — Sitemap: present' || printf ' — **Sitemap: missing**'; } )"
printf '| Canonical — homepage | %s |\n' "$HOME_CANON_STATUS"
printf '%s' "$CANON_INTERNAL_ROWS"
printf '| JSON-LD types | %s |\n' "$( [[ -n "$JSONLD_TYPES" ]] && printf '%s' "$JSONLD_TYPES" || printf '**none detected**' )"
printf '| OG image | %s%s |\n' "$OG_STATUS" \
  "$( [[ -n "$OG_IMAGE" ]] && printf ' (`%s`)' "$OG_IMAGE" )"
printf '| Analytics | %s |\n' "$ANALYTICS_STATUS"
printf '| www vs apex redirect | %s |\n' "$REDIR_STATUS"

printf '\n### Pillar pages\n\n'
printf '| Page | Status |\n|------|--------|\n'
printf '%s' "$PILLAR_ROWS"
if [[ "$PILLAR_FAIL" -gt 0 ]]; then
  printf '\n**%s pillar page(s) did not return HTTP 200.**\n' "$PILLAR_FAIL"
fi

exit 0
