#!/usr/bin/env bash
# doctor.sh — read-only health scorecard for BSG agent infrastructure.
#
# Implements the contract in .bsg/adr/002-doctor-skill-contract.md:
#   - touches no files, opens no PRs, makes no GitHub mutations
#   - exit 0 when nothing is missing, exit 1 when at least one row is ✗
#   - soft ⚠ warnings (stale, partial) do not raise exit code
#
# Checks each row independently and prints a fixed-width scorecard. The
# row order follows agents/registry.json so the output is stable across
# repos.
#
# Usage:
#   doctor.sh              full scorecard
#   doctor.sh --status     one-line summary instead of the full table
#   doctor.sh --json       machine-readable JSON output (for CI / pipes)
#
# Run from the target repo's root.

set -euo pipefail

MODE="full"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --status) MODE="status"; shift ;;
    --json)   MODE="json"; shift ;;
    -h|--help)
      sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *) echo "doctor.sh: unknown flag: $1" >&2; exit 2 ;;
  esac
done

# Locate the catalog. We walk up from this script to find the
# claude-skills/ root (works whether running from the repo or the
# cached ~/.claude/ copy).
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
catalog_dir="$(cd "$script_dir/../../.." && pwd)"
registry="$catalog_dir/agents/registry.json"

if [[ ! -f "$registry" ]]; then
  echo "doctor.sh: cannot find agents/registry.json (looked in $catalog_dir)" >&2
  exit 2
fi

# ---------------------------------------------------------------- helpers

# Resolve the on-disk location of an agent's custom-doc, preferring
# the new .bsg/ path (ADR-001) over the legacy folder.
resolve_doc() {
  local new_path="$1" legacy_path="$2"
  if [[ -e "$new_path" ]]; then
    printf '%s\t%s\n' "new" "$new_path"
  elif [[ -n "$legacy_path" && -e "$legacy_path" ]]; then
    printf '%s\t%s\n' "legacy" "$legacy_path"
  else
    printf '%s\t%s\n' "missing" "$new_path"
  fi
}

# Days since file was last modified (rounds down). Empty when missing.
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

# Status glyph + remediation hint.
fmt_status() {
  local kind="$1" detail="$2"
  case "$kind" in
    ok)      printf "✓ present (%s)" "$detail" ;;
    warn)    printf "⚠ %s" "$detail" ;;
    missing) printf "✗ missing — run /bsg-stack init" ;;
  esac
}

# ---------------------------------------------------------------- legacy path map
# Map each agent's bus label to the legacy folder where its custom doc
# used to live, so doctor can detect partially-migrated repos. Edit when
# adding new agents (mirrors ADR-001's migration table).
legacy_doc() {
  case "$1" in
    po)            echo "po/PLAN.md" ;;
    storytelling)  echo "brand/NARRATIVE.md" ;;
    seo)           echo "seo/KEYWORDS.md" ;;
    marketing)     echo "marketing/CALENDAR.md" ;;
    pr-comms)      echo "comms/ANNOUNCED.md" ;;
    security)      echo ".securityignore" ;;
    tech)          echo "adr/" ;;
    qa)            echo "qa/reports/" ;;
    cleaner)       echo "" ;;  # cleaner has no custom doc historically
    *)             echo "" ;;
  esac
}

# ---------------------------------------------------------------- gather

declare -a ROWS_AGENT ROWS_DOC ROWS_STATUS ROWS_KIND
EXIT_CODE=0
WARN_COUNT=0
MISSING_COUNT=0
OK_COUNT=0

while IFS= read -r entry; do
  name=$(jq -r '.name' <<<"$entry")
  bus=$(jq -r '.bus_label' <<<"$entry")

  # Pull custom-doc from the agent's own frontmatter. Fast path: grep
  # the first scalar `custom-doc:` line so we don't shell out to a YAML
  # parser. Agents that don't ship custom-doc are skipped (e.g. cleaner).
  agent_file="$catalog_dir/agents/$name.md"
  if [[ ! -f "$agent_file" ]]; then
    ROWS_AGENT+=("$name"); ROWS_DOC+=("(no agent file)"); ROWS_STATUS+=("⚠ unknown"); ROWS_KIND+=("warn")
    WARN_COUNT=$(( WARN_COUNT + 1 ))
    continue
  fi
  custom_doc=$(awk -F': *' '/^custom-doc:/ {print $2; exit}' "$agent_file")
  if [[ -z "$custom_doc" ]]; then
    ROWS_AGENT+=("$name"); ROWS_DOC+=("—"); ROWS_STATUS+=("⚠ no custom-doc declared"); ROWS_KIND+=("warn")
    WARN_COUNT=$(( WARN_COUNT + 1 ))
    continue
  fi

  legacy=$(legacy_doc "$bus")
  IFS=$'\t' read -r kind found < <(resolve_doc "$custom_doc" "$legacy")

  case "$kind" in
    new)
      age=$(file_age_days "$found")
      if [[ -n "$age" && "$age" -gt 90 ]]; then
        ROWS_STATUS+=("$(fmt_status warn "stale (${age}d old)")")
        ROWS_KIND+=("warn")
        WARN_COUNT=$(( WARN_COUNT + 1 ))
      else
        ROWS_STATUS+=("$(fmt_status ok "${age}d old")")
        ROWS_KIND+=("ok")
        OK_COUNT=$(( OK_COUNT + 1 ))
      fi
      ROWS_AGENT+=("$name"); ROWS_DOC+=("$custom_doc")
      ;;
    legacy)
      ROWS_AGENT+=("$name"); ROWS_DOC+=("$custom_doc → $found")
      ROWS_STATUS+=("$(fmt_status warn "legacy path — migrate to .bsg/")")
      ROWS_KIND+=("warn")
      WARN_COUNT=$(( WARN_COUNT + 1 ))
      ;;
    missing)
      ROWS_AGENT+=("$name"); ROWS_DOC+=("$custom_doc")
      ROWS_STATUS+=("$(fmt_status missing "")")
      ROWS_KIND+=("missing")
      MISSING_COUNT=$(( MISSING_COUNT + 1 ))
      EXIT_CODE=1
      ;;
  esac
