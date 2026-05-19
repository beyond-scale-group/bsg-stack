#!/usr/bin/env bash
# init.sh — bootstrap the .bsg/ directory for a fresh repo.
#
# Orchestrates the per-agent --init scripts shipped under
# `claude-skills/skills/<skill>/scripts/init-*.sh` to create a complete
# .bsg/ tree in one shot. Each per-agent init script is responsible
# for its own scan + draft logic; this orchestrator routes the calls
# and writes the output files.
#
# Per ADR-002 this verb is NOT read-only: it creates files and may
# create GitHub labels via `gh`. Always run interactively with consent.
#
# What this does, in order:
#
#   1. Create .bsg/ skeleton (reports/<bus>/ subdirs, adr/, brand/)
#   2. For each agent with an init script, run it and capture output
#      to the expected .bsg/<DOC> path. Skip agents whose doc already
#      exists (idempotent — safe to re-run).
#   3. Bootstrap missing GitHub labels from agents/registry.json plus
#      the `needs-human-review` / `human-reviewed` pair.
#   4. Drop a disabled .bsg/AUTOPILOT.yml scaffold if neither the new
#      nor legacy autopilot file exists.
#   5. Print a summary of what was created.
#
# This is intentionally a one-shot bootstrap. The orchestrator does not
# open a PR — it leaves the .bsg/ tree dirty for the human to review,
# edit, and commit. The `/bsg-stack doctor` verb can then verify the
# repo is healthy.
#
# Usage:
#   bash init.sh                 # full bootstrap with prompts skipped
#   bash init.sh --dry-run       # print what would happen, change nothing
#   bash init.sh --no-labels     # skip GitHub label creation
#   bash init.sh --skip <agent>  # skip a specific agent's init (repeatable)
#
# Exit 0 on success, non-zero on real failure (missing catalog,
# permission errors). Individual per-agent failures are reported but
# don't fail the whole bootstrap.

set -euo pipefail

DRY_RUN=0
NO_LABELS=0
declare -a SKIP_AGENTS

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)    DRY_RUN=1; shift ;;
    --no-labels)  NO_LABELS=1; shift ;;
    --skip)       SKIP_AGENTS+=("$2"); shift 2 ;;
    -h|--help)    sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "init.sh: unknown arg: $1" >&2; exit 2 ;;
  esac
done

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$REPO_ROOT"

# Locate the catalog — walk up from this script.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CATALOG_DIR="$(cd "$SCRIPT_DIR/../../.." && pwd)"
REGISTRY="$CATALOG_DIR/agents/registry.json"

if [[ ! -f "$REGISTRY" ]]; then
  echo "init.sh: cannot find agents/registry.json (looked in $CATALOG_DIR)" >&2
  exit 2
fi

# ---------------------------------------------------------------- helpers

would() {
  if [[ "$DRY_RUN" == "1" ]]; then printf 'would: %s\n' "$1"
  else printf '%s\n'        "$1"
  fi
}

is_skipped() {
  local agent="$1"
  for s in "${SKIP_AGENTS[@]:-}"; do
    [[ "$s" == "$agent" ]] && return 0
  done
  return 1
}

# Map agent name → its init script path relative to the catalog.
init_script_for() {
  case "$1" in
    po-manager)    echo "skills/po/scripts/init-plan.sh" ;;
    seo)           echo "skills/seo-report/scripts/init-keywords.sh" ;;
    marketing)     echo "skills/marketing-report/scripts/init-calendar.sh" ;;
    pr-comms)      echo "skills/pr-comms-report/scripts/init-announced.sh" ;;
    security)      echo "skills/security-report/scripts/init-securityignore.sh" ;;
    storytelling)  echo "skills/storytelling-report/scripts/init-narrative.sh" ;;
    tech-lead)     echo "skills/tech-report/scripts/init-adr.sh" ;;
    qa)            echo "skills/qa-report/scripts/init-qa-baseline.sh" ;;
    *)             echo "" ;;
  esac
}

# Map agent name → its expected output path under .bsg/.
output_path_for() {
  case "$1" in
    po-manager)    echo ".bsg/PLAN.md" ;;
    seo)           echo ".bsg/KEYWORDS.md" ;;
    marketing)     echo ".bsg/CALENDAR.md" ;;
    pr-comms)      echo ".bsg/ANNOUNCED.md" ;;
    security)      echo ".bsg/SECURITYIGNORE" ;;
    storytelling)  echo ".bsg/NARRATIVE.md" ;;
    tech-lead)     echo ".bsg/adr/0000-architecture-baseline.md" ;;
    qa)            echo ".bsg/reports/qa/0000-baseline.md" ;;
    *)             echo "" ;;
  esac
}

# ---------------------------------------------------------------- step 1: skeleton

echo ""
echo "Step 1/4 — Creating .bsg/ skeleton"
echo "==================================="

SKELETON_DIRS=(
  ".bsg"
  ".bsg/adr"
  ".bsg/brand"
  ".bsg/brand/templates"
  ".bsg/reports"
)
# One reports subdir per registered agent's bus label.
while IFS= read -r bus; do
  SKELETON_DIRS+=(".bsg/reports/$bus")
done < <(jq -r '.agents[].bus_label' "$REGISTRY")

for d in "${SKELETON_DIRS[@]}"; do
  if [[ -d "$d" ]]; then
    echo "  ✓ exists: $d"
  else
    would "  create: $d"
    [[ "$DRY_RUN" == "0" ]] && mkdir -p "$d"
  fi
done

# ---------------------------------------------------------------- step 2: per-agent init

echo ""
echo "Step 2/4 — Running per-agent --init scripts"
echo "==========================================="

CREATED_COUNT=0
SKIPPED_COUNT=0
FAILED_COUNT=0

