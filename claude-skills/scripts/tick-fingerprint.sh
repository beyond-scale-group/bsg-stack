#!/usr/bin/env bash
# tick-fingerprint.sh — deterministic input-fingerprint for tick short-circuit.
#
# Every reporting agent sources this at tick start. It computes a SHA-256
# of the repo's current "input state" and compares it against the
# fingerprint stored in the last merged report. If they match, the agent
# can skip the full audit.
#
# Usage:
#   eval "$(bash tick-fingerprint.sh <agent-name> <report-dir> [--extra-hash <string>])"
#
# Exports:
#   TICK_SHORT_CIRCUIT   1 if today's report exists and fingerprint matches; 0 otherwise
#   TICK_LAST_PR         PR number of the existing report (empty if none)
#   TICK_FINGERPRINT     Current input fingerprint (SHA-256, first 16 hex chars)
#   TICK_REPORT_FILE     Path to today's report file on disk (may not exist yet)

set -euo pipefail

AGENT=""
REPORT_DIR=""
EXTRA_HASH=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --extra-hash) EXTRA_HASH="$2"; shift 2 ;;
    -*)           echo "tick-fingerprint.sh: unknown flag: $1" >&2; exit 2 ;;
    *)
      if [[ -z "$AGENT" ]]; then
        AGENT="$1"; shift
      elif [[ -z "$REPORT_DIR" ]]; then
        REPORT_DIR="$1"; shift
      else
        echo "tick-fingerprint.sh: unexpected arg: $1" >&2; exit 2
      fi
      ;;
  esac
done

if [[ -z "$AGENT" || -z "$REPORT_DIR" ]]; then
  echo "usage: tick-fingerprint.sh <agent-name> <report-dir> [--extra-hash <string>]" >&2
  exit 2
fi

REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
TODAY=$(date +%F)
# Freeze HH-MM-SS at script start so every consumer of this run sees
# the same slug — and so multiple ticks in the same day produce
# distinct filenames instead of fighting over `${TODAY}-<role>.md`
# (the cause of merge-conflict storms like #338).
NOW_HMS=$(date +%H-%M-%S)
TIMESTAMP="${TODAY}T${NOW_HMS}"

# ---------------------------------------------------------------- helpers

# Per-agent role suffix appended to the timestamped slug. Kept separate
# from the timestamp so the same-day idempotency lookup can glob
# `${TODAY}*-${ROLE}.md` and find any earlier tick from today
# (including pre-timestamp files written before this change).
role_for_agent() {
  case "$1" in
    po-manager)   echo "status" ;;
    security)     echo "audit" ;;
    qa)           echo "audit" ;;
    tech-lead)    echo "health" ;;
    seo)          echo "audit" ;;
    marketing)    echo "audit" ;;
    storytelling) echo "audit" ;;
    pr-comms)     echo "events" ;;
    *)            echo "report" ;;
  esac
}

ROLE=$(role_for_agent "$AGENT")
SLUG="${TIMESTAMP}-${ROLE}"
REPORT_FILE="${REPO_ROOT}/${REPORT_DIR}/reports/${SLUG}.md"

# ------------------------------------------------ compute current fingerprint
# Hash a stable set of repo-wide signals that any agent cares about.
# Per-agent extensions go through --extra-hash.

fingerprint_inputs=""

# 1. Open issue numbers + labels (sorted for stability)
issue_state=$(gh issue list --state all --limit 500 --json number,state,labels \
  --jq '[.[] | {n: .number, s: .state, l: [.labels[].name] | sort}] | sort_by(.n)' 2>/dev/null || echo "[]")
fingerprint_inputs+="$issue_state"

# 2. PR numbers + state — excluding report PRs (reports/* branches).
#    A tick's own landed report must be invisible to the next tick's
#    fingerprint, or the loop never converges: report merges → PR state
#    changes → fingerprint differs → new report → repeat. Observed as
#    duplicate same-day report PRs (#538/#540, #541/#542).
pr_state=$(gh pr list --state all --limit 200 --json number,state,headRefName \
  --jq '[.[] | select(.headRefName | startswith("reports/") | not) | {n: .number, s: .state}] | sort_by(.n)' 2>/dev/null || echo "[]")
fingerprint_inputs+="$pr_state"

# 3. Last non-report commit SHA (code changes). Report merges bump HEAD
#    without changing anything an audit reads — skip them for the same
#    convergence reason as (2).
head_sha=$(git log -1 --invert-grep --grep='^report(' --format=%H 2>/dev/null || echo "unknown")
[[ -n "$head_sha" ]] || head_sha="unknown"
fingerprint_inputs+="$head_sha"

# 4. Per-agent extra hash (e.g. lockfile content hash for security)
if [[ -n "$EXTRA_HASH" ]]; then
  fingerprint_inputs+="$EXTRA_HASH"
fi

TICK_FINGERPRINT=$(printf '%s' "$fingerprint_inputs" | shasum -a 256 | cut -c1-16)

# --------------------------------------------- extract fingerprint from last report

TICK_SHORT_CIRCUIT=0
TICK_LAST_PR=""

# Look for any same-day report (current or earlier tick) whose stored
# fingerprint matches the current input state. The glob covers both
# the new timestamped slug `${TODAY}T${HH-MM-SS}-${ROLE}` and any
# legacy `${TODAY}-${ROLE}` files from before this change. Most-recent
# match wins via `ls -t`.
matched_file=""
matched_slug=""
for candidate in $(ls -t "${REPO_ROOT}/${REPORT_DIR}/reports/${TODAY}"*"-${ROLE}.md" 2>/dev/null); do
  stored_fp=$(sed -n 's/^<!-- fingerprint: \(.*\) -->/\1/p' "$candidate" | head -1)
  if [[ "$stored_fp" == "$TICK_FINGERPRINT" ]]; then
    matched_file="$candidate"
    matched_slug=$(basename "$candidate" .md)
    break
  fi
done

if [[ -n "$matched_file" ]]; then
  branch_pattern="reports/${AGENT}/${matched_slug}"
  TICK_LAST_PR=$(gh pr list --state merged --head "$branch_pattern" --limit 1 \
    --json number --jq '.[0].number' 2>/dev/null || echo "")
  if [[ -n "$TICK_LAST_PR" ]]; then
    TICK_SHORT_CIRCUIT=1
  fi
fi

# ---------------------------------------------------------------- emit exports
# Caller evals the output: eval "$(bash tick-fingerprint.sh ...)"
cat <<EXPORTS
export TICK_SHORT_CIRCUIT=$TICK_SHORT_CIRCUIT
export TICK_LAST_PR=$TICK_LAST_PR
export TICK_FINGERPRINT=$TICK_FINGERPRINT
export TICK_REPORT_FILE=$REPORT_FILE
EXPORTS
