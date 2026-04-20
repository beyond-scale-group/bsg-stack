#!/usr/bin/env bash
# generate-report.sh — compose a full security audit report.
#
# Collects once, runs every reporter, composes a markdown document on
# stdout. Intended as the single invocation behind `@security tick`.

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)

SNAPSHOT=$(mktemp -t security-snap.XXXXXX.json)
trap 'rm -f "$SNAPSHOT"' EXIT

bash "$SCRIPT_DIR/collect.sh" > "$SNAPSHOT"

DEPS=$(bash "$SCRIPT_DIR/deps.sh"    --snapshot "$SNAPSHOT")
SECRETS=$(bash "$SCRIPT_DIR/secrets.sh" --snapshot "$SNAPSHOT")
HEADERS=$(bash "$SCRIPT_DIR/headers.sh" --snapshot "$SNAPSHOT")

DATE=$(date +%F)
REPO=$(jq -r '.repoRoot' "$SNAPSHOT" | xargs -I{} basename {})

cat <<EOF
# Security Audit — $DATE

**Repository:** \`$REPO\`
**Generated:** $(jq -r '.generatedAt' "$SNAPSHOT")
**Ecosystems detected:** $(jq -r '.ecosystems | join(", ") // "(none)"' "$SNAPSHOT")

---

## Dependency Vulnerabilities

$(jq -r '
  .summary as $s
  | "**Summary:** \($s.total) total — \($s.critical) critical, \($s.high) high, \($s.moderate) moderate, \($s.low) low"
' <<<"$DEPS")

$(jq -r '
  if (.findings | length) == 0 then
    "_No vulnerabilities reported._"
  else
    (
      "| Package | Version | Severity | CVE | Fix available |",
      "|---------|---------|----------|-----|----------------|",
      (.findings[] | "| \(.package) | \(.version) | \(.severity) | \(.cve // "-") | \(.fixedIn // "no") |")
    )
  end
' <<<"$DEPS")

$(jq -r '
  if (.noFix | length) == 0 then
    ""
  else
    "\n**No-fix-available (critical/high):** " + ([.noFix[] | .package] | join(", "))
  end
' <<<"$DEPS")

---

## Secret Scan

$(jq -r '
  .summary as $s
  | "**Summary:** \($s.findings) finding(s), \($s.trackedEnvFiles) tracked .env file(s), \($s.scannedFiles) file(s) scanned"
' <<<"$SECRETS")

$(jq -r '
  if (.findings | length) == 0 then
    "_No secret patterns detected in tracked files._"
  else
    (
      "| File | Line | Kind | Match |",
      "|------|------|------|-------|",
      (.findings[] | "| \(.file) | \(.line) | \(.kind) | " + "\u0060" + .match + "\u0060" + " |")
    )
  end
' <<<"$SECRETS")

$(jq -r '
  if (.trackedEnvFiles | length) == 0 then
    ""
  else
    "\n**Tracked env files (silence-breaker):** " + ([.trackedEnvFiles[]] | join(", "))
  end
' <<<"$SECRETS")

---

## Configuration Hardening

$(jq -r '
  if .applicable == false then
    "_Not applicable — this repo does not serve HTTP._"
  else
    "**Server kind detected:** \(.serverKind)\n\n" +
    (
      if (.missing | length) == 0 then "_All required security headers are present._"
      else
        "### Missing headers\n\n" +
        "| Header | Severity |\n|--------|----------|\n" +
        ([.missing[] | "| \(.header) | \(.severity) |"] | join("\n"))
      end
    ) +
    (
      if (.weak | length) == 0 then ""
      else
        "\n\n### Weak / permissive headers\n\n" +
        "| Header | Severity | Reason |\n|--------|----------|--------|\n" +
        ([.weak[] | "| \(.header) | \(.severity) | \(.reason) |"] | join("\n"))
      end
    )
  end
' <<<"$HEADERS")

---

## OWASP Top-10 Quick Check

_Populated by the \`@security\` agent based on this snapshot. See
\`references/owasp.md\` for the heuristic catalog. Category-by-category
analysis is LLM-driven; the scripts only provide the raw signals
above._

EOF
