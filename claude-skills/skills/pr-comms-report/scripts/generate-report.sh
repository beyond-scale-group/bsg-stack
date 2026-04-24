#!/usr/bin/env bash
# generate-report.sh — compose the full PR / comms audit.

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)

SNAPSHOT=$(mktemp -t comms-snap.XXXXXX.json)
trap 'rm -f "$SNAPSHOT"' EXIT

bash "$SCRIPT_DIR/collect.sh" > "$SNAPSHOT"

EVENTS=$(bash "$SCRIPT_DIR/events.sh"    --snapshot "$SNAPSHOT")
KIT=$(bash "$SCRIPT_DIR/press-kit.sh"    --snapshot "$SNAPSHOT")
DRAFT=$(bash "$SCRIPT_DIR/draft.sh"      --snapshot "$SNAPSHOT")

DATE=$(date +%F)
REPO=$(jq -r '.repoRoot' "$SNAPSHOT" | xargs -I{} basename {})
VIS=$(jq -r '.visibility' "$SNAPSHOT")

cat <<EOF
<!-- fingerprint: ${TICK_FINGERPRINT:-none} -->
# PR / Comms Events — $DATE

**Repository:** \`$REPO\` (visibility: $VIS)
**Generated:** $(jq -r '.generatedAt' "$SNAPSHOT")
**Releases tracked:** $(jq '.releases | length' "$SNAPSHOT")
**Milestones tracked:** $(jq '.milestones | length' "$SNAPSHOT")
**Contributors:** $(jq '.contributors' "$SNAPSHOT") — **PRs merged (total):** $(jq '.prsMerged' "$SNAPSHOT")

---

## Newsworthy Events

$(jq -r '
  .summary as $s
  | "**Summary:** \($s.total) events — \($s.unannouncedMajor) unannounced major/minor, \($s.unannouncedMilestone) unannounced milestone, \($s.securityAdvisories) security advisories, \($s.communityMilestones) community milestones (\($s.patchesSkipped) patches skipped)"
' <<<"$EVENTS")

$(jq -r '
  if (.unannouncedMajor | length) == 0 then ""
  else
    "\n### Unannounced releases (silence-breaker)\n\n" +
    "| Release | Type | Published | Priority |\n|---------|------|-----------|----------|\n" +
    ([.unannouncedMajor[] | "| \(.release) | \(.type) | \(.publishedAt // "n/a") | \(.priority) |"] | join("\n"))
  end
' <<<"$EVENTS")

$(jq -r '
  if (.unannouncedMilestone | length) == 0 then ""
  else
    "\n\n### Unannounced milestones (silence-breaker)\n\n" +
    ([.unannouncedMilestone[] | "- **\(.milestone)** (#\(.number), closed \(.closedAt // "n/a"))"] | join("\n"))
  end
' <<<"$EVENTS")

$(jq -r '
  if (.securityAdvisories | length) == 0 then ""
  else
    "\n\n### Security advisories (silence-breaker — HUMAN JUDGEMENT REQUIRED)\n\n" +
    "_The @pr-comms agent does NOT draft security responses. Surfacing only._\n\n" +
    ([.securityAdvisories[] | "- \(.ghsaId // "n/a") / \(.cveId // "n/a") — \(.severity // "?") — \(.summary // "")"] | join("\n"))
  end
' <<<"$EVENTS")

$(jq -r '
  if (.communityMilestones | length) == 0 then ""
  else
    "\n\n### Community milestones\n\n" +
    ([.communityMilestones[] | "- \(.kind) crossed \(.count) (current: \(.hitAt))"] | join("\n"))
  end
' <<<"$EVENTS")

---

## Press Kit Health

$(jq -r '
  if .present == false then
    "_No \u0060comms/press-kit/\u0060 directory. See \u0060references/press-kit.md\u0060 for the recommended structure._"
  else
    "**Directory:** \u0060\(.directory)\u0060; **assets:** \(.assets | length), **stale:** \(.staleAssets | length), **missing recommended:** \(.missingRecommended | length)"
  end
' <<<"$KIT")

$(jq -r '
  if .present == false or (.assets | length) == 0 then ""
  else
    "\n\n| File | Last updated | Age (days) | Stale? |\n|------|--------------|-----------:|--------|\n" +
    ([.assets[] | "| \(.file) | \(.lastUpdated) | \(.ageDays) | \(if .stale then "**yes**" else "no" end) |"] | join("\n"))
  end
' <<<"$KIT")

$(jq -r '
  if (.missingRecommended | length) == 0 then ""
  else
    "\n\n**Missing recommended files:** " + ([.missingRecommended[] | "\u0060\(.)\u0060"] | join(", "))
  end
' <<<"$KIT")

---

## Draft Press Releases

$(jq -r '
  if (.plan | length) == 0 then "_No unannounced releases require drafting._"
  else
    "### Plan (not yet written to disk)\n\n" +
    "_Run the skill with \u0060--write\u0060 to materialize these drafts." +
    (if .confidential then " Drafts will be marked CONFIDENTIAL." else "" end) +
    "_\n\n" +
    ([.plan[] | "- \u0060\(.path)\u0060 — \(.release) \(.title) (priority \(.priority))"] | join("\n"))
  end
' <<<"$DRAFT")

$(jq -r '
  if (.existing | length) == 0 then ""
  else
    "\n\n### Existing drafts\n\n" +
    ([.existing[] | "- \u0060\(.file)\u0060 — \(.release) (status: \(.status))"] | join("\n"))
  end
' <<<"$DRAFT")

EOF
