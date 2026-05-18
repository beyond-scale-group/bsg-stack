#!/usr/bin/env bash
# init-adr.sh — generate a starter architecture-baseline ADR from repo scan.
#
# Part of #237 (per-agent --init contract): scans the repo for stack
# signals — primary language, major dependency manifests, and CI
# workflows — then emits a draft architecture-baseline ADR to stdout.
# The orchestrator (`/bsg-stack init`) captures stdout and writes it to
# `.bsg/adr/000-architecture-baseline.md`, then opens a PR for human
# review. This script never writes to disk.
#
# Usage:
#   bash init-adr.sh                # auto-scan current repo
#   bash init-adr.sh --repo OWNER/NAME
#
# Exit 0 + content on stdout: success
# Exit 0 + minimal stub on stdout: no strong signals found
# Exit 1: error (missing tool, no gh auth, etc.)

set -euo pipefail

REPO_FLAG=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) REPO_FLAG=(--repo "$2"); shift 2 ;;
    -h|--help) sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "init-adr.sh: unknown arg: $1" >&2; exit 2 ;;
  esac
done

REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
cd "$REPO_ROOT"

today=$(date -u +%F)

# ----------------------------------------------- signal collection

repo_name="unknown"
if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
  repo_name=$(gh repo view "${REPO_FLAG[@]}" --json name --jq '.name' 2>/dev/null || echo "unknown")
fi
if [[ "$repo_name" == "unknown" || -z "$repo_name" ]]; then
  repo_name=$(basename "$REPO_ROOT")
fi

# Detect dependency manifests → infer the primary stack.
declare -a manifests
[[ -f package.json ]]      && manifests+=("Node.js / npm (package.json)")
[[ -f requirements.txt ]]  && manifests+=("Python (requirements.txt)")
[[ -f pyproject.toml ]]    && manifests+=("Python (pyproject.toml)")
[[ -f go.mod ]]            && manifests+=("Go (go.mod)")
[[ -f Cargo.toml ]]        && manifests+=("Rust (Cargo.toml)")
[[ -f composer.json ]]     && manifests+=("PHP (composer.json)")
[[ -f Gemfile ]]           && manifests+=("Ruby (Gemfile)")
[[ -f pom.xml ]]           && manifests+=("Java / Maven (pom.xml)")

# A few headline dependencies from package.json, if present.
declare -a deps
if [[ -f package.json ]] && command -v jq >/dev/null 2>&1; then
  while IFS= read -r d; do
    [[ -n "$d" ]] && deps+=("$d")
  done < <(jq -r '(.dependencies // {}) | keys[]' package.json 2>/dev/null | head -8)
fi

# CI workflows.
declare -a workflows
if [[ -d .github/workflows ]]; then
  while IFS= read -r wf; do
    workflows+=("$(basename "$wf")")
  done < <(find .github/workflows -maxdepth 1 -type f \( -name '*.yml' -o -name '*.yaml' \) 2>/dev/null | sort | head -10)
fi

# ----------------------------------------------- emit

cat <<HEAD
# ADR-000 — Architecture baseline (${repo_name})

_Draft bootstrapped ${today}. This is a **starting point**, not a
decision record yet. Review the detected signals below, correct them,
and split distinct decisions into their own numbered ADRs
(\`.bsg/adr/001-*.md\`, …). The tech-lead agent reads this directory
every tick to detect undocumented decisions._

- **Status:** draft (auto-bootstrapped)
- **Date:** ${today}
- **Deciders:** _add the humans who own these decisions_

## Context

This baseline captures the stack as it exists today so future ADRs
have a reference point. Replace the inferred notes below with the
real architectural context.

## Detected stack
HEAD

if [[ ${#manifests[@]} -gt 0 ]]; then
  printf '\n'
  for m in "${manifests[@]}"; do echo "- $m"; done
else
  printf '\n- _No dependency manifest detected — document the stack manually._\n'
fi

if [[ ${#deps[@]} -gt 0 ]]; then
  printf '\n### Headline dependencies\n\n'
  for d in "${deps[@]}"; do echo "- \`$d\`"; done
fi

printf '\n## CI / automation\n\n'
if [[ ${#workflows[@]} -gt 0 ]]; then
  for w in "${workflows[@]}"; do echo "- \`.github/workflows/$w\`"; done
else
  echo "- _No GitHub Actions workflows detected._"
fi

cat <<'TAIL'

## Decision

_Record the first real architectural decision here, or delete this
ADR-000 once the genuine ADRs (001, 002, …) cover the ground. Each
ADR should state one decision, its alternatives, and its consequences._

## Consequences

_What becomes easier or harder because of the baseline above._
TAIL
