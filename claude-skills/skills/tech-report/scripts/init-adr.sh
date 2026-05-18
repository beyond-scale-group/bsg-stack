#!/usr/bin/env bash
# init-adr.sh — generate a draft bootstrap ADR from repo scan.
#
# Part of #237 (per-agent --init contract): scans the repo for
# architecture signals — primary language/ecosystem, major
# dependencies, and CI setup — then emits a draft first ADR
# (`.bsg/adr/001-bootstrap.md`) to stdout. The orchestrator
# (`/bsg-stack init`) captures stdout and opens a PR for human
# review — this script never writes to disk.
#
# Usage:
#   bash init-adr.sh                # auto-scan current repo
#   bash init-adr.sh --repo OWNER/NAME
#
# Exit 0 + content on stdout: success
# Exit 1: error (missing tool, etc.)

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
description=""
if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
  meta=$(gh repo view "${REPO_FLAG[@]}" --json name,description 2>/dev/null || echo '{}')
  repo_name=$(jq -r '.name // "unknown"' <<<"$meta" 2>/dev/null || echo unknown)
  description=$(jq -r '.description // ""' <<<"$meta" 2>/dev/null || echo "")
fi

# Detect ecosystem(s) from manifest files at repo root.
ecosystems=()
[[ -f package.json ]]      && ecosystems+=("Node.js (package.json)")
[[ -f requirements.txt ]]  && ecosystems+=("Python (requirements.txt)")
[[ -f pyproject.toml ]]    && ecosystems+=("Python (pyproject.toml)")
[[ -f go.mod ]]            && ecosystems+=("Go (go.mod)")
[[ -f Cargo.toml ]]        && ecosystems+=("Rust (Cargo.toml)")
[[ -f pom.xml ]]           && ecosystems+=("Java (Maven)")
[[ -f Gemfile ]]           && ecosystems+=("Ruby (Gemfile)")
[[ -f composer.json ]]     && ecosystems+=("PHP (composer.json)")

# Top runtime dependencies (best-effort, first few).
deps=""
if [[ -f package.json ]] && command -v jq >/dev/null 2>&1; then
  deps=$(jq -r '(.dependencies // {}) | keys[]' package.json 2>/dev/null | head -10 || echo "")
elif [[ -f requirements.txt ]]; then
  deps=$(grep -vE '^\s*#|^\s*$' requirements.txt 2>/dev/null \
    | sed -E 's/[<>=!~].*//' | head -10 || echo "")
fi

# CI setup.
ci="none detected"
if [[ -d .github/workflows ]]; then
  wf_count=$(find .github/workflows -maxdepth 1 -type f \
    \( -name '*.yml' -o -name '*.yaml' \) 2>/dev/null | wc -l | tr -d ' ')
  ci="GitHub Actions (${wf_count} workflow(s))"
elif [[ -f .gitlab-ci.yml ]]; then
  ci="GitLab CI"
elif [[ -f .circleci/config.yml ]]; then
  ci="CircleCI"
fi

# ----------------------------------------------- emit

cat <<HEAD
# 001 — Bootstrap architecture record

_Draft bootstrapped ${today}. Review, correct, and commit to
\`.bsg/adr/001-bootstrap.md\` — the tech-lead agent reads \`.bsg/adr/\`
every tick to flag undocumented decisions. Split into focused ADRs
(\`002-…\`, \`003-…\`) as decisions accumulate._

## Status

Proposed — needs human review.

## Context

HEAD

if [[ -n "$description" ]]; then
  echo "Repository: **${repo_name}** — ${description}"
else
  echo "Repository: **${repo_name}**"
fi

echo ""
echo "### Detected stack"
echo ""
if [[ ${#ecosystems[@]} -gt 0 ]]; then
  for e in "${ecosystems[@]}"; do echo "- ${e}"; done
else
  echo "- _No package manifest detected at repo root — document the stack manually._"
fi

echo ""
echo "### CI / automation"
echo ""
echo "- ${ci}"

echo ""
echo "### Notable dependencies"
echo ""
if [[ -n "$deps" ]]; then
  while IFS= read -r d; do
    [[ -n "$d" ]] && echo "- ${d}"
  done <<<"$deps"
else
  echo "- _None inventoried — list the load-bearing libraries here._"
fi

cat <<'TAIL'

## Decision

_Document the key architectural decision(s) already implicit in this
codebase: framework choice, persistence, deployment target, language
boundaries. One ADR per decision once the backlog grows._

## Consequences

_What does this decision make easy? What does it make hard? What are
the migration costs if it is reversed later?_
TAIL
