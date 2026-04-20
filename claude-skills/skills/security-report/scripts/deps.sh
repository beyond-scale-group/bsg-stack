#!/usr/bin/env bash
# deps.sh — dependency vulnerability reporter.
#
# Reads the security snapshot (from collect.sh or --snapshot) and emits
# a normalized JSON summary of dependency vulnerabilities across every
# detected ecosystem, plus a `noFix[]` list of critical findings with no
# available fix.

set -euo pipefail

SNAPSHOT=""
while [[ $# -gt 0 ]]; do
  case $1 in
    --snapshot) SNAPSHOT="$2"; shift 2 ;;
    *) shift ;;
  esac
done

if [[ -z "$SNAPSHOT" ]]; then
  SNAPSHOT=$(mktemp -t security-snap.XXXXXX.json)
  trap 'rm -f "$SNAPSHOT"' EXIT
  SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
  bash "$SCRIPT_DIR/collect.sh" > "$SNAPSHOT"
fi

# Transform npm audit output into a flat findings[] array.
NPM_FINDINGS=$(jq '
  (.deps.npmAudit.vulnerabilities // {}) as $v
  | [ $v | to_entries[] |
      .value as $entry |
      {
        package: .key,
        version: ($entry.range // "unknown"),
        severity: ($entry.severity // "unknown"),
        cve: ($entry.via | if type=="array" then (.[0].url // .[0] // null) else null end),
        fixedIn: ($entry.fixAvailable | if type=="object" then .version else null end),
        source: "npm audit"
      }
    ]
' "$SNAPSHOT")

# Transform pip-audit output.
PIP_FINDINGS=$(jq '
  (.deps.pipAudit.dependencies // []) as $deps
  | [ $deps[] as $d
      | ($d.vulns // []) as $vulns
      | $vulns[] |
      {
        package: $d.name,
        version: $d.version,
        severity: (.aliases // [] | map(select(startswith("CVE-"))) | first // .severity // "unknown"),
        cve: (.id // (.aliases // [] | map(select(startswith("CVE-"))) | first)),
        fixedIn: ((.fix_versions // [])[0] // null),
        source: "pip-audit"
      }
    ]
' "$SNAPSHOT")

# Transform Dependabot alerts.
DEPENDABOT_FINDINGS=$(jq '
  (.deps.dependabotAlerts // []) as $alerts
  | [ $alerts[]
      | select(.state == "open" or .state == null)
      | {
        package: (.security_vulnerability.package.name // .dependency.package.name // "unknown"),
        version: (.dependency.manifest_path // "unknown"),
        severity: (.security_vulnerability.severity // "unknown"),
        cve: (.security_advisory.cve_id // .security_advisory.ghsa_id // null),
        fixedIn: (.security_vulnerability.first_patched_version.identifier // null),
        source: "dependabot"
      }
    ]
' "$SNAPSHOT")

# Merge and deduplicate on (package, cve).
FINDINGS=$(jq -n \
  --argjson a "$NPM_FINDINGS" \
  --argjson b "$PIP_FINDINGS" \
  --argjson c "$DEPENDABOT_FINDINGS" \
  '($a + $b + $c) | unique_by([.package, .cve])')

SUMMARY=$(jq -n --argjson f "$FINDINGS" '
  {
    total: ($f | length),
    critical: ($f | map(select(.severity == "critical")) | length),
    high:     ($f | map(select(.severity == "high"))     | length),
    moderate: ($f | map(select(.severity == "moderate")) | length),
    low:      ($f | map(select(.severity == "low"))      | length)
  }')

NO_FIX=$(jq -n --argjson f "$FINDINGS" '
  $f | map(select((.severity == "critical" or .severity == "high") and (.fixedIn == null or .fixedIn == "")))')

jq -n \
  --argjson summary "$SUMMARY" \
  --argjson findings "$FINDINGS" \
  --argjson noFix "$NO_FIX" \
  '{ summary: $summary, findings: $findings, noFix: $noFix }'
