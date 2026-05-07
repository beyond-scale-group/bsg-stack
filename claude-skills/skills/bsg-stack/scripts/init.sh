#!/usr/bin/env bash
# init.sh — first-time bootstrap of `.bsg/` agent infrastructure.
#
# Implements the `init` verb of /bsg-stack per ADR-002 (write verbs are
# separate from read-only verbs). Touches the filesystem and the
# GitHub label set. Does NOT open PRs — the caller (or the chat
# session) opens one PR per generated file via open-report-pr.sh so
# each addition is reviewable.
#
# Behavior, per agent in registry.json:
#   1. Read the agent's `custom-doc:` and `init:` frontmatter
#   2. If the custom-doc already exists on disk → skip (this is `init`,
#      not `update`)
#   3. Otherwise, call the per-agent init script if one exists.
#      Today only md-to-office (init-brand.sh) and po-manager
#      (po/scripts/init.sh) have concrete scripts. Agents without a
#      script get a stub TODO file so the human knows what to author.
#
# Plus:
#   - Ensure `.bsg/` skeleton exists (creates missing subdirs)
#   - Bootstrap required GitHub labels (needs-human-review,
#     human-reviewed, every bus label from registry.json) — idempotent
#
# Usage:
#   bash claude-skills/skills/bsg-stack/scripts/init.sh
#   bash claude-skills/skills/bsg-stack/scripts/init.sh --dry-run
#   bash claude-skills/skills/bsg-stack/scripts/init.sh --skip-labels
#   bash claude-skills/skills/bsg-stack/scripts/init.sh --only po,seo
#
# Flags:
#   --dry-run       Print what would be done; touch nothing.
#   --skip-labels   Do not touch GitHub labels (file-only bootstrap).
#   --only LIST     Comma-separated list of bus labels to init (default:
#                   all agents in registry.json).
#   --force         Overwrite existing custom-docs. Off by default;
#                   `init` is for fresh repos. Use /bsg-stack update
#                   for refresh.
#
# Exit codes:
#   0  — every requested action succeeded (or was a no-op)
#   1  — at least one per-agent init failed
#   2  — bad usage

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CATALOG_DIR="$(cd "$SCRIPT_DIR/../../.." && pwd)"
REGISTRY="$CATALOG_DIR/agents/registry.json"

# shellcheck source=../../../scripts/_bsg-paths.sh disable=SC1091
source "$CATALOG_DIR/scripts/_bsg-paths.sh"

DRY_RUN=0
SKIP_LABELS=0
FORCE=0
ONLY=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)     DRY_RUN=1;     shift ;;
    --skip-labels) SKIP_LABELS=1; shift ;;
    --only)        ONLY="$2";     shift 2 ;;
    --force)       FORCE=1;       shift ;;
    -h|--help)
      sed -n '2,/^$/p' "$0" | sed 's/^# \?//'
      exit 0 ;;
    *) echo "init.sh: unknown flag: $1" >&2; exit 2 ;;
  esac
done

if [[ ! -f "$REGISTRY" ]]; then
  echo "init.sh: cannot find agents/registry.json (looked in $CATALOG_DIR)" >&2
  exit 2
fi

note() { printf '  %s\n' "$*"; }
say()  { printf '%s\n' "$*"; }
do_or_print() {
  if [[ $DRY_RUN -eq 1 ]]; then
    note "[dry-run] $*"
  else
    eval "$@"
  fi
}

# ---------------------------------------------------------------- skeleton

ensure_skeleton() {
  local subdirs=(
    .bsg
    .bsg/adr
    .bsg/brand
    .bsg/brand/templates
    .bsg/reports
    .bsg/reports/po
    .bsg/reports/qa
    .bsg/reports/tech
    .bsg/reports/seo
    .bsg/reports/marketing
    .bsg/reports/security
    .bsg/reports/storytelling
    .bsg/reports/comms
    .bsg/reports/cleaner
  )
  say "→ Ensuring .bsg/ skeleton"
  for d in "${subdirs[@]}"; do
    if [[ ! -d "$d" ]]; then
      do_or_print "mkdir -p '$d'"
      note "created: $d"
    fi
  done
}

# ---------------------------------------------------------------- per-agent init

# Map agent name → init script path (relative to catalog_dir). Empty
# means "no script yet; we leave a TODO stub instead."
init_script_for() {
  case "$1" in
    po-manager)   echo "skills/po/scripts/init.sh" ;;
    md-to-office) echo "skills/md-to-office/scripts/init-brand.sh" ;;
    *)            echo "" ;;
  esac
}

# What `custom-doc:` does the agent declare? Returns the path through
# the resolver so partial migrations resolve cleanly.
custom_doc_for() {
  local name="$1"
  awk -F': *' '/^custom-doc:/ {print $2; exit}' "$CATALOG_DIR/agents/$name.md"
}

