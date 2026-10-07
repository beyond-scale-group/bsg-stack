#!/usr/bin/env bash
# test_script_path.sh — unit tests for _bsg-script-path.sh.
#
# Verifies that bsg_script_path prefers the in-repo copy of a script when
# one exists and falls back to the installed copy under CLAUDE_CONFIG_DIR
# otherwise, so a machine-scoped tool resolves from any cwd.
#
# Run locally:
#   bash claude-skills/tests/test_script_path.sh
#
# Exit 0 = all pass, exit 1 = failure.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SUT="$REPO_ROOT/claude-skills/scripts/_bsg-script-path.sh"

PASS=0
FAIL=0

assert_eq() {
  local label="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    echo "FAIL: $label"
    echo "  expected: $expected"
    echo "  actual:   $actual"
  fi
}

# On macOS `mktemp -d` hands back a path through /var -> /private/var, while
# git reports the physical path. Normalise every fixture root with `pwd -P`
# or the string comparisons below fail for the wrong reason.
phys() { (cd "$1" && pwd -P); }

# 1. Inside a repo that has the script → the repo copy wins.
tmp_repo="$(phys "$(mktemp -d)")"
mkdir -p "$tmp_repo/claude-skills/scripts"
git -C "$tmp_repo" init -q
touch "$tmp_repo/claude-skills/scripts/session-state.sh"
out="$(cd "$tmp_repo" && CLAUDE_CONFIG_DIR=/nonexistent bash -c \
  'source "'"$SUT"'"; bsg_script_path session-state.sh')"
assert_eq "repo copy wins" \
  "$tmp_repo/claude-skills/scripts/session-state.sh" "$out"

# 2. Inside a repo WITHOUT the script → installed copy.
tmp_repo2="$(phys "$(mktemp -d)")"
git -C "$tmp_repo2" init -q
fake_home="$(phys "$(mktemp -d)")"
mkdir -p "$fake_home/scripts"
out="$(cd "$tmp_repo2" && CLAUDE_CONFIG_DIR="$fake_home" bash -c \
  'source "'"$SUT"'"; bsg_script_path session-state.sh')"
assert_eq "falls back to installed copy" \
  "$fake_home/scripts/session-state.sh" "$out"

# 3. Outside any git repo → installed copy, no crash.
tmp_bare="$(phys "$(mktemp -d)")"
out="$(cd "$tmp_bare" && CLAUDE_CONFIG_DIR="$fake_home" bash -c \
  'source "'"$SUT"'"; bsg_script_path session-state.sh')"
assert_eq "outside a repo falls back" \
  "$fake_home/scripts/session-state.sh" "$out"

# 4. CLAUDE_CONFIG_DIR unset → defaults to ~/.claude.
out="$(cd "$tmp_bare" && env -u CLAUDE_CONFIG_DIR bash -c \
  'source "'"$SUT"'"; bsg_script_path session-state.sh')"
assert_eq "defaults to ~/.claude" \
  "$HOME/.claude/scripts/session-state.sh" "$out"

rm -rf "$tmp_repo" "$tmp_repo2" "$tmp_bare" "$fake_home"

echo "test_script_path.sh: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
