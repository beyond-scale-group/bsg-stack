#!/usr/bin/env bash
# tick-idle-check.sh — pre-flight idle check for output:commit agents.
#
# Closes #363 fix #5. Cuts the recurring `/loop` cost when an agent has
# nothing to do: when there are no phase-B candidates AND the audit
# fingerprint hasn't changed since yesterday, the tick exits idle
# without running phases A / A.5 / B / C.
#
# Decision matrix:
#
#   1. Run `list-pilot-candidates.sh --agent <name>`. If it emits ≥ 1
#      candidate, we are NOT idle — the agent has phase-B work to do.
#   2. Run `tick-fingerprint.sh <agent> <report-dir>`. If
#      TICK_SHORT_CIRCUIT=1, today's report already matches the current
#      input state — phase-A is unchanged. Combined with (1) being
#      empty, there is nothing for this tick to produce.
#   3. Otherwise the agent must run phases A/A.5/B/C as usual.
#
# When idle, the script appends a one-line entry to
# `<report-dir>/idle-ticks.log` (e.g. `tech/idle-ticks.log`) for
# trend analysis. The log is git-ignored by convention but committed
# in repos that want to track agent cadence.
#
# Usage (sourced via eval, like tick-fingerprint.sh):
#   eval "$(bash claude-skills/scripts/tick-idle-check.sh <agent-cli-name> <bus-label> <report-dir> [-- <tick-fingerprint-args>...])"
#
# Arguments:
#   <agent-cli-name>  the name passed to tick-fingerprint.sh
#                     (e.g. tech-lead, qa, seo)
#   <bus-label>       the bus label passed to list-pilot-candidates.sh
#                     (e.g. tech, qa, seo) — this differs from the CLI
#                     name for tech-lead vs tech.
#   <report-dir>      e.g. tech, qa, seo (used for idle-ticks.log path)
#   [-- <args>...]    optional extra args forwarded verbatim to
#                     tick-fingerprint.sh. Required for narrow-scope
#                     agents (marketing / storytelling / pr-comms) whose
#                     stored fingerprint used --inputs — otherwise the
#                     idle check recomputes a default fingerprint that
#                     will never match (#714).
#
# Exports:
#   TICK_IDLE             1 if the agent should short-circuit, 0 otherwise
#   TICK_IDLE_RECEIPT     One-line receipt to surface in chat when idle
#                         (e.g. "Tick: idle — no candidates")
#
# When TICK_IDLE=1, the calling agent should emit TICK_IDLE_RECEIPT and
# exit without running phases A/A.5/B/C. See the agent's tick frontmatter
# for the integration point.

set -euo pipefail

if [[ $# -lt 3 ]]; then
  echo "usage: tick-idle-check.sh <agent-cli-name> <bus-label> <report-dir> [-- <tick-fingerprint-args>...]" >&2
  exit 2
fi

AGENT_CLI="$1"
BUS_LABEL="$2"
REPORT_DIR="$3"
shift 3

# Optional `--` separator introduces extra args forwarded to
# tick-fingerprint.sh (e.g. `--inputs releases,path:comms`). Callers
# that don't need it just omit the separator.
FP_EXTRA_ARGS=()
if [[ $# -gt 0 ]]; then
  if [[ "$1" == "--" ]]; then
    shift
    FP_EXTRA_ARGS=("$@")
  else
    echo "tick-idle-check.sh: expected -- before extra tick-fingerprint args, got: $1" >&2
    exit 2
  fi
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

# Step 1: are there any phase-B candidates?
candidates=$(bash "$SCRIPT_DIR/list-pilot-candidates.sh" --agent "$BUS_LABEL" 2>/dev/null || echo "")
candidate_count=$(printf '%s\n' "$candidates" | grep -c '^{' || true)

# Step 2: is today's audit fingerprint already on file?
# Run tick-fingerprint.sh in a subshell to capture its exports without
# polluting the caller — we only need to know if SHORT_CIRCUIT was set.
# Forward any extra args (typically --inputs) so the recomputed
# fingerprint matches the one stored in today's report.
fp_exports=$(bash "$SCRIPT_DIR/tick-fingerprint.sh" "$AGENT_CLI" "$REPORT_DIR" "${FP_EXTRA_ARGS[@]}" 2>/dev/null || true)
short_circuit=$(printf '%s\n' "$fp_exports" | sed -n 's/^export TICK_SHORT_CIRCUIT=//p' | head -1)

TICK_IDLE=0
TICK_IDLE_RECEIPT=""
if [[ "$candidate_count" -eq 0 ]] && [[ "$short_circuit" == "1" ]]; then
  TICK_IDLE=1
  TICK_IDLE_RECEIPT="Tick: idle — no candidates"
  # Append to idle-ticks.log for cadence analysis. Best-effort — never
  # fail the tick over a missing report dir or unwritable filesystem.
  log_dir="$REPO_ROOT/$REPORT_DIR"
  if [[ -d "$log_dir" ]]; then
    printf '%s %s idle (no candidates, audit fingerprint matched)\n' \
      "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$AGENT_CLI" \
      >> "$log_dir/idle-ticks.log" 2>/dev/null || true
  fi
fi

cat <<EXPORTS
export TICK_IDLE=$TICK_IDLE
export TICK_IDLE_RECEIPT='$TICK_IDLE_RECEIPT'
EXPORTS
