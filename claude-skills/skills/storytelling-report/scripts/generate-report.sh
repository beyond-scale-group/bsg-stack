#!/usr/bin/env bash
# generate-report.sh — compose the full storytelling audit.

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)

SNAPSHOT=$(mktemp -t brand-snap.XXXXXX.json)
trap 'rm -f "$SNAPSHOT"' EXIT

bash "$SCRIPT_DIR/collect.sh" > "$SNAPSHOT"

VOICE=$(bash "$SCRIPT_DIR/voice.sh"          --snapshot "$SNAPSHOT")
ALIGNMENT=$(bash "$SCRIPT_DIR/alignment.sh"  --snapshot "$SNAPSHOT")
TP=$(bash "$SCRIPT_DIR/talking-points.sh"    --snapshot "$SNAPSHOT")

DATE=$(date +%F)
REPO=$(jq -r '.repoRoot' "$SNAPSHOT" | xargs -I{} basename {})
NARRATIVE_FOUND=$(jq -r '.narrative.found' "$SNAPSHOT")

cat <<EOF
# Brand Audit — $DATE

**Repository:** \`$REPO\`
**Generated:** $(jq -r '.generatedAt' "$SNAPSHOT")
**Narrative bible:** $(jq -r 'if .narrative.found then ("found at `" + .narrative.path + "`") else "missing" end' "$SNAPSHOT")

---

## Narrative Bible Summary

$(jq -r '
  if .narrative.found == false then
    "_No \u0060brand/NARRATIVE.md\u0060 found. See \u0060references/narrative.md\u0060 for the schema and bootstrap with the team before the next tick._"
  else
    .narrative as $n
    | "- **Tone target:** \($n.toneTarget)\n" +
      "- **Key messages:** \($n.keyMessages | length)\n" +
      "- **Value-prop bullets:** \($n.positioning.differentiators | length)\n" +
      "- **Feature anchors:** \($n.positioning.featureAnchors | length)\n" +
      "- **Category / audience:** \($n.positioning.category // "(unset)") / \($n.positioning.audience // "(unset)")"
  end
' "$SNAPSHOT")

---

## Voice Consistency

$(jq -r '
  .summary as $s
  | "**Summary:** \($s.assetsScored) assets scored; target = \($s.targetTone), mean = \($s.meanScore // "n/a"), σ = \($s.stddev // "n/a"), drift = \($s.driftCount)"
' <<<"$VOICE")

$(jq -r '
  if (.perAsset | length) == 0 then "_No assets to score._"
  else
    "| Asset | Tone | Avg sentence | Passive ratio | Jargon density | Flesch |\n|------|------|--------------|---------------|----------------|--------|\n" +
    ([.perAsset[] | "| \(.file) | \(.toneScore) | \(.sentenceAvg) | \(.passiveRatio) | \(.jargonDensity) | \(.fleschEase) |"] | join("\n"))
  end
' <<<"$VOICE")

$(jq -r '
  if (.drift | length) == 0 then ""
  else
    "\n\n### Drift (silence-breaker)\n\n" +
    "| Asset | Tone | Deviation | Direction |\n|------|------|-----------|-----------|\n" +
    ([.drift[] | "| \(.file) | \(.toneScore) | \(.deviation) | \(.direction) |"] | join("\n"))
  end
' <<<"$VOICE")

---

## Key Message Alignment

$(jq -r '
  if (.summary.messagesChecked // 0) == 0 then
    "_No key messages declared in the narrative bible._"
  else
    .summary as $s
    | "**Summary:** \($s.messagesChecked) messages checked — \($s.messagesInREADME) present in README, \($s.missingInREADME) missing from README"
  end
' <<<"$ALIGNMENT")

$(jq -r '
  if (.coverage | length) == 0 then ""
  else
    "\n\n| Message | In README | Other assets |\n|---------|-----------|--------------|\n" +
    ([.coverage[] | "| \(.message) | \(if .inREADME then "yes" else "**no**" end) | \(.assetHits | length) |"] | join("\n"))
  end
' <<<"$ALIGNMENT")

$(jq -r '
  if (.stalePositioning | length) == 0 then ""
  else
    "\n\n### Stale positioning (silence-breaker)\n\n" +
    ([.stalePositioning[] | "- **\(.anchor)** — \(.reason)"] | join("\n"))
  end
' <<<"$ALIGNMENT")

---

## Talking Points for Releases

$(jq -r '
  if (.existing | length) == 0 then "_No talking-point files yet under \u0060brand/talking-points/\u0060._"
  else
    "**Existing:** \(.existing | length) file(s) — " +
    ([.existing[] | "\(.release) (\(.status))"] | join(", "))
  end
' <<<"$TP")

$(jq -r '
  if (.plan | length) == 0 then "\n_No unnarrated releases._"
  else
    "\n\n### Unnarrated releases (silence-breaker)\n\n" +
    "_Run the skill with \u0060--write\u0060 to generate stubs._\n\n" +
    ([.plan[] | "- \u0060\(.path)\u0060 — \(.release) \(.title)"] | join("\n"))
  end
' <<<"$TP")

EOF
