#!/bin/bash
# fetch.sh -- Locate and print the SKILL.md of a skills.sh skill in its GitHub repo (read-only).
# Usage: fetch.sh <owner/repo> <skillId>
# Prints: the skill folder, the files it contains, the repo's stars, then the SKILL.md.
set -euo pipefail
repo="${1:?usage: fetch.sh <owner/repo> <skillId>}"
id="${2:?usage: fetch.sh <owner/repo> <skillId>}"
id_re=$(printf '%s' "$id" | sed 's/[][\.*^$+?(){}|/]/\\&/g')
tree=$(gh api "repos/$repo/git/trees/HEAD?recursive=1" --jq '.tree[].path')
skill_md=$(printf '%s\n' "$tree" | grep -E "(^|/)$id_re/SKILL\.md$" | head -1 || true)
if [ -z "$skill_md" ]; then
  # Fallback: a SKILL.md whose frontmatter carries this name (covers repo-root skills)
  while IFS= read -r p; do
    if gh api "repos/$repo/contents/$p" --jq .content | base64 -d | grep -qE "^name: *[\"']?$id_re[\"']? *$"; then
      skill_md="$p"; break
    fi
  done < <(printf '%s\n' "$tree" | grep -E '(^|/)SKILL\.md$' || true)
fi
[ -n "$skill_md" ] || { echo "No SKILL.md found for $id in $repo" >&2; exit 1; }
dir=$(dirname "$skill_md")
echo "repo: https://github.com/$repo"
echo "stars: $(gh api "repos/$repo" --jq .stargazers_count)"
echo "folder: $dir"
echo "files:"
printf '%s\n' "$tree" | awk -v d="$dir/" 'd == "./" || index($0, d) == 1' | sed 's/^/  /'
echo "---- $skill_md ----"
gh api "repos/$repo/contents/$skill_md" --jq .content | base64 -d
