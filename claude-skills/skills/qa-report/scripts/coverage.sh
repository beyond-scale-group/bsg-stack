#!/usr/bin/env bash
# coverage.sh — coverage reporter.
#
# Reads the QA snapshot (from collect.sh or --snapshot) and emits current
# coverage + delta-vs-previous.

set -euo pipefail

SNAPSHOT=""
while [[ $# -gt 0 ]]; do
  case $1 in
    --snapshot) SNAPSHOT="$2"; shift 2 ;;
    *) shift ;;
  esac
done

if [[ -z "$SNAPSHOT" ]]; then
  SNAPSHOT=$(mktemp -t qa-snap.XXXXXX.json)
  trap 'rm -f "$SNAPSHOT"' EXIT
  SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
  bash "$SCRIPT_DIR/collect.sh" > "$SNAPSHOT"
fi

jq '
  .coverage as $c
  | .previous as $p
  | {
      found: $c.found,
      format: $c.format,
      current: {
        line:   { pct: $c.overall.line },
        branch: { pct: $c.overall.branch },
        files:  { total: ($c.perFile | length), zeroCoverage: $c.overall.zeroCoverage }
      },
      previous: (
        if ($p == null or $p.coverage == null) then null
        else {
          line:   { pct: ($p.coverage.overall.line // null) },
          branch: { pct: ($p.coverage.overall.branch // null) },
          files:  { zeroCoverage: ($p.coverage.overall.zeroCoverage // null) },
          date:   $p.date
        } end
      ),
      delta: (
        if ($p == null or $p.coverage == null or $c.overall.line == null or $p.coverage.overall.line == null) then
          { line: null, branch: null, zeroCoverage: null }
        else
          {
            line:   ((($c.overall.line // 0) - ($p.coverage.overall.line // 0)) * 100 | floor / 100),
            branch: (if ($c.overall.branch == null or $p.coverage.overall.branch == null) then null
                     else ((($c.overall.branch // 0) - ($p.coverage.overall.branch // 0)) * 100 | floor / 100) end),
            zeroCoverage: (if ($c.overall.zeroCoverage == null or $p.coverage.overall.zeroCoverage == null) then null
                           else (($c.overall.zeroCoverage // 0) - ($p.coverage.overall.zeroCoverage // 0)) end)
          }
        end
      ),
      perFile: $c.perFile
    }
' "$SNAPSHOT"
