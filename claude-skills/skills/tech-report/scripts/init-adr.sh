#!/usr/bin/env bash
# init-adr.sh — generate a draft ADR 000 from repo scan.
#
# Part of #237 (per-agent --init contract): scans the repo for the
# primary language / framework, major dependencies, and the CI system,
# then emits a draft `.bsg/adr/000-record-architecture-decisions.md` to
# stdout. The tech-lead agent reads `.bsg/adr/` every tick to track
# architecture decisions.
#
# The orchestrator (`/bsg-stack init`) captures stdout and writes the
# file for human review — this script never writes to disk.
#
# Usage:
#   bash init-adr.sh
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

# ----------------------------------------------- signal collection

language="unknown"
framework=""
if [[ -f package.json ]]; then
  language="JavaScript / TypeScript (Node.js)"
  for fw in next react vue svelte @angular/core express fastify nestjs; do
    if jq -e --arg fw "$fw" '.dependencies[$fw] // .devDependencies[$fw]' package.json >/dev/null 2>&1; then
      framework="$fw"
      break
    fi
  done
elif [[ -f pyproject.toml || -f setup.py || -f requirements.txt ]]; then
  language="Python"
  grep -hiE 'django|flask|fastapi' pyproject.toml setup.py requirements.txt 2>/dev/null | head -1 \
    | grep -ioE 'django|flask|fastapi' | head -1 | tr '[:upper:]' '[:lower:]' \
    | { read -r fw || true; framework="$fw"; }
elif [[ -f Cargo.toml ]]; then
  language="Rust"
elif [[ -f go.mod ]]; then
  language="Go"
elif [[ -f pom.xml || -f build.gradle || -f build.gradle.kts ]]; then
  language="Java / JVM"
fi

ci_system="none detected"
if [[ -d .github/workflows ]]; then
  ci_system="GitHub Actions (.github/workflows/)"
elif [[ -f .gitlab-ci.yml ]]; then
  ci_system="GitLab CI (.gitlab-ci.yml)"
elif [[ -f .circleci/config.yml ]]; then
  ci_system="CircleCI (.circleci/config.yml)"
elif [[ -f Jenkinsfile ]]; then
  ci_system="Jenkins (Jenkinsfile)"
fi

# ----------------------------------------------- emit

cat <<DOC
# ADR 000 — Record architecture decisions

- **Status:** accepted
- **Date:** ${today}
- **Drafted by:** \`/bsg-stack init\` (tech-lead --init) — review before committing

## Context

This repository did not yet record its architecture decisions in a
structured way. The tech-lead agent reads \`.bsg/adr/\` every tick to
track and audit technical decisions; an initial ADR log is required for
it to produce useful output.

The following signals were detected from the repository on ${today}:

| Signal | Detected value |
|---|---|
| Primary language | ${language} |
| Framework | ${framework:-_none detected — fill in manually_} |
| CI system | ${ci_system} |

## Decision

We will document architecture decisions as Markdown files under
\`.bsg/adr/\`, one file per decision, numbered sequentially
(\`000-...\`, \`001-...\`). Each ADR records context, the decision, and
its consequences. Superseded ADRs stay in place with their status
updated rather than being deleted.

## Consequences

- New significant technical decisions get an ADR before or alongside
  the change that introduces them.
- The tech-lead agent can cross-reference code changes against recorded
  decisions and flag drift.
- _Replace the seeded signals above with the real architecture context
  (key dependencies, runtime targets, data stores) and add follow-up
  ADRs (\`001-...\`) for the decisions that already shaped this repo._
DOC
