#!/usr/bin/env bash
# deps.sh — per-dependency upgrade-gap analysis.

set -euo pipefail

SNAPSHOT=""
while [[ $# -gt 0 ]]; do
  case $1 in
    --snapshot) SNAPSHOT="$2"; shift 2 ;;
    *) shift ;;
  esac
done

if [[ -z "$SNAPSHOT" ]]; then
  SNAPSHOT=$(mktemp -t tech-snap.XXXXXX.json)
  trap 'rm -f "$SNAPSHOT"' EXIT
  SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
  bash "$SCRIPT_DIR/collect.sh" > "$SNAPSHOT"
fi

# Helper jq function: compare two semver strings and emit major /
# minor / patch / unknown. Embedded inline for portability.
JQ_GAP_FN='
  def parse_semver(s): (s | tostring | split(".") | map(try (tonumber) catch 0));
  def gap(cur; lat):
    parse_semver(cur) as $c | parse_semver(lat) as $l
    | if ($c | length) < 1 or ($l | length) < 1 then "unknown"
      elif $l[0] > $c[0] then "major"
      elif ($l[1] // 0) > ($c[1] // 0) then "minor"
      elif ($l[2] // 0) > ($c[2] // 0) then "patch"
      else "up-to-date"
      end;
  def majorsBehind(cur; lat):
    parse_semver(cur) as $c | parse_semver(lat) as $l
    | ((($l[0] // 0) - ($c[0] // 0)) | if . < 0 then 0 else . end);
'

jq --argjson today "0" "$JQ_GAP_FN"'
  ( [.deps.dependabotAlerts[]? | select(.state == "open" or .state == null) | .security_vulnerability.package.name // empty] ) as $alertPkgs
  |
  (
    # npm outdated is {"pkg": {"current": "1.2.3", "latest": "2.0.0", ...}}
    (.deps.npmOutdated // {}) as $npm
    | [ $npm | to_entries[]
        | .value.current as $cur | .value.latest as $lat
        | {
            package: .key,
            current: $cur,
            latest: $lat,
            gap: gap($cur; $lat),
            majorsBehind: majorsBehind($cur; $lat),
            hasAlert: ([$alertPkgs[] | select(. == .key)] | length > 0),
            ecosystem: "npm"
          }
      ]
  ) as $npmFindings
  |
  (
    # pip list --outdated returns [{"name": ..., "version": ..., "latest_version": ...}]
    (.deps.pipOutdated // []) as $pip
    | [ $pip[]
        | {
            package: .name,
            current: .version,
            latest: .latest_version,
            gap: gap(.version; .latest_version),
            majorsBehind: majorsBehind(.version; .latest_version),
            hasAlert: ([$alertPkgs[] | select(. == .name)] | length > 0),
            ecosystem: "pip"
          }
      ]
  ) as $pipFindings
  |
  ($npmFindings + $pipFindings) as $all
  |
  {
    summary: {
      total: ($all | length),
      upToDate:    ([$all[] | select(.gap == "up-to-date")] | length),
      patchBehind: ([$all[] | select(.gap == "patch")]      | length),
      minorBehind: ([$all[] | select(.gap == "minor")]      | length),
      majorBehind: ([$all[] | select(.gap == "major")]      | length)
    },
    findings: $all,
    majorBehind: [ $all[] | select(.gap == "major" and .majorsBehind >= 2)
                         | { package, majorsBehind, current, latest, ecosystem, hasAlert } ]
  }
' "$SNAPSHOT"
