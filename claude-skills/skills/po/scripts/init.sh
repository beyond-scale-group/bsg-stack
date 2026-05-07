#!/usr/bin/env bash
# init.sh — bootstrap `.bsg/PLAN.md` for a fresh repo.
#
# Implements `@po-manager init` (#237 deliverable #2). Wraps the
# existing bootstrap-plan.sh draft generator (#115) with the file-write
# + safety-check plumbing every agent's `--init` needs:
#
#   1. Refuse to clobber an existing PLAN.md unless `--force` is set
#   2. Resolve the destination via _bsg-paths.sh (.bsg/PLAN.md preferred,
#      legacy po/PLAN.md as fallback while the repo migrates)
#   3. Generate the draft from a fresh GraphQL snapshot
#   4. Write it to disk
#   5. Print follow-up instructions
#
# Pure file-write; never opens a PR or makes external changes. The
# agent or umbrella skill is responsible for the PR step (via
# open-report-pr.sh or `/bsg-stack init`).
#
# Usage:
#   bash claude-skills/skills/po/scripts/init.sh
#   bash claude-skills/skills/po/scripts/init.sh --force
#   bash claude-skills/skills/po/scripts/init.sh --dry-run
#   bash claude-skills/skills/po/scripts/init.sh --out .bsg/PLAN.md
#
# Flags:
#   --force      Overwrite an existing PLAN.md.
#   --dry-run    Print the draft to stdout, write nothing.
#   --out PATH   Override the destination. Default: result of
#                `bsg_doc_path plan` (.bsg/PLAN.md preferred).
#   --snapshot   Reuse an existing collect.sh snapshot instead of
#                fetching one. Forwarded to bootstrap-plan.sh.

set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$HERE/../../../.." && pwd)"

# shellcheck source=../../../scripts/_bsg-paths.sh disable=SC1091
source "$REPO_ROOT/claude-skills/scripts/_bsg-paths.sh"

force=0
dry_run=0
out=""
snapshot=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --force)    force=1;        shift ;;
    --dry-run)  dry_run=1;      shift ;;
    --out)      out="$2";       shift 2 ;;
    --snapshot) snapshot="$2";  shift 2 ;;
    -h|--help)
      sed -n '2,/^$/p' "$0" | sed 's/^# \?//'
      exit 0 ;;
    *)
      echo "init.sh: unknown argument: $1" >&2
      exit 2 ;;
  esac
done

if [[ -z "$out" ]]; then
  out="$(bsg_doc_path plan)"
fi

# Refuse to clobber an existing plan. The whole point of init is "fresh
# repo bootstrap" — if PLAN.md already exists, the user wants `update`,
# not `init`, and that's a different verb.
if [[ -f "$out" && $force -eq 0 && $dry_run -eq 0 ]]; then
  echo "init.sh: $out already exists. Pass --force to overwrite or run @po-manager update instead." >&2
  exit 3
fi

# Generate the draft. bootstrap-plan.sh emits markdown on stdout; we
# capture it before writing so an interrupted snapshot fetch doesn't
# leave a half-written file on disk.
draft_args=()
if [[ -n "$snapshot" ]]; then
  draft_args+=(--snapshot "$snapshot")
fi
draft="$(bash "$HERE/bootstrap-plan.sh" "${draft_args[@]}")"

if [[ $dry_run -eq 1 ]]; then
  printf '%s\n' "$draft"
  echo "" >&2
  echo "init.sh: --dry-run, would have written to $out" >&2
  exit 0
fi

mkdir -p "$(dirname "$out")"
printf '%s\n' "$draft" > "$out"

cat <<EOF >&2
init.sh: wrote $(wc -l <"$out" | tr -d ' ') lines to $out

Next steps:
  1. Review the draft — every bullet should carry at least one binding
     ([milestone:...], [epic:#N], [label:...]). See plan-schema.md.
  2. Replace the bootstrapped suggestions with your real objectives.
  3. Open it as a PR for review:
       bash claude-skills/scripts/open-report-pr.sh "$out" --agent po \\
         --title "init(po): bootstrap PLAN.md from milestones"

Or let \`/bsg-stack init\` orchestrate this and the other agents' inits
in a single sweep.
EOF

printf '%s\n' "$out"