done < <(jq -c '.agents[]' "$registry")

# ---------------------------------------------------------------- labels
declare -a LABEL_NAMES LABEL_STATUS LABEL_KIND
LABEL_NAMES=("needs-human-review" "human-reviewed")
while IFS= read -r bus; do LABEL_NAMES+=("$bus"); done < <(jq -r '.agents[].bus_label' "$registry")

if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
  existing=$(gh label list --limit 200 --json name --jq '.[].name' 2>/dev/null || echo "")
  for lbl in "${LABEL_NAMES[@]}"; do
    if grep -qx "$lbl" <<<"$existing"; then
      LABEL_STATUS+=("✓ exists"); LABEL_KIND+=("ok"); OK_COUNT=$(( OK_COUNT + 1 ))
    else
      LABEL_STATUS+=("✗ missing — run /bsg-stack init")
      LABEL_KIND+=("missing")
      MISSING_COUNT=$(( MISSING_COUNT + 1 ))
      EXIT_CODE=1
    fi
  done
else
  for _ in "${LABEL_NAMES[@]}"; do
    LABEL_STATUS+=("⚠ gh not available — cannot check"); LABEL_KIND+=("warn")
    WARN_COUNT=$(( WARN_COUNT + 1 ))
  done
fi

# ---------------------------------------------------------------- autopilot
autopilot_file=""
autopilot_kind="missing"
autopilot_detail="not configured (auto-implementation disabled)"
if [[ -f .bsg/AUTOPILOT.yml ]]; then
  autopilot_file=".bsg/AUTOPILOT.yml"
elif [[ -f .bsg-autopilot.yml ]]; then
  autopilot_file=".bsg-autopilot.yml"
  autopilot_kind="warn"
  autopilot_detail="legacy dotfile path — move to .bsg/AUTOPILOT.yml"
fi
if [[ -n "$autopilot_file" ]]; then
  enabled=$(grep -E '^\s*enabled\s*:' "$autopilot_file" 2>/dev/null | head -1 | sed 's/.*:\s*//' | tr -d '[:space:]')
  if [[ "$enabled" == "true" ]]; then
    [[ "$autopilot_kind" == "missing" ]] && autopilot_kind="ok"
    autopilot_detail="enabled — file: $autopilot_file"
  else
    autopilot_kind="warn"
    autopilot_detail="present but enabled=$enabled — file: $autopilot_file"
  fi
fi

# Tally autopilot into counters
case "$autopilot_kind" in
  ok)      OK_COUNT=$(( OK_COUNT + 1 )) ;;
  warn)    WARN_COUNT=$(( WARN_COUNT + 1 )) ;;
  missing) WARN_COUNT=$(( WARN_COUNT + 1 )) ;;  # advisory; do not fail the build
esac

# ---------------------------------------------------------------- output

if [[ "$MODE" == "status" ]]; then
  total=$(( OK_COUNT + WARN_COUNT + MISSING_COUNT ))
  printf 'BSG: %d ok / %d warn / %d missing (autopilot: %s)\n' \
    "$OK_COUNT" "$WARN_COUNT" "$MISSING_COUNT" "$autopilot_kind"
  exit "$EXIT_CODE"
fi

if [[ "$MODE" == "json" ]]; then
  jq -n \
    --argjson ok "$OK_COUNT" \
    --argjson warn "$WARN_COUNT" \
    --argjson missing "$MISSING_COUNT" \
    --arg autopilot "$autopilot_kind" \
    --arg autopilot_file "$autopilot_file" \
    '{
       summary: { ok: $ok, warn: $warn, missing: $missing },
       autopilot: { kind: $autopilot, file: $autopilot_file }
     }'
  exit "$EXIT_CODE"
fi

# Human-readable scorecard
printf '\n'
printf 'Agent          Custom doc                                 Status\n'
printf -- '-------------  -----------------------------------------  --------------------------------------------\n'
for i in "${!ROWS_AGENT[@]}"; do
  printf '%-13s  %-41s  %s\n' "${ROWS_AGENT[$i]}" "${ROWS_DOC[$i]}" "${ROWS_STATUS[$i]}"
done

printf '\n'
printf 'Labels                  Status\n'
printf -- '----------------------  --------------------------------------------\n'
for i in "${!LABEL_NAMES[@]}"; do
  printf '%-22s  %s\n' "${LABEL_NAMES[$i]}" "${LABEL_STATUS[$i]}"
done

printf '\n'
printf 'Autopilot               Status\n'
printf -- '----------------------  --------------------------------------------\n'
printf '%-22s  %s\n' "config" "$autopilot_detail"

printf '\n'
printf 'Summary: %d ok, %d warn, %d missing.\n' "$OK_COUNT" "$WARN_COUNT" "$MISSING_COUNT"
if [[ "$EXIT_CODE" -eq 0 ]]; then
  printf 'Exit 0 — nothing to act on.\n'
else
  printf 'Exit 1 — at least one ✗ row needs attention. Run /bsg-stack init.\n'
fi

exit "$EXIT_CODE"
