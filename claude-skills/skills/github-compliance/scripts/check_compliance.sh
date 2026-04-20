#!/bin/bash
# GitHub Org Compliance Checker & Fixer
# Usage: ./check_compliance.sh [--fix] [--org beyond-scale-group] [--team board]

ORG="${ORG:-beyond-scale-group}"
TEAM="${TEAM:-board}"
PERMISSION="${PERMISSION:-admin}"
FIX=false

while [[ "$#" -gt 0 ]]; do
  case $1 in
    --fix) FIX=true ;;
    --org) ORG="$2"; shift ;;
    --team) TEAM="$2"; shift ;;
    --permission) PERMISSION="$2"; shift ;;
  esac
  shift
done

echo "=== GitHub Compliance Check ==="
echo "Org: $ORG | Team: $TEAM | Permission: $PERMISSION"
echo ""

# Get all non-archived private repos
ALL_REPOS=$(gh api "orgs/$ORG/repos" --paginate --jq '[.[] | select(.private == true and .archived == false) | .name] | .[]' 2>&1)

# Get repos already assigned to the team
TEAM_REPOS=$(gh api "orgs/$ORG/teams/$TEAM/repos" --paginate --jq '[.[].name] | .[]' 2>&1)

MISSING=()
COMPLIANT=()

while IFS= read -r repo; do
  if echo "$TEAM_REPOS" | grep -qx "$repo"; then
    COMPLIANT+=("$repo")
  else
    MISSING+=("$repo")
  fi
done <<< "$ALL_REPOS"

echo "✓ Compliant (${#COMPLIANT[@]} repos):"
for r in "${COMPLIANT[@]}"; do echo "    $r"; done

echo ""
echo "✗ Non-compliant (${#MISSING[@]} repos):"
for r in "${MISSING[@]}"; do echo "    $r"; done

if [ ${#MISSING[@]} -eq 0 ]; then
  echo ""
  echo "✓ All repos are compliant."
  exit 0
fi

if [ "$FIX" = true ]; then
  echo ""
  echo "=== Fixing non-compliant repos ==="
  for repo in "${MISSING[@]}"; do
    result=$(gh api --method PUT "orgs/$ORG/teams/$TEAM/repos/$ORG/$repo" -f permission="$PERMISSION" 2>&1)
    if [ $? -eq 0 ]; then
      echo "  ✓ $repo"
    else
      echo "  ✗ $repo — $result"
    fi
  done
  echo ""
  echo "Done."
else
  echo ""
  echo "Run with --fix to assign team '$TEAM' to missing repos."
fi
