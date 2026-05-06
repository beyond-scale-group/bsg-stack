#!/usr/bin/env bash
# peer-review-candidates.sh — list PRs awaiting peer review from a given agent.
#
# Returns open PRs that:
#   - Were opened by a pilot agent (title matches `fix(*-pilot):`)
#   - Were NOT opened by the reviewing agent itself
#   - Carry `needs-human-review` label
#   - Do NOT already carry `peer-reviewed:<reviewer>` label
#   - Match the review matrix in $BSG_AUTOPILOT_FILE
#
# Usage:
#   bash claude-skills/scripts/peer-review-candidates.sh --reviewer tech [--repo OWNER/NAME]
#
# Emits one line per candidate PR (JSON). Empty output = no work.
# Exit 0 always.

set -euo pipefail

# shellcheck source=_bsg-paths.sh disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/_bsg-paths.sh"

REVIEWER=""
REPO_FLAG=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --reviewer) REVIEWER="$2"; shift 2 ;;
    --repo)     REPO_FLAG=(--repo "$2"); shift 2 ;;
    -h|--help)
      sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *) echo "peer-review-candidates.sh: unknown arg: $1" >&2; exit 2 ;;
  esac
done

if [[ -z "$REVIEWER" ]]; then
  echo "peer-review-candidates.sh: --reviewer is required" >&2
  exit 2
fi

# Read the review matrix from $BSG_AUTOPILOT_FILE.
# The reviewer must be listed, and we extract which agents it reviews.
if [[ ! -f "$BSG_AUTOPILOT_FILE" ]]; then
  exit 0
fi

enabled=$(grep -E '^\s*enabled\s*:' "$BSG_AUTOPILOT_FILE" 2>/dev/null | head -1 | sed 's/.*:\s*//' | tr -d '[:space:]')
if [[ "$enabled" != "true" ]]; then
  exit 0
fi

# Parse the peer_review section. Look for the reviewer's block and extract
# the agents it reviews. Simple grep-based parsing for YAML subset.
in_peer_review=false
in_reviewer=false
in_reviews=false
reviews_list=()

while IFS= read -r line; do
  if [[ "$line" =~ ^peer_review: ]]; then
    in_peer_review=true
    continue
  fi
  if [[ "$in_peer_review" == true ]]; then
    # New top-level key ends peer_review
    if [[ "$line" =~ ^[a-z] && ! "$line" =~ ^[[:space:]] ]]; then
      break
    fi
    # Agent block: "  tech:" (2-space indent, agent name, colon)
    if [[ "$line" =~ ^[[:space:]]{2}${REVIEWER}: ]]; then
      in_reviewer=true
      continue
    fi
    # Another agent block ends our reviewer
    if [[ "$in_reviewer" == true && "$line" =~ ^[[:space:]]{2}[a-z] && "$line" =~ : ]]; then
      if [[ ! "$line" =~ ^[[:space:]]{4} ]]; then
        break
      fi
    fi
    if [[ "$in_reviewer" == true ]]; then
      if [[ "$line" =~ ^[[:space:]]*reviews: ]]; then
        in_reviews=true
        # Inline list: reviews: [qa, seo]
        if [[ "$line" =~ \[(.+)\] ]]; then
          IFS=', ' read -ra items <<< "${BASH_REMATCH[1]}"
          reviews_list+=("${items[@]}")
          in_reviews=false
        fi
        continue
      fi
      if [[ "$in_reviews" == true ]]; then
        if [[ "$line" =~ ^[[:space:]]*-[[:space:]]+([a-z_-]+) ]]; then
          reviews_list+=("${BASH_REMATCH[1]}")
        else
          in_reviews=false
        fi
      fi
    fi
  fi
done < "$BSG_AUTOPILOT_FILE"

if [[ ${#reviews_list[@]} -eq 0 ]]; then
  exit 0
fi

# Build a search query for pilot PRs not yet peer-reviewed by this reviewer.
peer_label="peer-reviewed:${REVIEWER}"

prs=$(gh pr list "${REPO_FLAG[@]}" \
  --state open \
  --label "needs-human-review" \
  --search "fix( in:title -pilot): in:title" \
  --json number,title,labels,url,author \
  --limit 50 2>/dev/null || echo "[]")

# Filter: not opened by the reviewer, not already peer-reviewed by them,
# and the opening agent is in the reviews list.
jq -c --arg peer "$peer_label" --argjson reviews "$(printf '%s\n' "${reviews_list[@]}" | jq -R . | jq -s .)" '
  .[]
  | select(.labels | all(.name != $peer))
  | select(
      .title as $t |
      $reviews | any(. as $agent |
        $t | test("fix\\(" + $agent + "-pilot\\):")
      )
    )
  | {number, title, url}
' <<<"$prs"
