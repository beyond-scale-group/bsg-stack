#!/usr/bin/env bash
# update.sh — refresh stale BSG custom docs in the repo.
#
# Reads doctor.sh --json to identify docs that exist but are older
# than the staleness threshold (default: 90 days). For each stale doc,
# re-runs the corresponding per-agent --init script and writes the
# refreshed draft alongside a `.bsg/.update-pending/<doc>.draft.md`
# file so the human can diff against the existing version before
# committing.
#
# Per ADR-002 this verb is NOT read-only: it writes to disk. It does
# not, however, overwrite existing custom docs — drafts land in
# `.bsg/.update-pending/` for explicit human merge.
#
# Usage:
#   bash update.sh                  # refresh anything >90 days old
#   bash update.sh --threshold 30   # custom staleness threshold (days)
#   bash update.sh --dry-run        # print what would happen, change nothing
#   bash update.sh --force          # also refresh fresh docs (override threshold)

set -euo pipefail

THRESHOLD=90
DRY_RUN=0
FORCE=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --threshold) THRESHOLD="$2"; shift 2 ;;
    --dry-run)   DRY_RUN=1; shift ;;
    --force)     FORCE=1; shift ;;
    -h|--help)   sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "update.sh: unknown arg: $1" >&2; exit 2 ;;
  esac
done

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$REPO_ROOT"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CATALOG_DIR="$(cd "$SCRIPT_DIR/../../.." && pwd)"
REGISTRY="$CATALOG_DIR/agents/registry.json"

# Same agent → script + output path mapping as init.sh; keep in sync.
init_script_for() {
  case "$1" in
    seo)           echo "skills/seo-report/scripts/init-keywords.sh" ;;
    marketing)     echo "skills/marketing-report/scripts/init-calendar.sh" ;;
    pr-comms)      echo "skills/pr-comms-report/scripts/init-announced.sh" ;;
    security)      echo "skills/security-report/scripts/init-securityignore.sh" ;;
    storytelling)  echo "skills/storytelling-report/scripts/init-narrative.sh" ;;
    *)             echo "" ;;
  esac
}

output_path_for() {
  case "$1" in
    seo)           echo ".bsg/KEYWORDS.md" ;;
    marketing)     echo ".bsg/CALENDAR.md" ;;
    pr-comms)      echo ".bsg/ANNOUNCED.md" ;;
    security)      echo ".bsg/SECURITYIGNORE" ;;
    storytelling)  echo ".bsg/NARRATIVE.md" ;;
    *)             echo "" ;;
  esac
}

file_age_days() {
  local f="$1"
  [[ -e "$f" ]] || { echo ""; return; }
  if [[ "$OSTYPE" == "darwin"* ]]; then
    local mtime; mtime=$(stat -f %m "$f")
  else
    local mtime; mtime=$(stat -c %Y "$f")
  fi
  echo $(( ( $(date +%s) - mtime ) / 86400 ))
}

echo ""
echo "Updating stale custom docs (threshold: ${THRESHOLD}d, force: $FORCE)"
echo "=================================================================="

REFRESHED=0
SKIPPED=0
PENDING_DIR=".bsg/.update-pending"

while IFS= read -r name; do
  script_rel="$(init_script_for "$name")"
  output_path="$(output_path_for "$name")"
  [[ -z "$script_rel" || -z "$output_path" ]] && continue

  if [[ ! -f "$output_path" ]]; then
    echo "  ⊘ skip:    $output_path (not yet bootstrapped — run /bsg-stack init)"
    SKIPPED=$((SKIPPED + 1))
    continue
  fi

  age="$(file_age_days "$output_path")"
  if [[ "$FORCE" != "1" && "$age" -lt "$THRESHOLD" ]]; then
    echo "  ✓ fresh:   $output_path (${age}d old)"
    SKIPPED=$((SKIPPED + 1))
    continue
  fi

  script_abs="$CATALOG_DIR/$script_rel"
  [[ -f "$script_abs" ]] || script_abs="$HOME/.claude/$script_rel"
  if [[ ! -f "$script_abs" ]]; then
    echo "  ✗ missing: $script_rel — cannot refresh $output_path"
    continue
  fi

  draft_path="$PENDING_DIR/$(basename "$output_path").draft.md"

  echo "  ⟳ refresh: $output_path (${age}d old) → $draft_path"
  if [[ "$DRY_RUN" == "0" ]]; then
    mkdir -p "$PENDING_DIR"
    if content="$(bash "$script_abs" 2>/dev/null)" && [[ -n "$content" ]]; then
      printf '%s\n' "$content" > "$draft_path"
      REFRESHED=$((REFRESHED + 1))
    else
      echo "    └─ ✗ init script produced no output"
    fi
  fi
done < <(jq -r '.agents[].name' "$REGISTRY")

echo ""
echo "Summary"
echo "======="
echo "  Refreshed drafts: $REFRESHED"
echo "  Skipped (fresh or unbootstrapped): $SKIPPED"

if [[ "$REFRESHED" -gt 0 ]]; then
  echo ""
  echo "Next steps:"
  echo "  1. Diff each .bsg/.update-pending/*.draft.md against its committed sibling"
  echo "  2. Merge or discard each draft based on what's changed in the repo"
  echo "  3. Remove .bsg/.update-pending/ after merging"
fi
