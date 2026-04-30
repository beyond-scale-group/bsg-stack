#!/usr/bin/env bash
# run-pipeline-test.sh — compressed-run regression harness for the
# bsg-stack autopilot pipeline (#292).
#
# Workflow:
#   1. Reset state on the test repo (close test-fixture issues, clear
#      agent:lock:* labels, close any open PRs from prior runs)
#   2. Seed a fresh synthetic backlog via seed-test-backlog.sh
#   3. Loop `claude -p "/tick-all"` for --duration at --cadence
#   4. Collect PR + issue snapshots
#   5. Assert invariants I1-I4 via assert-invariants.sh
#
# Exits 0 if all invariants pass, 1 otherwise.
#
# Usage:
#   bash claude-skills/scripts/test/run-pipeline-test.sh \
#     --repo beyond-scale-group/bsg-stack-test-harness \
#     --duration 30m --cadence 60s

set -euo pipefail

REPO="beyond-scale-group/bsg-stack-test-harness"
DURATION="30m"
CADENCE="60s"
RESET=true
SEED=true
CLONE_DIR=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo)      REPO="$2"; shift 2 ;;
    --duration)  DURATION="$2"; shift 2 ;;
    --cadence)   CADENCE="$2"; shift 2 ;;
    --no-reset)  RESET=false; shift ;;
    --no-seed)   SEED=false; shift ;;
    --clone-dir) CLONE_DIR="$2"; shift 2 ;;
    -h|--help)   sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "run-pipeline-test: unknown arg: $1" >&2; exit 2 ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
START_TIME=$(date -u +%s)
LOG_DIR="/tmp/pipeline-test-$START_TIME"
mkdir -p "$LOG_DIR"

duration_to_secs() {
  local s="$1"
  case "$s" in
    *m) echo $((${s%m} * 60)) ;;
    *h) echo $((${s%h} * 3600)) ;;
    *s) echo "${s%s}" ;;
    *)  echo "$s" ;;
  esac
}
DUR_SECS=$(duration_to_secs "$DURATION")
CAD_SECS=$(duration_to_secs "$CADENCE")

iso_from_epoch() {
  if date --version >/dev/null 2>&1; then
    date -u -d "@$1" +%Y-%m-%dT%H:%M:%SZ
  else
    date -u -r "$1" +%Y-%m-%dT%H:%M:%SZ
  fi
}
START_ISO=$(iso_from_epoch "$START_TIME")

[[ -z "$CLONE_DIR" ]] && CLONE_DIR="/tmp/harness-clone-$START_TIME"

echo "== Pipeline regression test =="
echo "repo:     $REPO"
echo "duration: $DURATION ($DUR_SECS s)"
echo "cadence:  $CADENCE ($CAD_SECS s)"
echo "logs:     $LOG_DIR"
echo

# === Clone the harness repo (claude tick-all needs cwd to be a git repo) ===
if [[ ! -d "$CLONE_DIR/.git" ]]; then
  echo "clone: $REPO -> $CLONE_DIR"
  gh repo clone "$REPO" "$CLONE_DIR" >/dev/null 2>&1
fi
cd "$CLONE_DIR"

# === Reset ===
if [[ "$RESET" == "true" ]]; then
  echo "reset: closing test-fixture issues + clearing locks + closing stale PRs"

  gh issue list --repo "$REPO" --label test-fixture --state open --json number --jq '.[].number' \
    | while read -r n; do gh issue close --repo "$REPO" "$n" >/dev/null 2>&1 || true; done

  for agent in po security qa tech seo marketing storytelling pr-comms; do
    gh issue list --repo "$REPO" --label "agent:lock:$agent" --state open --json number --jq '.[].number' 2>/dev/null \
      | while read -r n; do gh issue edit --repo "$REPO" "$n" --remove-label "agent:lock:$agent" >/dev/null 2>&1 || true; done
  done

  gh pr list --repo "$REPO" --state open --json number --jq '.[].number' \
    | while read -r n; do gh pr close --repo "$REPO" "$n" --delete-branch >/dev/null 2>&1 || true; done
fi

# === Seed ===
if [[ "$SEED" == "true" ]]; then
  bash "$SCRIPT_DIR/seed-test-backlog.sh" --repo "$REPO" --force
fi

# === Run ===
target_ticks=$((DUR_SECS / CAD_SECS))
echo "run: target $target_ticks ticks"
end_time=$((START_TIME + DUR_SECS))
tick_count=0
errored=0
while [[ $(date -u +%s) -lt $end_time ]]; do
  tick_count=$((tick_count + 1))
  ts=$(date -u +%H:%M:%S)
  echo "  tick $tick_count/$target_ticks at $ts"
  if claude -p "/tick-all" > "$LOG_DIR/tick-$tick_count.log" 2>&1; then
    :
  else
    errored=$((errored + 1))
    echo "    errored — see $LOG_DIR/tick-$tick_count.log"
  fi
  sleep "$CAD_SECS"
done

# === Collect ===
echo "collect: snapshotting PR + issue state since $START_ISO"
gh pr list --repo "$REPO" --state all --search "created:>=$START_ISO" \
  --json number,title,state,labels,additions,deletions,changedFiles,mergedAt,createdAt \
  > "$LOG_DIR/prs.json"
gh issue list --repo "$REPO" --state all --search "created:>=$START_ISO" \
  --json number,title,state,labels,createdAt \
  > "$LOG_DIR/issues.json"

# === Assert ===
echo "assert: running invariants I1-I4"
echo
bash "$SCRIPT_DIR/assert-invariants.sh" --logs "$LOG_DIR" --repo "$REPO"
result=$?

elapsed=$(( $(date -u +%s) - START_TIME ))
echo
echo "done: $tick_count ticks in ${elapsed}s ($errored errored). logs: $LOG_DIR"
exit $result