while IFS= read -r name; do
  if is_skipped "$name"; then
    echo "  ⊘ skip:    $name (explicit --skip)"
    SKIPPED_COUNT=$((SKIPPED_COUNT + 1))
    continue
  fi

  script_rel="$(init_script_for "$name")"
  output_path="$(output_path_for "$name")"

  if [[ -z "$script_rel" || -z "$output_path" ]]; then
    echo "  ⊘ no-init: $name (no --init script registered yet)"
    SKIPPED_COUNT=$((SKIPPED_COUNT + 1))
    continue
  fi

  script_abs="$CATALOG_DIR/$script_rel"
  if [[ ! -f "$script_abs" ]]; then
    # Fall back to cached install.
    script_abs="$HOME/.claude/$script_rel"
  fi
  if [[ ! -f "$script_abs" ]]; then
    echo "  ✗ missing script for $name: $script_rel"
    FAILED_COUNT=$((FAILED_COUNT + 1))
    continue
  fi

  if [[ -f "$output_path" ]]; then
    echo "  ✓ keeps:   $output_path (already present)"
    SKIPPED_COUNT=$((SKIPPED_COUNT + 1))
    continue
  fi

  would "  create:  $output_path  ← bash $script_rel"
  if [[ "$DRY_RUN" == "0" ]]; then
    if content="$(bash "$script_abs" 2>/dev/null)" && [[ -n "$content" ]]; then
      mkdir -p "$(dirname "$output_path")"
      printf '%s\n' "$content" > "$output_path"
      CREATED_COUNT=$((CREATED_COUNT + 1))
    else
      echo "    └─ ✗ script produced no output; nothing written"
      FAILED_COUNT=$((FAILED_COUNT + 1))
    fi
  fi
done < <(jq -r '.agents[].name' "$REGISTRY")

# ---------------------------------------------------------------- step 3: labels

echo ""
echo "Step 3/4 — Bootstrapping GitHub labels"
echo "======================================"

if [[ "$NO_LABELS" == "1" ]]; then
  echo "  ⊘ skip (--no-labels)"
elif ! command -v gh >/dev/null 2>&1 || ! gh auth status >/dev/null 2>&1; then
  echo "  ⚠ gh CLI unavailable or not authenticated — skipping label bootstrap"
else
  REQUIRED_LABELS=("needs-human-review" "human-reviewed")
  while IFS= read -r bus; do REQUIRED_LABELS+=("$bus"); done < <(jq -r '.agents[].bus_label' "$REGISTRY")

  EXISTING=$(gh label list --limit 200 --json name --jq '.[].name' 2>/dev/null || echo "")
  for lbl in "${REQUIRED_LABELS[@]}"; do
    if grep -qx "$lbl" <<<"$EXISTING"; then
      echo "  ✓ exists:  $lbl"
    else
      would "  create:  $lbl"
      if [[ "$DRY_RUN" == "0" ]]; then
        # Pick a sensible color per category.
        case "$lbl" in
          needs-human-review) color="fbca04"; desc="Awaiting a human decision (triage, merge, or scope)" ;;
          human-reviewed)     color="0e8a16"; desc="A human has made a disposition decision" ;;
          *)                  color="5319e7"; desc="Owned by @$lbl (agent bus label)" ;;
        esac
        gh label create "$lbl" --color "$color" --description "$desc" >/dev/null 2>&1 \
          || echo "    └─ ✗ failed to create label $lbl (may already exist with different case)"
      fi
    fi
  done
fi

# ---------------------------------------------------------------- step 4: autopilot scaffold

echo ""
echo "Step 4/4 — Autopilot config scaffold"
echo "====================================="

if [[ -f .bsg/AUTOPILOT.yml ]]; then
  echo "  ✓ exists: .bsg/AUTOPILOT.yml"
elif [[ -f .bsg-autopilot.yml ]]; then
  echo "  ⚠ legacy: .bsg-autopilot.yml — consider renaming to .bsg/AUTOPILOT.yml"
else
  would "  create: .bsg/AUTOPILOT.yml (disabled — edit to enable)"
  if [[ "$DRY_RUN" == "0" ]]; then
    cat > .bsg/AUTOPILOT.yml <<'YAML'
# .bsg/AUTOPILOT.yml — repo-level opt-in for auto-implementation.
#
# When `enabled: true` and the calling agent is listed under `agents:`,
# the agent's tick will pick up eligible issues and attempt one fix per
# sweep (subject to the per-issue budget). See CLAUDE.md → "Autopilot
# mode" for the full schema and semantics.
#
# This scaffold ships disabled — flip `enabled` to `true` and add agent
# bus labels under `agents:` when you're ready.

enabled: false
agents: []
budget:
  max_prs_per_tick: 3
  max_prs_per_day: 200
  max_loc_per_issue: 200
  max_files_per_issue: 8
YAML
  fi
fi

# ---------------------------------------------------------------- summary

echo ""
echo "Summary"
echo "======="
echo "  Created: $CREATED_COUNT custom doc(s)"
echo "  Kept:    $SKIPPED_COUNT (already present or no script registered)"
echo "  Failed:  $FAILED_COUNT"
echo ""
if [[ "$DRY_RUN" == "1" ]]; then
  echo "Dry-run complete — no files written. Re-run without --dry-run to apply."
elif [[ "$CREATED_COUNT" -gt 0 ]]; then
  echo "Next steps:"
  echo "  1. Review the generated files under .bsg/"
  echo "  2. Edit and replace _placeholder_ text where needed"
  echo "  3. git add .bsg/ && git commit"
  echo "  4. Run /bsg-stack doctor to verify the setup"
else
  echo "Nothing to write — repo already has its .bsg/ tree set up."
  echo "Run /bsg-stack doctor to check current health."
fi
