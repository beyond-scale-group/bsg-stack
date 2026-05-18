#!/usr/bin/env bash
# init-adr.sh — generate a draft baseline ADR from repo scan.
#
# Part of #237 (per-agent --init contract): scans the repo for
# architecture signals — primary language / build tooling, major
# dependencies, CI setup, containerization — and emits a draft
# `.bsg/adr/000-architecture-baseline.md` to stdout. The tech-lead
# agent reads `.bsg/adr/` every tick to track which technical
# decisions are documented.
#
# The orchestrator (`/bsg-stack init`) captures stdout and writes it
# to `.bsg/adr/000-architecture-baseline.md` for human review — this
# script never writes to disk.
#
# Usage:
#   bash init-adr.sh           # auto-scan current repo
#
# Exit 0 + content on stdout: success
# Exit 1: error

set -euo pipefail

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help) sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "init-adr.sh: unknown arg: $1" >&2; exit 2 ;;
  esac
done

REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
cd "$REPO_ROOT"

today=$(date -u +%F)

repo_name=$(basename "$REPO_ROOT")
if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
  repo_name=$(gh repo view --json name --jq '.name // empty' 2>/dev/null || echo "$repo_name")
fi

# ----------------------------------------------- signals: build tooling
#
# Accumulate detected stack as newline-delimited text rather than a bash
# array — referencing an empty array under `set -u` is an "unbound
# variable" error on bash < 4.4, which the orchestrator may run on.

stack=""
add_stack() {
  case $'\n'"$stack"$'\n' in
    *$'\n'"$1"$'\n'*) return ;;
  esac
  stack="${stack:+$stack$'\n'}$1"
}

[[ -f package.json ]]       && add_stack "Node.js / npm (package.json)"
[[ -f pnpm-lock.yaml ]]     && add_stack "pnpm workspace"
[[ -f yarn.lock ]]          && add_stack "Yarn"
[[ -f build.sbt ]]          && add_stack "Scala / sbt (build.sbt)"
[[ -f pom.xml ]]            && add_stack "Java / Maven (pom.xml)"
{ [[ -f build.gradle ]] || [[ -f build.gradle.kts ]]; } && add_stack "Gradle"
[[ -f requirements.txt ]]   && add_stack "Python (requirements.txt)"
[[ -f pyproject.toml ]]     && add_stack "Python (pyproject.toml)"
[[ -f go.mod ]]             && add_stack "Go modules (go.mod)"
[[ -f Cargo.toml ]]         && add_stack "Rust / Cargo (Cargo.toml)"
[[ -f Gemfile ]]            && add_stack "Ruby / Bundler (Gemfile)"
[[ -f composer.json ]]      && add_stack "PHP / Composer (composer.json)"
[[ -f Dockerfile ]]         && add_stack "Docker (Dockerfile)"
{ [[ -f docker-compose.yml ]] || [[ -f docker-compose.yaml ]]; } && add_stack "Docker Compose"

# ----------------------------------------------- signals: major deps

deps=""
if [[ -f package.json ]] && command -v jq >/dev/null 2>&1; then
  deps=$(jq -r '(.dependencies // {}) | keys[]' package.json 2>/dev/null \
    | head -12 | awk '{print "- " $0}' || echo "")
fi

# ----------------------------------------------- signals: CI

ci_workflows=""
if [[ -d .github/workflows ]]; then
  ci_workflows=$(find .github/workflows -maxdepth 1 -type f \
    \( -name '*.yml' -o -name '*.yaml' \) 2>/dev/null \
    | sed 's#.*/#- #' | sort | head -15 || echo "")
fi

# ----------------------------------------------- emit

cat <<HEAD
# ADR 000 — Architecture baseline (${repo_name})

_Draft bootstrapped ${today}. This is a starting point, not a decision
record. Edit and commit to \`.bsg/adr/000-architecture-baseline.md\`,
then author follow-up ADRs (\`001-*.md\`, \`002-*.md\`, …) for each
real decision. The tech-lead agent reads \`.bsg/adr/\` every tick to
flag undocumented architectural changes._

## Status

Proposed — replace with Accepted once a human has reviewed and
corrected the inferred stack below.

## Context

This ADR captures the technical baseline detected from the repository
so future decisions have a documented starting point.

### Detected stack

HEAD

if [[ -n "$stack" ]]; then
  printf '%s\n' "$stack" | sed 's/^/- /'
else
  echo "- _No build tooling detected — describe the stack manually._"
fi

if [[ -n "$deps" ]]; then
  cat <<'DEPS_HEADER'

### Major dependencies (top of package.json)

DEPS_HEADER
  printf '%s\n' "$deps"
fi

if [[ -n "$ci_workflows" ]]; then
  cat <<'CI_HEADER'

### CI workflows

CI_HEADER
  printf '%s\n' "$ci_workflows"
else
  cat <<'NO_CI'

### CI workflows

- _No GitHub Actions workflows detected under .github/workflows._
NO_CI
fi

cat <<'TAIL'

## Decision

_None yet — this baseline only records what exists. Document the first
real architectural decision in a new ADR file._

## Consequences

_Fill in as decisions are made. The tech-lead agent cross-references
this directory against detected architecture drift on each tick._
TAIL
