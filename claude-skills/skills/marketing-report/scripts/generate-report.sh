#!/usr/bin/env bash
# generate-report.sh — compose the full marketing audit.

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)

SNAPSHOT=$(mktemp -t mkt-snap.XXXXXX.json)
trap 'rm -f "$SNAPSHOT"' EXIT

bash "$SCRIPT_DIR/collect.sh" > "$SNAPSHOT"

CALENDAR=$(bash "$SCRIPT_DIR/calendar.sh"  --snapshot "$SNAPSHOT")
ALIGNMENT=$(bash "$SCRIPT_DIR/alignment.sh" --snapshot "$SNAPSHOT")
BRIEF=$(bash "$SCRIPT_DIR/brief.sh"        --snapshot "$SNAPSHOT")

DATE=$(date +%F)
REPO=$(jq -r '.repoRoot' "$SNAPSHOT" | xargs -I{} basename {})

cat <<EOF
<!-- fingerprint: ${TICK_FINGERPRINT:-none} -->
# Marketing Audit — $DATE

**Repository:** \`$REPO\`
**Generated:** $(jq -r '.generatedAt' "$SNAPSHOT")
**Releases tracked:** $(jq '.releases | length' "$SNAPSHOT")
**Milestones tracked:** $(jq '.milestones | length' "$SNAPSHOT")

---

## Content Calendar

$(jq -r '
  if .calendarFound == false then
    "_No \u0060marketing/CALENDAR.md\u0060 found. Create one using the template in \u0060references/calendar.md\u0060 to enable calendar auditing._"
  else
    .summary as $s
    | "**Summary:** \($s.total) items — \($s.overdue) overdue, \($s.today) today, \($s.upcoming) upcoming, \($s.completed) completed"
  end
' <<<"$CALENDAR")

$(jq -r '
  if .calendarFound == false or (.overdueItems | length) == 0 then ""
  else
    "\n### Overdue items (silence-breaker)\n\n" +
    "| Date | Title | Days late |\n|------|-------|-----------|\n" +
    ([.overdueItems[] | "| \(.date) | \(.title) | \(.daysLate) |"] | join("\n"))
  end
' <<<"$CALENDAR")

$(jq -r '
  if .calendarFound == false or (.upcomingItems | length) == 0 then ""
  else
    "\n\n### Upcoming\n\n" +
    ([.upcomingItems[0:5] | .[] | "- \(.date) — \(.title) (in \(.daysUntil) days)"] | join("\n"))
  end
' <<<"$CALENDAR")

---

## Feature-Marketing Alignment

$(jq -r '
  .summary as $s
  | "**Summary:** \($s.shippedCount) shipped, \($s.marketedCount) marketing files scanned — \($s.aligned) aligned, \($s.unmarketed) unmarketed shipped features, \($s.unshipped) claimed-but-unshipped"
' <<<"$ALIGNMENT")

$(jq -r '
  if (.unmarketed | length) == 0 then ""
  else
    "\n### Unmarketed shipped features (silence-breaker)\n\n" +
    "| Release | Feature | Released at |\n|---------|---------|-------------|\n" +
    ([.unmarketed[] | "| \(.release) | \(.feature) | \(.releasedAt // "n/a") |"] | join("\n"))
  end
' <<<"$ALIGNMENT")

$(jq -r '
  if (.unshipped | length) == 0 then ""
  else
    "\n\n### Claimed but not (yet) shipped\n\n" +
    ([.unshipped[] | "- \u0060\(.claim)\u0060 (found in \(.foundIn | join(", ")))"] | join("\n"))
  end
' <<<"$ALIGNMENT")

---

## Campaign Briefs

$(jq -r '
  if (.plan | length) == 0 then "_No unmarketed releases waiting for a brief._"
  else
    "### Plan (not yet written to disk)\n\n" +
    "_Run the skill with \u0060--write\u0060 to generate these stubs._\n\n" +
    ([.plan[] | "- \u0060\(.path)\u0060 — \(.release) \(.feature)"] | join("\n"))
  end
' <<<"$BRIEF")

$(jq -r '
  if (.staleBriefs | length) == 0 then ""
  else
    "\n\n### Stale briefs (silence-breaker, > 14 days in draft)\n\n" +
    ([.staleBriefs[] | "- \u0060\(.path)\u0060 — \(.release), \(.age) days old (status: \(.status))"] | join("\n"))
  end
' <<<"$BRIEF")

EOF
