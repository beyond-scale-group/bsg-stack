#!/usr/bin/env bash
# init-adr.sh — generate a draft bootstrap ADR from repo scan.
#
# Part of #237 (per-agent --init contract): scans the repo for
# architecture signals (detected ecosystems / major dependencies,
# CI setup, top-level directory layout) and emits a draft seed ADR
# to stdout. The tech-lead agent reads `.bsg/adr/` every tick to
# detect decisions that ship without a matching ADR.
#
# The orchestrator (`/bsg-stack init`) captures stdout and writes it
# to `.bsg/adr/0000-architecture-baseline.md`, then opens a PR for
# human review — this script never writes to disk.
#
# Usage:
#   bash init-adr.sh
#
# Exit 0 + content on stdout: success
# Exit 2: bad arguments

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

# ----------------------------------------------- signals

# 1. Ecosystems / major deps from lockfiles & manifests at the top level.
ECOSYSTEMS=()
[[ -f package.json ]]      && ECOSYSTEMS+=("Node.js (package.json)")
[[ -f requirements.txt ]]  && ECOSYSTEMS+=("Python (requirements.txt)")
[[ -f pyproject.toml ]]    && ECOSYSTEMS+=("Python (pyproject.toml)")
[[ -f go.mod ]]            && ECOSYSTEMS+=("Go (go.mod)")
[[ -f Cargo.toml ]]        && ECOSYSTEMS+=("Rust (Cargo.toml)")
[[ -f pom.xml ]]           && ECOSYSTEMS+=("Java (pom.xml)")
[[ -f build.gradle || -f build.gradle.kts ]] && ECOSYSTEMS+=("Java/Kotlin (Gradle)")
[[ -f Gemfile ]]           && ECOSYSTEMS+=("Ruby (Gemfile)")
[[ -f composer.json ]]     && ECOSYSTEMS+=("PHP (composer.json)")

# Top npm dependencies (names only, capped) when package.json is present.
top_npm=""
if [[ -f package.json ]] && command -v jq >/dev/null 2>&1; then
  top_npm=$(jq -r '(.dependencies // {}) | keys | .[0:10] | join(", ")' package.json 2>/dev/null || true)
fi

# 2. CI setup.
CI=()
[[ -d .github/workflows ]] && CI+=("GitHub Actions ($(find .github/workflows -maxdepth 1 -type f \( -name '*.yml' -o -name '*.yaml' \) 2>/dev/null | wc -l | tr -d ' ') workflow file(s))")
[[ -f .gitlab-ci.yml ]]    && CI+=("GitLab CI")
[[ -f .circleci/config.yml ]] && CI+=("CircleCI")
[[ -f Jenkinsfile ]]       && CI+=("Jenkins")

# 3. Top-level directory layout (a coarse architecture signal).
top_dirs=$(find . -maxdepth 1 -mindepth 1 -type d \
  -not -name '.git' -not -name 'node_modules' 2>/dev/null \
  | sed 's|^\./||' | sort | head -20 \
  | awk 'NR>1{printf ", "}{printf "%s",$0}END{if(NR)print ""}')

# 4. Existing ADRs (so the bootstrap notes whether a tree already exists).
existing_adr_dir=""
for d in .bsg/adr adr docs/adr; do
  if [[ -d "$d" ]] && find "$d" -maxdepth 1 -type f -name '*.md' 2>/dev/null | grep -q .; then
    existing_adr_dir="$d"
    break
  fi
done

# ----------------------------------------------- emit

fmt_list() {
  if [[ "$#" -eq 0 ]]; then
    echo "_None detected — fill this in manually._"
  else
    printf -- '- %s\n' "$@"
  fi
}

cat <<HEAD
# 0000 — Architecture baseline

- **Status:** draft (bootstrapped ${today})
- **Deciders:** _set the people who own this decision_
- **Tags:** baseline, bootstrap

_This ADR was bootstrapped automatically from a repo scan. It is a
**starting point**, not a record of a real decision — review every
section, replace the placeholders, and split it into focused ADRs
(\`0001-...\`, \`0002-...\`) as concrete decisions are made. The
tech-lead agent reads \`.bsg/adr/\` every tick to flag major
dependencies and architecture changes that ship without an ADR._

## Context

The repository currently exhibits the following architecture signals.
Treat each as a decision that *should* eventually have its own ADR.

### Detected ecosystems

$(fmt_list ${ECOSYSTEMS[@]+"${ECOSYSTEMS[@]}"})
HEAD

if [[ -n "$top_npm" ]]; then
  cat <<DEPS

### Top runtime dependencies (npm)

${top_npm}

_Each major dependency above is an implicit architecture decision.
Document the non-obvious ones (frameworks, data layers, auth) in
their own ADR._
DEPS
fi

cat <<TAIL

### Continuous integration

$(fmt_list ${CI[@]+"${CI[@]}"})

### Top-level layout

${top_dirs:-_empty repository — no top-level directories yet._}

## Decision

_Replace this section. Document the **load-bearing** architectural
choices that are currently implicit in the layout and dependencies
above — e.g. "we use Next.js app-router", "Postgres is the system of
record", "the API is REST, not GraphQL". One decision per future ADR._

## Consequences

_Replace this section. For each decision, note the trade-off accepted
and what would have to change to reverse it._

## Notes

$(if [[ -n "$existing_adr_dir" ]]; then
    echo "An existing ADR tree was detected at \`${existing_adr_dir}/\`."
    echo "Migrate those records under \`.bsg/adr/\` (see #237) and delete"
    echo "this bootstrap stub once real ADRs exist."
  else
    echo "No existing ADR tree was found. Start adding focused ADRs"
    echo "under \`.bsg/adr/\` and delete this bootstrap stub once the"
    echo "first real decision is recorded."
  fi)
TAIL
