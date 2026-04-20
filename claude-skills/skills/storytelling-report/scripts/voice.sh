#!/usr/bin/env bash
# voice.sh — tone score per asset + drift detection.

set -euo pipefail

SNAPSHOT=""
while [[ $# -gt 0 ]]; do
  case $1 in
    --snapshot) SNAPSHOT="$2"; shift 2 ;;
    *) shift ;;
  esac
done

if [[ -z "$SNAPSHOT" ]]; then
  SNAPSHOT=$(mktemp -t brand-snap.XXXXXX.json)
  trap 'rm -f "$SNAPSHOT"' EXIT
  SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
  bash "$SCRIPT_DIR/collect.sh" > "$SNAPSHOT"
fi

jq '
  (.narrative.toneTarget // 7.0) as $target
  | (.assets // []) as $assets
  |
  [ $assets[]
    | (.fleschEase / 10) as $base
    | (if $base > 10 then 10 elif $base < 0 then 0 else $base end) as $clampedBase
    | (.passiveRatio * 0.5) as $passivePenalty
    | (.jargonDensity * 100 * 0.5) as $jargonPenalty
    | ($clampedBase - $passivePenalty - $jargonPenalty) as $raw
    | (if $raw > 10 then 10 elif $raw < 0 then 0 else $raw end) as $tone
    | . + { toneScore: ($tone * 100 | floor / 100) }
  ] as $scored
  |
  ( $scored | map(.toneScore) | add / (if ($scored | length) == 0 then 1 else ($scored | length) end) ) as $mean
  | ( $scored | map(pow(.toneScore - $mean; 2)) | add / (if ($scored | length) == 0 then 1 else ($scored | length) end) | sqrt ) as $stddev
  |
  [ $scored[]
    | ((.toneScore - $target)) as $dev
    | (if (($stddev * 2) > 0.5) then ($stddev * 2) else 0.5 end) as $threshold
    | select(($dev | if . < 0 then - . else . end) > $threshold)
    | {
        file: .file,
        toneScore: .toneScore,
        deviation: ($dev * 100 | floor / 100),
        direction: (if $dev < 0 then "too formal / robotic" else "too casual / loose" end)
      }
  ] as $drift
  |
  {
    summary: {
      assetsScored: ($scored | length),
      targetTone: $target,
      meanScore: (if ($scored | length) == 0 then null else ($mean * 100 | floor / 100) end),
      stddev:    (if ($scored | length) == 0 then null else ($stddev * 100 | floor / 100) end),
      driftCount: ($drift | length)
    },
    perAsset: $scored,
    drift: $drift
  }
' "$SNAPSHOT"