bootstrap_doc_stub() {
  local name="$1" doc="$2"
  cat <<EOF >"$doc"
# TODO: ${name} custom-doc

This file is an init stub. The ${name} agent does not yet ship its own
\`--init\` generator (#237 deliverable #2 is mid-rollout).

Until then, author this file by hand. See:

- \`claude-skills/agents/${name}.md\` frontmatter \`init:\` field for
  what this agent expects to find here
- \`claude-skills/MIGRATION-bsg-paths.md\` for the directory convention
- The PR that closes #237 deliverable #2 for ${name} will replace this
  stub with a generated draft

To remove this stub, replace its content with the real custom-doc and
commit. The next agent tick will pick it up.
EOF
}

run_agent_init() {
  local name="$1" custom_doc script
  custom_doc="$(custom_doc_for "$name")"
  script="$(init_script_for "$name")"

  if [[ -z "$custom_doc" ]]; then
    note "$name: no custom-doc declared, skipping"
    return 0
  fi

  # Resolve through _bsg-paths.sh so we honor partial migrations.
  # custom-doc: in frontmatter is already a `.bsg/` path, so the
  # resolver returns it directly when nothing else exists.
  local target
  if [[ "$custom_doc" == .bsg/* ]]; then
    target="$custom_doc"
  else
    target="$custom_doc"
  fi

  if [[ -e "$target" && $FORCE -eq 0 ]]; then
    note "$name: $target already exists — skipping (use --force or /bsg-stack update)"
    return 0
  fi

  if [[ -n "$script" && -f "$CATALOG_DIR/$script" ]]; then
    note "$name: running $script"
    if [[ $DRY_RUN -eq 1 ]]; then
      note "  [dry-run] would run: bash $CATALOG_DIR/$script"
    else
      local force_flag=""
      [[ $FORCE -eq 1 ]] && force_flag="--force"
      if ! bash "$CATALOG_DIR/$script" $force_flag; then
        note "$name: init script exited non-zero"
        return 1
      fi
    fi
    return 0
  fi

  # No per-agent init script. Two cases:
  #   - file-style custom-doc (.bsg/PLAN.md) → write a TODO stub
  #   - dir-style  custom-doc (.bsg/adr/, .bsg/reports/qa/) → ensure
  #     the directory exists; the agent owns its contents
  if [[ "$target" == */ || "$target" == *.bsg/adr || "$target" == *.bsg/reports/* ]]; then
    note "$name: no init script yet — ensuring directory $target"
    if [[ $DRY_RUN -eq 1 ]]; then
      note "  [dry-run] would mkdir -p $target"
    else
      mkdir -p "$target"
    fi
  else
    note "$name: no init script yet — writing TODO stub at $target"
    if [[ $DRY_RUN -eq 1 ]]; then
      note "  [dry-run] would write stub to $target"
    else
      mkdir -p "$(dirname "$target")"
      bootstrap_doc_stub "$name" "$target"
    fi
  fi
}

# ---------------------------------------------------------------- labels

ensure_labels() {
  if [[ $SKIP_LABELS -eq 1 ]]; then
    note "labels: --skip-labels, leaving GitHub label set untouched"
    return 0
  fi
  if ! command -v gh >/dev/null 2>&1; then
    note "labels: gh CLI not found — skipping label bootstrap"
    return 0
  fi
  if ! gh auth status >/dev/null 2>&1; then
    note "labels: gh not authenticated — skipping label bootstrap"
    return 0
  fi

  say "→ Ensuring GitHub labels"
  local existing
  existing="$(gh label list --limit 200 --json name --jq '.[].name' 2>/dev/null || echo "")"

  ensure_label() {
    local lbl="$1" color="$2" desc="$3"
    if grep -qx "$lbl" <<<"$existing"; then
      note "label '$lbl': ✓ exists"
    else
      do_or_print "gh label create '$lbl' --color '$color' --description '$desc'"
      note "label '$lbl': created"
    fi
  }

  ensure_label "needs-human-review" "fbca04" "Awaiting a human decision (triage, merge, or scope)"
  ensure_label "human-reviewed"     "0e8a16" "A human has made a disposition decision on this item"

  while IFS= read -r bus; do
    ensure_label "$bus" "5319e7" "Owned by @$bus (agent bus label from registry.json)"
  done < <(jq -r '.agents[].bus_label' "$REGISTRY")
}

# ---------------------------------------------------------------- main

say "/bsg-stack init"
if [[ $DRY_RUN -eq 1 ]]; then
  say "(dry-run mode — no files will be written, no labels created)"
fi
say ""

ensure_skeleton
say ""

say "→ Per-agent init"

# Filter agents by --only if set.
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
  if ! run_agent_init "$name"; then
    failed=$((failed + 1))
  fi
done
say ""

ensure_labels
say ""

if [[ $failed -gt 0 ]]; then
  say "✗ $failed per-agent init(s) failed — see notes above"
  exit 1
fi

say "✓ /bsg-stack init complete"
if [[ $DRY_RUN -eq 1 ]]; then
  say "  Re-run without --dry-run to apply."
fi
say "  Next: review the generated files, then commit and PR them."
