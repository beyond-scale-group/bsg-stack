#!/usr/bin/env bash
# prod-check.sh — opt-in production verification for the SEO audit.
#
# Source-at-rest analysis cannot see what is actually deployed: missing
# env vars, 404 assets, 307-vs-301 redirects, analytics not wired. This
# script makes a bounded set of curl probes against a live site and emits
# a `## Production checks` markdown section for generate-report.sh.
#
# It is OFF by default and only runs when explicitly invoked with --prod.
#
# Usage:
#   bash prod-check.sh --prod https://www.the-shift.ai
#   bash prod-check.sh --prod                # resolve URL from env / autopilot
#   SITE_URL=https://x bash prod-check.sh --prod
#
# URL resolution order: CLI arg → $SITE_URL → `site_url:` / `url:` /
# `production_url:` in the autopilot config (.bsg/AUTOPILOT.yml).
#
# Never crashes on network failure: every probe degrades to a reported
# `⚠️` line. Exit 0 unless the URL cannot be resolved at all.

set -uo pipefail

PROD=0
SITE_URL="${SITE_URL:-}"
while [[ $# -gt 0 ]]; do
  case $1 in
    --prod) PROD=1; shift
            if [[ $# -gt 0 && "$1" != --* ]]; then SITE_URL="$1"; shift; fi ;;
    *) shift ;;
  esac
done

[[ "$PROD" -eq 1 ]] || exit 0

if ! command -v curl >/dev/null 2>&1; then
  echo "## Production checks"
  echo
  echo "_\`curl\` not available — production verification skipped._"
  exit 0
fi

# ----------------------------------------------------- URL resolution

if [[ -z "$SITE_URL" ]]; then
  BSG_PATHS="$(dirname "$0")/../../../scripts/_bsg-paths.sh"
  if [[ -f "$BSG_PATHS" ]]; then
    # shellcheck source=../../../scripts/_bsg-paths.sh disable=SC1091
    source "$BSG_PATHS"
    AUTOPILOT="$(bsg_doc_path autopilot 2>/dev/null || true)"
    if [[ -n "${AUTOPILOT:-}" && -f "$AUTOPILOT" ]]; then
      SITE_URL=$(grep -ioE '^[[:space:]]*(site_url|production_url|url)[[:space:]]*:[[:space:]]*\S+' "$AUTOPILOT" 2>/dev/null \
        | head -1 | sed -E 's/^[^:]*:[[:space:]]*//; s/^["'\'']//; s/["'\'']$//' || true)
    fi
  fi
fi

if [[ -z "$SITE_URL" ]]; then
  echo "## Production checks"
  echo
  echo "_No site URL: pass \`--prod <url>\`, set \`\$SITE_URL\`, or add" \
       "\`site_url:\` to the autopilot config. Production checks skipped._"
  exit 0
fi

# Normalize: strip trailing slash, ensure scheme.
[[ "$SITE_URL" =~ ^https?:// ]] || SITE_URL="https://$SITE_URL"
SITE_URL="${SITE_URL%/}"
HOST="${SITE_URL#*://}"; HOST="${HOST%%/*}"

CURL=(curl -sS --max-time 15 -A "bsg-seo-report/prod-check")

# status <url> — print HTTP code following redirects, or 000 on failure.
status() { "${CURL[@]}" -o /dev/null -w '%{http_code}' -L "$1" 2>/dev/null || echo 000; }
# raw_status <url> — print HTTP code WITHOUT following redirects.
raw_status() { "${CURL[@]}" -o /dev/null -w '%{http_code}' "$1" 2>/dev/null || echo 000; }
# body <url> — print response body (redirects followed), empty on failure.
body() { "${CURL[@]}" -L "$1" 2>/dev/null || true; }

mark() { [[ "$1" == "1" ]] && printf -- '- [x] ' || printf -- '- [ ] '; }

echo "## Production checks"
echo
echo "**Target:** \`$SITE_URL\`  ·  **Probed:** $(date -u +%FT%TZ)"
echo

# ------------------------------------------------------- sitemap.xml
SM_CODE=$(status "$SITE_URL/sitemap.xml")
SM_BODY=$(body "$SITE_URL/sitemap.xml")
SM_COUNT=$(printf '%s' "$SM_BODY" | grep -oE '<loc>' | wc -l | tr -d ' ')
SM_OK=$([[ "$SM_CODE" == "200" ]] && echo 1 || echo 0)
echo "$(mark "$SM_OK")sitemap.xml → HTTP $SM_CODE, $SM_COUNT URLs"

# --------------------------------------------------------- robots.txt
RB_CODE=$(status "$SITE_URL/robots.txt")
RB_BODY=$(body "$SITE_URL/robots.txt")
RB_HASMAP=$(printf '%s' "$RB_BODY" | grep -qiE '^[[:space:]]*Sitemap:' && echo 1 || echo 0)
RB_OK=$([[ "$RB_CODE" == "200" && "$RB_HASMAP" == "1" ]] && echo 1 || echo 0)
echo "$(mark "$RB_OK")robots.txt → HTTP $RB_CODE, \`Sitemap:\` $([[ "$RB_HASMAP" == 1 ]] && echo present || echo MISSING)"

# Internal page sample from the live sitemap (paths only, excl. homepage).
mapfile -t SM_PATHS < <(printf '%s' "$SM_BODY" \
  | grep -oE '<loc>[^<]+</loc>' \
  | sed -E 's|<loc>||; s|</loc>||; s|^https?://[^/]+||; s|/$||' \
  | grep -E '^/.+' | sort -u | head -8)

HOME_HTML=$(body "$SITE_URL/")

abs_canonical() {  # 1 if page has an absolute (http) rel=canonical
  local html="$1"
  printf '%s' "$html" \
    | grep -oiE '<link[^>]*rel="canonical"[^>]*>' | head -1 \
    | grep -qiE 'href="https?://' && echo 1 || echo 0
}

# ---------------------------------------- canonical: home + 2 internal
HOME_CANON=$(abs_canonical "$HOME_HTML")
CANON_DETAIL="home=$([[ "$HOME_CANON" == 1 ]] && echo ok || echo MISSING)"
CANON_OK="$HOME_CANON"
checked=0
for p in "${SM_PATHS[@]:-}"; do
  [[ -z "$p" || "$p" == "/" ]] && continue
  [[ "$checked" -ge 2 ]] && break
  ph=$(abs_canonical "$(body "$SITE_URL$p")")
  CANON_DETAIL="$CANON_DETAIL, ${p}=$([[ "$ph" == 1 ]] && echo ok || echo MISSING)"
  [[ "$ph" == 1 ]] || CANON_OK=0
  checked=$((checked + 1))
done
echo "$(mark "$CANON_OK")Canonical absolute → $CANON_DETAIL"

# ------------------------------------------------- JSON-LD in rendered HTML
JSONLD_TYPES=$(printf '%s' "$HOME_HTML" \
  | grep -oiE '"@type"[[:space:]]*:[[:space:]]*"[^"]+"' \
  | sed -E 's/.*"([^"]+)"$/\1/' | sort -u | paste -sd, - 2>/dev/null)
JSONLD_OK=$([[ -n "$JSONLD_TYPES" ]] && echo 1 || echo 0)
echo "$(mark "$JSONLD_OK")JSON-LD types (homepage) → ${JSONLD_TYPES:-none detected}"

# --------------------------------------------------------- OG image
OG_IMG=$(printf '%s' "$HOME_HTML" \
  | grep -oiE '<meta[^>]*property="og:image"[^>]*>' | head -1 \
  | grep -oiE 'content="[^"]+"' | sed -E 's/content="//I; s/"$//')
if [[ -z "$OG_IMG" ]]; then
  echo "$(mark 0)OG image → no \`og:image\` meta on homepage"
else
  [[ "$OG_IMG" =~ ^https?:// ]] || OG_IMG="$SITE_URL/${OG_IMG#/}"
  OG_CODE=$(status "$OG_IMG")
  OG_OK=$([[ "$OG_CODE" == "200" ]] && echo 1 || echo 0)
  echo "$(mark "$OG_OK")OG image → HTTP $OG_CODE (\`$OG_IMG\`)"
fi

# ----------------------------------------------- analytics (GA4 / Pixel)
GA=$(printf '%s' "$HOME_HTML" | grep -qiE 'googletagmanager\.com/gtag|gtag\(|G-[A-Z0-9]{6,}' && echo 1 || echo 0)
PX=$(printf '%s' "$HOME_HTML" | grep -qiE 'connect\.facebook\.net|fbq\(' && echo 1 || echo 0)
AN_OK=$([[ "$GA" == 1 || "$PX" == 1 ]] && echo 1 || echo 0)
echo "$(mark "$AN_OK")Analytics → GA4 $([[ "$GA" == 1 ]] && echo yes || echo no), Pixel $([[ "$PX" == 1 ]] && echo yes || echo no)"

# ------------------------------------------------- pillar pages all 200
if [[ "${#SM_PATHS[@]}" -eq 0 || -z "${SM_PATHS[0]:-}" ]]; then
  echo "$(mark 0)Pillar pages → no sitemap URLs to sample"
else
  PILLAR_OK=1; PILLAR_DETAIL=""
  for p in "${SM_PATHS[@]}"; do
    [[ -z "$p" ]] && continue
    c=$(status "$SITE_URL$p")
    [[ "$c" == "200" ]] || PILLAR_OK=0
    PILLAR_DETAIL="$PILLAR_DETAIL ${p}=$c"
  done
  echo "$(mark "$PILLAR_OK")Pillar pages (sitemap sample) →${PILLAR_DETAIL}"
fi

# ----------------------------------------- www vs apex → 301 (not 307)
if [[ "$HOST" == www.* ]]; then
  ALT="${SITE_URL/www./}"
else
  SCHEME="${SITE_URL%%://*}"
  ALT="$SCHEME://www.$HOST"
fi
ALT_CODE=$(raw_status "$ALT")
REDIR_OK=$([[ "$ALT_CODE" == "301" || "$ALT_CODE" == "308" ]] && echo 1 || echo 0)
echo "$(mark "$REDIR_OK")www↔apex redirect → \`$ALT\` returns HTTP $ALT_CODE (want 301/308, not 307/302)"

echo
echo "_Production checks are opt-in (\`--prod\`) and probe a live site;" \
     "transient network errors surface as non-200 codes above._"
