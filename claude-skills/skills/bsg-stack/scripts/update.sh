#!/usr/bin/env bash
# update.sh — refresh stale `.bsg/` custom-docs.
#
# Implements the `update` verb of /bsg-stack per ADR-002. Like `init`,
# but operates on docs that ALREADY exist and have grown stale; never
# creates fresh docs (that's `init`'s job). Touches the filesystem;
# does NOT open PRs (caller does that explicitly).
#
# A doc is "stale" when its mtime is more than `--max-age-days` old
# (default 90). Per-agent override is possible via --max-age-days.
#
# Behavior, per agent in registry.json:
#   1. Read the agent's `custom-doc:`
#   2. If the doc is missing → skip with a note (run /bsg-stack init)
#   3. If the doc exists and is fresh → skip silently
#   4. If the doc exists and is stale → re-run the per-agent init
#      script with --force to regenerate
#
# Usage:
#   bash claude-skills/skills/bsg-stack/scripts/update.sh
#   bash claude-skills/skills/bsg-stack/scripts/update.sh --dry-run
#   bash claude-skills/skills/bsg-stack/scripts/update.sh --max-age-days 30
#   bash claude-skills/skills/bsg-stack/scripts/update.sh --only po,seo
#
# Flags:
#   --dry-run             Print what would be done; touch nothing.
#   --max-age-days N      Threshold for stale (default 90).
#   --only LIST           Comma-separated bus labels to process.
#
# Exit codes:
#   0  — every requested action succeeded (or was a no-op)
#   1  — at least one per-agent re-init failed
#   2  — bad usage

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CATALOG_DIR="$(cd "$SCRIPT_DIR/../../.." && pwd)"
REGISTRY="$CATALOG_DIR/agents/registry.json"

# shellcheck source=../../../scripts/_bsg-paths.sh disable=SC1091
source "$CATALOG_DIR/scripts/_bsg-paths.sh"

DRY_RUN=0
MAX_AGE=90
ONLY=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)        DRY_RUN=1;        shift ;;
    --max-age-days)   MAX_AGE="$2";     shift 2 ;;
    --only)           ONLY="$2";        shift 2 ;;
    -h|--help)
      sed -n '2,/^$/p' "$0" | sed 's/^# \?//'
      exit 0 ;;
    *) echo "update.sh: unknown flag: $1" >&2; exit 2 ;;
  esac
done

if [[ ! -f "$REGISTRY" ]]; then
  echo "update.sh: cannot find agents/registry.json (looked in $CATALOG_DIR)" >&2
  exit 2
fi

note() { printf '  %s\n' "$*"; }
say()  { printf '%s\n' "$*"; }

# Cross-platform mtime in days (BSD stat on macOS, GNU stat on Linux).
file_age_days() {
  local f="$1" mtime now
  if mtime="$(stat -f %m "$f" 2>/dev/null)"; then
    :
  elif mtime="$(stat -c %Y "$f" 2>/dev/null)"; then
    :
  else
    echo ""; return
  fi
  now="$(date +%s)"
  echo $(( (now - mtime) / 86400 ))
}

custom_doc_for() {
  awk -F': *' '/^custom-doc:/ {print $2; exit}' "$CATALOG_DIR/agents/$1.md"
}

init_script_for() {
  case "$1" in
    po-manager)   echo "skills/po/scripts/init.sh" ;;
    md-to-office) echo "skills/md-to-office/scripts/init-brand.sh" ;;
    *)            echo "" ;;
  esac
}

run_agent_update() {
  local name="$1" custom_doc target age script
  custom_doc="$(custom_doc_for "$name")"

  if [[ -z "$custom_doc" ]]; then
    note "$name: no custom-doc declared, skipping"
    return 0
  fi

  # Resolve to whichever path actually exists (prefer .bsg/, fall back
  # to legacy). If neither exists, this is an `init` case, not update.
  local resolved
  if [[ -e "$custom_doc" ]]; then
    resolved="$custom_doc"
  else
    resolved=""
    # Try the common legacy mappings:
    case "$name" in
      po-manager)    [[ -f po/PLAN.md ]]          && resolved="po/PLAN.md" ;;
      storytelling)  [[ -f brand/NARRATIVE.md ]]  && resolved="brand/NARRATIVE.md" ;;
      seo)           [[ -f seo/KEYWORDS.md ]]     && resolved="seo/KEYWORDS.md" ;;
      marketing)     [[ -f marketing/CALENDAR.md ]] && resolved="marketing/CALENDAR.md" ;;
      pr-comms)      [[ -f comms/ANNOUNCED.md ]]  && resolved="comms/ANNOUNCED.md" ;;
      security)      [[ -f .securityignore ]]     && resolved=".securityignore" ;;
    esac
  fi

  if [[ -z "$resolved" ]]; then
    note "$name: $custom_doc is missing — run /bsg-stack init first"
    return 0
  fi

  age="$(file_age_days "$resolved")"
  if [[ -z "$age" ]]; then
    note "$name: cannot stat $resolved, skipping"
    return 0
  fi

  if (( age <= MAX_AGE )); then
    note "$name: $resolved is fresh (${age}d ≤ ${MAX_AGE}d) — skipping"
    return 0
  fi

  note "$name: $resolved is stale (${age}d > ${MAX_AGE}d)"

  script="$(init_script_for "$name")"
  if [[ -z "$script" || ! -f "$CATALOG_DIR/$script" ]]; then
    note "$name: no init script yet — manual refresh required"
    return 0
  fi

  if [[ $DRY_RUN -eq 1 ]]; then
    note "  [dry-run] would run: bash $CATALOG_DIR/$script --force"
    return 0
  fi

  if ! bash "$CATALOG_DIR/$script" --force; then
    note "$name: refresh exited non-zero"
    return 1
  fi
  note "$name: refreshed"
}

# ---------------------------------------------------------------- main

say "/bsg-stack update"
if [[ $DRY_RUN -eq 1 ]]; then
  say "(dry-run mode — no files will be written)"
fi
say "  staleness threshold: ${MAX_AGE} days"
say ""

filtered_agents=()
while IFS= read -r entry; do
  name="$(jq -r '.name' <<<"$entry")"
  bus="$(jq -r '.bus_label' <<<"$entry")"
  if [[ -n "$ONLY" ]]; then
    case ",$ONLY," in
      *",$bus,"*) filtered_agents+=("$name") ;;
    esac
  else
    filtered_agents+=("$name")
  fi
done < <(jq -c '.agents[]' "$REGISTRY")

failed=0
for name in "${filtered_agents[@]}"; do
  if ! run_agent_update "$name"; then
    failed=$((failed + 1))
  fi
done
say ""

if [[ $failed -gt 0 ]]; then
  say "✗ $failed per-agent update(s) failed"
  exit 1
fi

say "✓ /bsg-stack update complete"
if [[ $DRY_RUN -eq 1 ]]; then
  say "  Re-run without --dry-run to apply."
fi
