#!/usr/bin/env bash
# stale-issues.sh [DAYS] — open issues with no real activity for N days.
#
# "Real activity" = last human-style signal. Uses `lastCommentedAt`
# from the snapshot, which is only set when a comment lands; label
# changes by bots no longer reset the stale clock (regression vs the
# pre-PR-1 script, which used `updatedAt` directly). Falls back to
# `createdAt` for issues that never received a comment.
#
# Reads a collect.sh snapshot via `--snapshot <path>`, stdin, or
# auto-run. Default threshold: 14 days.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"

DAYS=14
snapshot_path=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --snapshot) snapshot_path="$2"; shift 2 ;;
    *) DAYS="$1"; shift ;;
  esac
done

snapshot=""
if [[ -n "$snapshot_path" ]]; then
  snapshot=$(cat "$snapshot_path")
elif [[ ! -t 0 ]]; then
  snapshot=$(cat)
fi
if [[ -z "$snapshot" ]]; then
  snapshot=$(bash "$HERE/collect.sh")
fi

printf '%s' "$snapshot" | jq --argjson days "$DAYS" '
  (now) as $now
  | .issues
  | map(select(.state == "OPEN"))
  | map(
      # Prefer lastCommentedAt (real human-style activity). Fall back to
      # createdAt — NOT updatedAt, because updatedAt is bumped by bot
      # label changes and resets staleness incorrectly.
      (.lastCommentedAt // .createdAt) as $lastActivity
      | ($lastActivity | fromdateiso8601) as $lastTs
      | (($now - $lastTs) / 86400 | floor) as $daysStale
      | select($daysStale >= $days)
      | {
          number, title, url,
          assignees, labels,
          updatedAt, lastCommentedAt, lastCommentBy,
          daysStale: $daysStale
        }
    )
  | sort_by(-.daysStale)
'
