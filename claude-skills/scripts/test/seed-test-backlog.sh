#!/usr/bin/env bash
# seed-test-backlog.sh — populate a test repo with N synthetic issues
# for the pipeline regression harness (#292).
#
# Each issue carries: bug or enhancement, a bus label (tech/qa/seo),
# label `test-fixture` (for cleanup), title prefix `[test-fixture]`,
# milestone (default `E-test`), and a deterministic micro-action body
# the agent can execute in <= 1 LOC / 1 file.
#
# Distribution: 60% tech, 25% qa, 15% seo.
#
# Usage:
#   bash claude-skills/scripts/test/seed-test-backlog.sh \
#     --repo beyond-scale-group/bsg-stack-test-harness \
#     --count 30
#
# Idempotent: refuses to seed when test-fixture issues already exist
# (use --force to override) so re-runs don't double the backlog.

set -euo pipefail

REPO="beyond-scale-group/bsg-stack-test-harness"
COUNT=30
MILESTONE="E-test"
FORCE=false
DRY_RUN=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo)      REPO="$2"; shift 2 ;;
    --count)     COUNT="$2"; shift 2 ;;
    --milestone) MILESTONE="$2"; shift 2 ;;
    --force)     FORCE=true; shift ;;
    --dry-run)   DRY_RUN=true; shift ;;
    -h|--help)   sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "seed-test-backlog: unknown arg: $1" >&2; exit 2 ;;
  esac
done

existing=$(gh issue list --repo "$REPO" --label test-fixture --state open --json number --jq length)
if [[ "$existing" -gt 0 && "$FORCE" != "true" ]]; then
  echo "seed: $existing existing test-fixture issues — pass --force to re-seed" >&2
  exit 1
fi

# Ensure milestone exists (idempotent).
ms_exists=$(gh api "repos/$REPO/milestones?state=all" --jq "[.[] | select(.title == \"$MILESTONE\")] | length")
if [[ "$ms_exists" -eq 0 ]]; then
  gh api -X POST "repos/$REPO/milestones" \
    -f title="$MILESTONE" \
    -f description="Synthetic backlog for pipeline regression test (#292)" >/dev/null
fi

# Bootstrap labels (idempotent — gh label create exits 0 if it exists with --force).
for label in test-fixture tech qa seo bug enhancement; do
  gh label create --repo "$REPO" "$label" --color cccccc --force >/dev/null 2>&1 || true
done

# Distribution 60/25/15.
mix=()
for i in $(seq 1 "$COUNT"); do
  r=$((RANDOM % 100))
  if   [[ $r -lt 60 ]]; then mix+=(tech)
  elif [[ $r -lt 85 ]]; then mix+=(qa)
  else                        mix+=(seo)
  fi
done

# Pick markdown files in the repo as targets (deterministic per index).
mapfile -t FILES < <(find . -maxdepth 3 -name "*.md" -not -path "./.git/*" -not -path "./node_modules/*" 2>/dev/null | sort | head -20)
if [[ ${#FILES[@]} -eq 0 ]]; then
  echo "seed: no .md files found to target — run from a clone of the harness repo" >&2
  exit 2
fi
NUM_FILES=${#FILES[@]}

created=0
for i in $(seq 0 $((COUNT - 1))); do
  bus="${mix[$i]}"
  type=$([ $((RANDOM % 5)) -eq 0 ] && echo enhancement || echo bug)
  file="${FILES[$((i % NUM_FILES))]}"
  title="[test-fixture] add fix-me marker to $(basename "$file") (#$((i + 1)))"
  body=$(cat <<EOM
## Synthetic test fixture

Add a single line at the top of \`$file\`:

\`\`\`
<!-- TODO(test-fixture-$((i + 1))): fix-me -->
\`\`\`

**Estimated effort:** 1 LOC, 1 file.
**Bus:** \`$bus\`

---
This issue was created by \`claude-skills/scripts/test/seed-test-backlog.sh\`
for the pipeline regression harness (#292). Auto-removable via
\`run-pipeline-test.sh --reset\`.
EOM
)
  if [[ "$DRY_RUN" == "true" ]]; then
    echo "DRY: $title  [$bus, $type, milestone=$MILESTONE]"
    continue
  fi
  gh issue create --repo "$REPO" \
    --title "$title" \
    --body "$body" \
    --label "test-fixture,$bus,$type" \
    --milestone "$MILESTONE" >/dev/null
  created=$((created + 1))
done

echo "seed: $created issue(s) created on $REPO under milestone '$MILESTONE'"
