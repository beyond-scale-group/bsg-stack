#!/bin/bash
# search.sh -- Search the skills.sh directory (public API, read-only).
# Usage: search.sh "<query>" [limit]
# Output: one TSV line per skill: installs, source (owner/repo), skillId, skills.sh page
set -euo pipefail
q="${1:?usage: search.sh \"<query>\" [limit]}"
limit="${2:-10}"
curl -fsS -m 20 -G "https://skills.sh/api/search" \
  --data-urlencode "q=$q" --data-urlencode "limit=$limit" \
  | jq -r '.skills[] | [.installs, .source, .skillId, ("https://skills.sh/" + .id)] | @tsv'
