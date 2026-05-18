#!/usr/bin/env bash
# init-securityignore.sh — generate a draft SECURITYIGNORE from repo scan.
#
# Part of #237 (per-agent --init contract): scans the repo for paths
# that typically contain test fixtures, sample credentials, or example
# data — i.e. the most common sources of secret-scanner false positives.
# Emits a draft `.bsg/SECURITYIGNORE` to stdout. The security agent
# reads this file every tick to suppress known false-positive paths.
#
# The orchestrator (`/bsg-stack init`) captures stdout and opens a PR
# for human review — this script never writes to disk.
#
# Usage:
#   bash init-securityignore.sh
#
# Exit 0 + content on stdout: success
# Exit 1: error

set -euo pipefail

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help) sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "init-securityignore.sh: unknown arg: $1" >&2; exit 2 ;;
  esac
done

REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
cd "$REPO_ROOT"

today=$(date -u +%F)

# Track suggestions so we only emit each once, and report whether
# anything was found.
declare -a SUGGESTIONS
seen=""
add_suggestion() {
  local path="$1"
  case " $seen " in
    *" $path "*) return ;;
  esac
  seen="$seen $path"
  SUGGESTIONS+=("$path")
}

# 1. Common test / fixture directories at the top level.
for d in tests test __tests__ spec fixtures __fixtures__ examples example demo demos sample samples; do
  if [[ -d "$d" ]]; then
    add_suggestion "$d/"
  fi
done

# 2. Nested test/fixture/example directories anywhere in the repo (one
#    level deep so we don't recurse forever).
while IFS= read -r d; do
  d="${d#./}"
  # Skip top-level entries already added above.
  case "$d" in
    tests/|test/|__tests__/|spec/|fixtures/|__fixtures__/|examples/|example/|demo/|demos/|sample/|samples/)
      continue
      ;;
  esac
  add_suggestion "$d/"
done < <(find . -maxdepth 4 -type d \
    -not -path './.git/*' -not -path './node_modules/*' \( \
    -name 'fixtures' -o -name '__fixtures__' \
    -o -name 'samples' -o -name 'sample' \
    -o -name 'examples' -o -name 'example' \
    -o -name 'testdata' -o -name 'test_data' \
  \) 2>/dev/null | head -20)

# 3. Common sample env files. Skip .git/ which contains stock
# *.sample hook scripts — those are part of git, not the repo.
while IFS= read -r f; do
  f="${f#./}"
  add_suggestion "$f"
done < <(find . -maxdepth 3 -type f \
    -not -path './.git/*' -not -path './node_modules/*' \( \
    -name '*.example' -o -name '*.sample' \
    -o -name '.env.example' -o -name '.env.sample' -o -name '.env.template' \
  \) 2>/dev/null | head -20)

# ----------------------------------------------- emit

cat <<HEAD
# SECURITYIGNORE — draft bootstrapped ${today}
#
# Paths listed here are excluded from secret-pattern scans by the
# security agent. One pattern per line; trailing slash means "treat
# as a directory and recurse." Blank lines and lines starting with #
# are comments.
#
# This file was bootstrapped automatically from common test / fixture
# directory names. Review every entry, delete anything you don't
# recognise, and add patterns specific to your repo (e.g. a vendored
# third-party SDK that contains demo credentials).
#
# After editing, commit this file to .bsg/SECURITYIGNORE.

HEAD

if [[ "${#SUGGESTIONS[@]}" -eq 0 ]]; then
  cat <<'EMPTY'
# No common test or fixture directories detected. Add explicit patterns
# below as the security agent surfaces false positives, e.g.:
#
#   tests/fixtures/
#   docs/examples/sample-config.yml
EMPTY
else
  printf '%s\n' "${SUGGESTIONS[@]}"
fi
