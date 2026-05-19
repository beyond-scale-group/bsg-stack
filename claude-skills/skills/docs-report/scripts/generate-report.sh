#!/usr/bin/env bash
# generate-report.sh — compose the full docs health audit.

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)

SNAPSHOT=$(mktemp -t docs-snap.XXXXXX.json)
trap 'rm -f "$SNAPSHOT"' EXIT

bash "$SCRIPT_DIR/collect.sh" > "$SNAPSHOT"

LINKS=$(bash "$SCRIPT_DIR/links.sh"    --snapshot "$SNAPSHOT")
COMMANDS=$(bash "$SCRIPT_DIR/commands.sh" --snapshot "$SNAPSHOT")
CHANGELOG=$(bash "$SCRIPT_DIR/changelog.sh" --snapshot "$SNAPSHOT")
BSG=$(bash "$SCRIPT_DIR/bsg-docs.sh"   --snapshot "$SNAPSHOT")

DATE=$(date +%F)
REPO=$(jq -r '.repoRoot' "$SNAPSHOT" | xargs -I{} basename {})

cat <<EOF
<!-- fingerprint: ${TICK_FINGERPRINT:-none} -->
# Docs Health — $DATE

**Repository:** \`$REPO\`
**Generated:** $(jq -r '.generatedAt' "$SNAPSHOT")
**Tracked markdown files:** $(jq -r '.markdownFiles | length' "$SNAPSHOT")

---

## Broken links

$(jq -r '
  .summary as $s
  | "**Summary:** \($s.brokenLinks) broken link(s) in tracked markdown."
' <<<"$LINKS")

$(jq -r '
  if (.brokenLinks | length) == 0 then "_No broken links._"
  else
    (
      "| Source | Target |",
      "|--------|--------|",
      (.brokenLinks | sort_by(.source) | .[0:25][] | "| \(.source) | \(.target) |")
    )
  end
' <<<"$LINKS")

---

## Stale README commands

$(jq -r '
  .summary as $s
  | "**Summary:** \($s.staleCommands) command(s) referenced in READMEs but not present in package.json / Makefile."
' <<<"$COMMANDS")

$(jq -r '
  if (.staleCommands | length) == 0 then "_No stale commands._"
  else
    (
      "| README | Tool | Command |",
      "|--------|------|---------|",
      (.staleCommands | .[0:25][] | "| \(.readme) | \(.tool) | \(.command) |")
    )
  end
' <<<"$COMMANDS")

---

## CHANGELOG gaps

$(jq -r '
  if .changelogFound == false then "_No CHANGELOG.md found at the repo root or any subproject._"
  else
    "**Summary:** \(.summary.loggedVersions) version(s) logged, \(.summary.missingTags) tag(s) missing from \(.changelogPath)."
  end
' <<<"$CHANGELOG")

$(jq -r '
  if (.missingTags | length) == 0 then "_No missing tags._"
  else
    "### Tags missing from CHANGELOG\n\n" +
    ([.missingTags[] | "- \(.)"] | join("\n"))
  end
' <<<"$CHANGELOG")

---

## .bsg/ doc freshness

$(jq -r '
  .summary as $s
  | "**Summary:** \($s.deadReferences) dead reference(s), \($s.staleSinceBump) doc(s) unedited since latest tag."
' <<<"$BSG")

$(jq -r '
  if (.deadReferences | length) == 0 then "_No dead references in .bsg/ flat docs._"
  else
    (
      "### Dead references",
      "",
      "| Doc | Reference |",
      "|-----|-----------|",
      (.deadReferences | .[0:25][] | "| \(.doc) | \(.reference) |")
    )
  end
' <<<"$BSG")

$(jq -r '
  if (.staleSinceBump | length) == 0 then ""
  else
    "\n### Unedited since latest release\n\n" +
    ([.staleSinceBump[] | "- \(.doc) — \(.reason)"] | join("\n"))
  end
' <<<"$BSG")

EOF
