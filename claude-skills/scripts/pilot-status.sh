#!/usr/bin/env bash
# pilot-status.sh — report #181 output:commit pilot health.
#
# Tallies PRs opened by a pilot agent over a window (default 7 days)
# and reports:
#
#   - attempts: PRs the agent opened matching fix(pilot): title pattern
#   - merged:   state MERGED
#   - closed:   state CLOSED (not merged — agent abandoned, human rejected)
#   - open:     still pending human review
#   - reverts:  merged commits reverted within the window
#
# Success metric from #181: merge-rate >= 60% and revert-rate == 0%
# over 7 days. If both hold, the pilot is a go to expand to a second
# agent. If not, the pilot is a stop — either tighten the scope
# contract or roll back to output: pr.
#
# Usage:
#   pilot-status.sh [--agent NAME] [--days N] [--repo OWNER/NAME]
#
# Defaults: --agent tech --days 7.

set -euo pipefail

AGENT="tech"
DAYS=7
REPO_FLAG=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --agent) AGENT="$2"; shift 2 ;;
    --days)  DAYS="$2";  shift 2 ;;
    --repo)  REPO_FLAG=(--repo "$2"); shift 2 ;;
    -h|--help)
      sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *) echo "pilot-status.sh: unknown arg: $1" >&2; exit 2 ;;
  esac
done

# Window: PRs whose createdAt is within the last N days. GitHub date
# math via `date -v` (BSD) or `date -d` (GNU) — detect once.
if date -v-${DAYS}d +%Y-%m-%d >/dev/null 2>&1; then
  since=$(date -v-${DAYS}d +%Y-%m-%d)
else
  since=$(date -d "-${DAYS} days" +%Y-%m-%d)
fi

# Pull every PR matching the pilot convention: title starts with
# `fix(pilot):`. State is filtered client-side so we can also count
# CLOSED-but-not-merged (abandoned).
prs=$(gh pr list "${REPO_FLAG[@]}" \
  --state all \
  --search "fix(pilot): in:title created:>=$since" \
  --json number,title,state,createdAt,mergedAt,closedAt,url,mergeCommit \
  --limit 200 2>/dev/null || echo "[]")

n_total=$(jq 'length' <<<"$prs")
n_merged=$(jq '[.[] | select(.state == "MERGED")] | length' <<<"$prs")
n_closed=$(jq '[.[] | select(.state == "CLOSED")] | length' <<<"$prs")
n_open=$(jq   '[.[] | select(.state == "OPEN")]   | length' <<<"$prs")

# Revert detection: any merged PR whose mergeCommit SHA appears in a
# subsequent revert commit on main. Cheap heuristic: look at the main
# branch's last $DAYS+2 days of commits for "Revert" messages that
# reference a short SHA we can match.
reverts=0
if [[ "$n_merged" -gt 0 ]]; then
  # Pull recent main history once.
  recent=$(git log --since="${DAYS} days ago" --pretty=format:'%H %s' 2>/dev/null || true)
  while IFS= read -r sha; do
    [[ -z "$sha" ]] && continue
    short="${sha:0:7}"
    if grep -Fq "Revert" <<<"$recent" && grep -Fq "$short" <<<"$recent"; then
      reverts=$((reverts + 1))
    fi
  done < <(jq -r '.[] | select(.state == "MERGED") | .mergeCommit.oid // empty' <<<"$prs")
fi

# Merge rate = merged / (merged + closed). Open PRs are excluded —
# they haven't had their disposition yet.
decided=$((n_merged + n_closed))
if [[ "$decided" -eq 0 ]]; then
  merge_rate="n/a"
else
  merge_rate="$(( 100 * n_merged / decided ))%"
fi

echo "pilot-status: agent=$AGENT window=${DAYS}d since=$since"
echo "  attempts:   $n_total"
echo "  merged:     $n_merged"
echo "  closed:     $n_closed (abandoned/rejected)"
echo "  open:       $n_open (pending review)"
echo "  merge-rate: $merge_rate (on decided PRs)"
echo "  reverts:    $reverts"

# Decision hint per #181 acceptance: merge-rate >= 60% and reverts == 0.
if [[ "$decided" -eq 0 ]]; then
  echo
  echo "no decided PRs yet — metric is indeterminate. apply 'safe-to-automate' to an issue to start the pilot."
else
  pct=$(( 100 * n_merged / decided ))
  if [[ $pct -ge 60 && $reverts -eq 0 ]]; then
    echo
    echo "pilot health: PASS — meets the >=60% merge-rate / 0 reverts bar. expand to a second agent."
  else
    echo
    echo "pilot health: WATCH — below the #181 bar. tighten scope or consider rolling back."
  fi
fi

# Per-PR table (sorted by createdAt descending).
if [[ "$n_total" -gt 0 ]]; then
  echo
  echo "  Recent PRs:"
  jq -r '
    sort_by(.createdAt) | reverse | .[]
    | "    #\(.number) [\(.state)]  \(.createdAt[0:10])  \(.title)"
  ' <<<"$prs"
fi
