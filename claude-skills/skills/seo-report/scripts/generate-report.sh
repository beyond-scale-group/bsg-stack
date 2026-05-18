#!/usr/bin/env bash
# generate-report.sh — compose the full SEO audit report.
#
# Usage:
#   generate-report.sh                 source-at-rest audit only
#   generate-report.sh --prod          + production checks, URL resolved
#                                       from SEO_SITE_URL / SITE_URL /
#                                       AUTOPILOT.yml `site_url:`
#   generate-report.sh --prod <url>    + production checks against <url>

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)

# ---------------------------------------------------------- arg parsing

PROD=0
PROD_URL=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --prod)
      PROD=1
      # Optional inline URL: `--prod https://...`
      if [[ ${2:-} =~ ^https?:// ]]; then
        PROD_URL="$2"
        shift
      fi
      ;;
    *)
      echo "generate-report.sh: unknown argument '$1'" >&2
      exit 2
      ;;
  esac
  shift
done

# Resolve the production URL: explicit arg > env > AUTOPILOT.yml.
if [[ "$PROD" -eq 1 && -z "$PROD_URL" ]]; then
  PROD_URL="${SEO_SITE_URL:-${SITE_URL:-}}"
fi
if [[ "$PROD" -eq 1 && -z "$PROD_URL" ]]; then
  REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
  BSG_PATHS="$SCRIPT_DIR/../../../scripts/_bsg-paths.sh"
  if [[ -f "$BSG_PATHS" ]]; then
    # shellcheck source=../../../scripts/_bsg-paths.sh disable=SC1091
    source "$BSG_PATHS"
    AUTOPILOT="$REPO_ROOT/$BSG_AUTOPILOT_FILE"
    if [[ -f "$AUTOPILOT" ]]; then
      PROD_URL=$( { grep -oE '^[[:space:]]*site_url:[[:space:]]*\S+' "$AUTOPILOT" 2>/dev/null || true; } \
        | head -1 | sed -E 's/^[[:space:]]*site_url:[[:space:]]*//; s/^["'\'']//; s/["'\'']$//' )
    fi
  fi
fi

SNAPSHOT=$(mktemp -t seo-snap.XXXXXX.json)
trap 'rm -f "$SNAPSHOT"' EXIT

bash "$SCRIPT_DIR/collect.sh" > "$SNAPSHOT"

META=$(bash "$SCRIPT_DIR/meta.sh"      --snapshot "$SNAPSHOT")
LINKS=$(bash "$SCRIPT_DIR/links.sh"    --snapshot "$SNAPSHOT")
CONTENT=$(bash "$SCRIPT_DIR/content.sh" --snapshot "$SNAPSHOT")
TECH=$(bash "$SCRIPT_DIR/technical.sh" --snapshot "$SNAPSHOT")

DATE=$(date +%F)
REPO=$(jq -r '.repoRoot' "$SNAPSHOT" | xargs -I{} basename {})
TOTAL_PAGES=$(jq '.pages | length' "$SNAPSHOT")

cat <<EOF
<!-- fingerprint: ${TICK_FINGERPRINT:-none} -->
# SEO Audit — $DATE

**Repository:** \`$REPO\`
**Generated:** $(jq -r '.generatedAt' "$SNAPSHOT")
**Pages detected:** $TOTAL_PAGES

---

## Meta Tag Coverage

$(jq -r '
  .summary as $s
  | "**Summary:** \($s.pagesScanned) pages scanned — \($s.missingTitle) missing title, \($s.missingDescription) missing description, \($s.missingCanonical) missing canonical; OG full=\($s.ogCoverage.full) partial=\($s.ogCoverage.partial) none=\($s.ogCoverage.none)"
' <<<"$META")

$(jq -r '
  if (.missingTitle | length) == 0 and (.missingDescription | length) == 0 then "_No title / description gaps._"
  else
    "### Gaps\n\n" +
    (if (.missingTitle | length) == 0 then "" else
      "**Missing title:**\n" + ([.missingTitle[] | "- \(.page)"] | join("\n")) + "\n\n"
    end) +
    (if (.missingDescription | length) == 0 then "" else
      "**Missing description:**\n" + ([.missingDescription[] | "- \(.page)"] | join("\n"))
    end)
  end
' <<<"$META")

---

## Internal Link Health

$(jq -r '
  .summary as $s
  | "**Summary:** \($s.totalPages) pages — \($s.orphanCount) orphan, \($s.brokenCount) broken, avg inbound: \($s.avgInboundLinks)"
' <<<"$LINKS")

$(jq -r '
  if (.orphanPages | length) == 0 then ""
  else
    "\n### Orphan pages\n\n" + ([.orphanPages[] | "- \(.page)"] | join("\n"))
  end
' <<<"$LINKS")

$(jq -r '
  if (.brokenLinks | length) == 0 then ""
  else
    "\n\n### Broken links\n\n" + ([.brokenLinks[] | "- \(.from) → \(.target)"] | join("\n"))
  end
' <<<"$LINKS")

---

## Content Coverage

$(jq -r '
  if .keywordsFound == false then
    "_No \u0060seo/KEYWORDS.md\u0060 found. Create one to enable keyword coverage analysis._"
  else
    .summary as $s
    | "**Summary:** \($s.total) keywords — \($s.covered) covered, \($s.uncovered) uncovered\n\n" +
      (
        "| Keyword | Status | Page |\n|---------|--------|------|\n" +
        ([.coverage[] | "| \(.keyword) | \(.status) | \(.page // "-") |"] | join("\n"))
      )
  end
' <<<"$CONTENT")

---

## Technical SEO

$(jq -r '
  "| Check | Status |\n|-------|--------|\n" +
  "| sitemap.xml | \(if .sitemapFound then "Present at \u0060\(.sitemapPath)\u0060 (\(.sitemapUrlCount) URLs)" else "**Missing**" end) |\n" +
  "| robots.txt | \(if .robotsFound then "Present at \u0060\(.robotsPath)\u0060" else "**Missing**" end) |\n" +
  "| Canonical hosts | \(if .canonicalInconsistent then "**Inconsistent** (\(.canonicalHosts | length) distinct hosts)" else (if (.canonicalHosts | length) == 0 then "n/a" else "consistent (\(.canonicalHosts[0].host))" end) end) |\n" +
  "| Robots blanket disallow | \(if .robotsBlanketDisallow then "**YES — indexing blocked!**" else "no" end) |"
' <<<"$TECH")

$(jq -r '
  if (.pagesNotInSitemap | length) == 0 then ""
  else
    "\n### Pages not in sitemap\n\n" + ([.pagesNotInSitemap[] | "- \(.page)"] | join("\n"))
  end
' <<<"$TECH")

EOF

if [[ "$PROD" -eq 1 ]]; then
  echo
  echo "---"
  echo
  # Non-fatal: a failing prod-checks.sh must not abort the audit.
  bash "$SCRIPT_DIR/prod-checks.sh" "$PROD_URL" || \
    echo "_Production checks failed to run (see logs); source-at-rest audit above is unaffected._"
fi
