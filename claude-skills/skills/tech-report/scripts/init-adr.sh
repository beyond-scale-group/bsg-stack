#!/usr/bin/env bash
# init-adr.sh — generate a draft ADR bootstrap from repo scan.
#
# Part of #237 (per-agent --init contract): scans the repo for
# architecture signals (primary language/framework, CI system, major
# dependencies) and emits a draft `000-record-architecture-decisions.md`
# meta-ADR to stdout, with the detected stack folded into its Context
# section so the first decision record is immediately useful. The
# tech-lead agent reads `.bsg/adr/` every tick to flag undocumented
# decisions.
#
# The orchestrator (`/bsg-stack init`) captures stdout and opens a PR
# for human review — this script never writes to disk.
#
# Usage:
#   bash init-adr.sh
#   bash init-adr.sh --repo OWNER/NAME

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

# ----------------------------------------------- signals

# 1. Primary language / framework from manifest files.
STACK=()
if [[ -f package.json ]]; then
  fw="Node.js"
  for marker in next nuxt react vue svelte @angular/core express fastify nestjs; do
    if grep -q "\"$marker\"" package.json 2>/dev/null; then
      fw="Node.js (${marker%%/*})"
      break
    fi
  done
  STACK+=("$fw — package.json")
fi
[[ -f pyproject.toml ]] && STACK+=("Python — pyproject.toml")
[[ -f setup.py && ! -f pyproject.toml ]] && STACK+=("Python — setup.py")
[[ -f requirements.txt && ! -f pyproject.toml && ! -f setup.py ]] && STACK+=("Python — requirements.txt")
[[ -f Cargo.toml ]] && STACK+=("Rust — Cargo.toml")
[[ -f go.mod ]] && STACK+=("Go — go.mod")
[[ -f pom.xml ]] && STACK+=("Java — Maven (pom.xml)")
[[ -f build.gradle || -f build.gradle.kts ]] && STACK+=("Java/Kotlin — Gradle")
[[ -f Gemfile ]] && STACK+=("Ruby — Gemfile")
[[ -f composer.json ]] && STACK+=("PHP — composer.json")

# 2. CI system.
ci="none detected"
if [[ -d .github/workflows ]] && \
   find .github/workflows -maxdepth 1 -name '*.y*ml' 2>/dev/null | grep -q .; then
  ci="GitHub Actions (.github/workflows/)"
elif [[ -f .gitlab-ci.yml ]]; then
  ci="GitLab CI (.gitlab-ci.yml)"
elif [[ -f .circleci/config.yml ]]; then
  ci="CircleCI (.circleci/config.yml)"
elif [[ -f Jenkinsfile ]]; then
  ci="Jenkins (Jenkinsfile)"
elif [[ -f azure-pipelines.yml ]]; then
  ci="Azure Pipelines (azure-pipelines.yml)"
fi

# Guard the array expansion: under `set -u`, bash 5.2+ treats an empty
# array as unbound, so always seed a fallback before any `${STACK[@]}`.
# `${STACK[*]:-}` is the only expansion that is safe here.
if [[ -z "${STACK[*]:-}" ]]; then
  STACK=("_No language manifest detected — fill this in manually._")
fi

# ----------------------------------------------- emit

cat <<HEAD
# 0. Record architecture decisions

_Draft bootstrapped ${today}. Edit and commit to
\`.bsg/adr/000-record-architecture-decisions.md\` — the tech-lead agent
reads \`.bsg/adr/\` every tick to flag significant decisions that were
made without a record._

## Status

Proposed

## Context

We need to record the architectural decisions made on this project so
that newcomers — human or agent — can understand *why* the system is
shaped the way it is, not just *how*. Decisions made implicitly in code
review or chat are invisible six months later.

Scan of the current repository detected:

**Primary stack:**
HEAD

printf -- '- %s\n' "${STACK[@]}"

cat <<TAIL

**CI system:** ${ci}

_Verify these signals and replace with the real architectural context
before marking this ADR \`Accepted\`._

## Decision

We will use Architecture Decision Records (ADRs), as
[described by Michael Nygard][nygard]. Each ADR is a short Markdown
file in \`.bsg/adr/\`, numbered sequentially, with the sections:
**Status**, **Context**, **Decision**, **Consequences**.

[nygard]: https://cognitect.com/blog/2011/11/15/documenting-architecture-decisions

## Consequences

- Every significant technical decision gets a numbered ADR under
  \`.bsg/adr/\` and is reviewed in a PR like any other change.
- The tech-lead agent treats an undocumented architectural change as a
  finding and prompts for an ADR.
- Suggested next record: \`001-technology-stack.md\` — formalise the
  detected stack above into an accepted decision once verified.
TAIL
