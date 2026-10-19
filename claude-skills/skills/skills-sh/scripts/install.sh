#!/bin/bash
# install.sh -- Copy a skill from its GitHub repo into a skills folder, after the user's approval.
# Usage: install.sh <owner/repo> <skill-folder-in-repo> <target-folder>
#   e.g.: install.sh anthropics/skills skills/pdf ~/.claude/skills
# <skill-folder-in-repo> is the "folder:" line printed by fetch.sh ("." for a repo-root skill).
# Refuses to overwrite an existing skill. Executes nothing from the repo: plain file copy.
set -euo pipefail
repo="${1:?usage: install.sh <owner/repo> <skill-folder-in-repo> <target-folder>}"
src="${2:?usage: install.sh <owner/repo> <skill-folder-in-repo> <target-folder>}"
dest_root="${3:?usage: install.sh <owner/repo> <skill-folder-in-repo> <target-folder>}"
src="${src%/}"
if [ "$src" = "." ]; then name=$(basename "$repo"); else name=$(basename "$src"); fi
dest="$dest_root/$name"
[ -e "$dest" ] && { echo "Already exists: $dest (nothing overwritten)" >&2; exit 1; }
work=$(mktemp -d "${TMPDIR:-/tmp}/skills-sh-import.XXXXXX")
trap 'rm -rf "$work"' EXIT
if [ "$src" = "." ]; then
  git clone -q --depth 1 "https://github.com/$repo.git" "$work/repo"
else
  git clone -q --depth 1 --filter=blob:none --sparse "https://github.com/$repo.git" "$work/repo"
  git -C "$work/repo" sparse-checkout set --no-cone "/$src/"
fi
sha=$(git -C "$work/repo" rev-parse HEAD)
[ -f "$work/repo/$src/SKILL.md" ] || { echo "No SKILL.md in $repo/$src" >&2; exit 1; }
mkdir -p "$dest"
(cd "$work/repo/$src" && tar --exclude=.git -cf - .) | (cd "$dest" && tar -xf -)
printf 'source: https://github.com/%s/tree/%s/%s\nimported_on: %s\nvia: skills.sh\n' "$repo" "$sha" "$src" "$(date +%F)" > "$dest/.origin"
echo "Installed: $dest (commit $sha)"
