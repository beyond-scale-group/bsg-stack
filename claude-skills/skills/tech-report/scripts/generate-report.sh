#!/usr/bin/env bash
# generate-report.sh — compose the full tech health report.

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)

SNAPSHOT=$(mktemp -t tech-snap.XXXXXX.json)
trap 'rm -f "$SNAPSHOT"' EXIT

bash "$SCRIPT_DIR/collect.sh" > "$SNAPSHOT"

DEPS=$(bash "$SCRIPT_DIR/deps.sh"    --snapshot "$SNAPSHOT")
QUALITY=$(bash "$SCRIPT_DIR/quality.sh" --snapshot "$SNAPSHOT")
DEBT=$(bash "$SCRIPT_DIR/debt.sh"    --snapshot "$SNAPSHOT")
ADR=$(bash "$SCRIPT_DIR/adr.sh"      --snapshot "$SNAPSHOT")

DATE=$(date +%F)
REPO=$(jq -r '.repoRoot' "$SNAPSHOT" | xargs -I{} basename {})

cat <<EOF
# Tech Health — $DATE

**Repository:** \`$REPO\`
**Generated:** $(jq -r '.generatedAt' "$SNAPSHOT")
**Ecosystems:** $(jq -r '.ecosystems | join(", ") // "(none)"' "$SNAPSHOT")

---

## Dependency Health

$(jq -r '
  .summary as $s
  | "**Summary:** \($s.total) tracked — \($s.upToDate) up-to-date, \($s.patchBehind) patch-behind, \($s.minorBehind) minor-behind, \($s.majorBehind) major-behind"
' <<<"$DEPS")

$(jq -r '
  if (.majorBehind | length) == 0 then "_No major-version-behind dependencies._"
  else
    (
      "### Major-behind (silence-breaker)",
      "",
      "| Package | Current | Latest | Majors behind | CVE alert? |",
      "|---------|---------|--------|---------------|------------|",
      (.majorBehind[] | "| \(.package) | \(.current) | \(.latest) | \(.majorsBehind) | \(if .hasAlert then "yes" else "-" end) |")
    )
  end
' <<<"$DEPS")

---

## Code Quality

$(jq -r '
  .summary as $s
  | "**Summary:** \($s.filesAnalyzed) source files analyzed — \($s.oversized) oversized (> 500 LOC), \($s.functionDense) function-dense (> 20), \($s.circularDeps) circular-import cycles"
' <<<"$QUALITY")

$(jq -r '
  if (.oversizedFiles | length) == 0 then "_No oversized files._"
  else
    (
      "### Largest files",
      "",
      "| File | Lines | Functions |",
      "|------|-------|-----------|",
      (.oversizedFiles | sort_by(-.lines) | .[0:10][] | "| \(.file) | \(.lines) | \(.functions) |")
    )
  end
' <<<"$QUALITY")

$(jq -r '
  if (.circularDeps | length) == 0 then ""
  else
    "\n### Circular imports\n\n" +
    ([.circularDeps[] | "- \(.a)  ⇄  \(.b)"] | join("\n"))
  end
' <<<"$QUALITY")

---

## Tech Debt Inventory

$(jq -r '
  .summary as $s
  | "**Summary:** \($s.total) markers — TODO: \($s.todo), FIXME: \($s.fixme), HACK: \($s.hack); oldest: \($s.oldestDate // "n/a")"
' <<<"$DEBT")

$(jq -r '
  "**Debt score:** \(.debtScore) " +
  (if .previousDebtScore == null then "(no previous)"
   elif .debtScoreDelta == null then ""
   else "(previous: \(.previousDebtScore), delta: \(if .debtScoreDelta >= 0 then "+" else "" end)\(.debtScoreDelta))"
   end)
' <<<"$DEBT")

$(jq -r '
  if (.staleTodos | length) == 0 then "_No stale TODOs (> 90 days)._"
  else
    (
      "### Stale items (> 90 days)",
      "",
      "| File | Line | Kind | Age (days) | Text |",
      "|------|------|------|-----------:|------|",
      (.staleTodos | sort_by(-.age) | .[0:15][] | "| \(.file) | \(.line) | \(.kind) | \(.age) | \(.text) |")
    )
  end
' <<<"$DEBT")

---

## Architecture Decision Records

$(jq -r '
  if .dir == null then
    "_No ADR directory found. Consider creating \u0060adr/0001-start.md\u0060 to document the first architectural decision of this repo._"
  else
    "**ADR directory:** \u0060\(.dir)\u0060 (\(.index | length) entry/entries)\n\n" +
    (if (.index | length) == 0 then "_Directory is empty._"
     else
       ([.index | sort_by(.id) | .[] | "- \(.id) — \(.title) (\(.status // "unknown"))"] | join("\n"))
     end)
  end
' <<<"$ADR")

$(jq -r '
  if (.undocumentedDecisions | length) == 0 then ""
  else
    "\n### Undocumented decisions (silence-breaker)\n\n" +
    ([.undocumentedDecisions[] | "- New top-level dep \u0060\(.dependency)\u0060 (\(.ecosystem)) added without a matching ADR"] | join("\n"))
  end
' <<<"$ADR")

EOF
