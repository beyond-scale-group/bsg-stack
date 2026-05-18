#!/usr/bin/env bash
# init-adr.sh — generate a draft bootstrap ADR from repo scan.
#
# Part of #237 (per-agent --init contract): detects the repo's primary
# language/framework, build tooling, and CI system, then emits a draft
# `000-record-architecture-decisions.md` ADR to stdout. The tech-lead
# agent reads `.bsg/adr/` every tick; this seed gives a fresh repo a
# starting decision log instead of an empty directory.
#
# The orchestrator (`/bsg-stack init`) captures stdout and writes it to
# `.bsg/adr/000-record-architecture-decisions.md` — this script never
# writes to disk.
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
build_tool="unknown"
if [[ -f package.json ]]; then
  language="JavaScript/TypeScript (Node.js)"
  build_tool="npm/package.json"
  [[ -f tsconfig.json ]] && language="TypeScript (Node.js)"
elif [[ -f pyproject.toml || -f setup.py || -f requirements.txt ]]; then
  language="Python"
  if [[ -f pyproject.toml ]]; then build_tool="pyproject.toml"
  elif [[ -f setup.py ]]; then build_tool="setup.py"
  else build_tool="requirements.txt"; fi
elif [[ -f Cargo.toml ]]; then
  language="Rust"
  build_tool="Cargo"
elif [[ -f go.mod ]]; then
  language="Go"
  build_tool="go modules"
elif [[ -f pom.xml ]]; then
  language="Java"
  build_tool="Maven"
elif [[ -f build.gradle || -f build.gradle.kts ]]; then
  language="Java/Kotlin"
  build_tool="Gradle"
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

# Top runtime dependencies as architecture signals.
deps=""
if [[ -f package.json ]]; then
  deps=$(jq -r '(.dependencies // {}) | keys | .[0:8] | join(", ")' package.json 2>/dev/null || echo "")
elif [[ -f pyproject.toml ]]; then
  deps=$(grep -E '^[a-zA-Z0-9_-]+ *=' pyproject.toml 2>/dev/null | head -8 \
    | sed -E 's/ *=.*//' | paste -sd ', ' - 2>/dev/null || echo "")
fi
[[ -z "$deps" ]] && deps="_none detected — fill in manually_"

repo_name=$(basename "$REPO_ROOT")
if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
  n=$(gh repo view --json name --jq '.name' 2>/dev/null || true)
  [[ -n "$n" ]] && repo_name="$n"
fi

# ----------------------------------------------- emit

cat <<DOC
# 000 — Record architecture decisions

- **Status:** accepted
- **Date:** ${today}
- **Deciders:** tech-lead agent (draft — bootstrapped, pending human review)

_Draft bootstrapped ${today} for **${repo_name}**. Edit and commit to
\`.bsg/adr/\` — the tech-lead agent reads this directory every tick.
This first ADR records the decision to keep an architecture decision
log; subsequent ADRs document individual decisions._

## Context

This repository did not yet have an architecture decision record (ADR)
log. The tech-lead agent expects significant technical decisions to be
captured under \`.bsg/adr/\` so that the rationale behind the current
design is discoverable and reviewable over time.

The following signals were detected during bootstrap and should anchor
the first real ADRs:

| Signal | Detected value |
|---|---|
| Primary language | ${language} |
| Build / packaging | ${build_tool} |
| CI system | ${ci_system} |
| Key dependencies | ${deps} |

## Decision

We will keep an architecture decision log under \`.bsg/adr/\`, one
Markdown file per decision, numbered sequentially
(\`NNN-title.md\`). Each ADR records context, the decision, and its
consequences. ADRs are immutable once accepted; a superseding decision
gets a new ADR that references the one it replaces.

## Consequences

- New significant decisions (frameworks, data stores, API style,
  build tooling) must be recorded as a new ADR before or alongside the
  change that introduces them.
- The tech-lead agent will flag undocumented architectural drift on its
  tick by comparing observed signals against this log.

## Suggested follow-up ADRs

_Replace these stubs with real decisions for this repo:_

- \`001-technology-stack.md\` — why **${language}** / **${build_tool}**
- \`002-ci-pipeline.md\` — why **${ci_system}**
- \`003-api-design.md\` — public interface conventions (if applicable)
DOC
