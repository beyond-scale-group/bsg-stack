# session-janitor Lot 1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship the read-only half of `session-janitor` — a path helper, a
session-state resolver that emits one JSON line per live Claude Code session,
and a `doctor` verb that formats it — so the manual audit of 2026-09-17 becomes
repeatable and loopable.

**Architecture:** `session-state.sh` is the single place that decides what a
session is and whether it may be reaped; every later consumer (`reap`, `sync`)
filters its `verdict` field rather than re-deriving rules. The script is
testable because process enumeration is injectable (`BSG_SESSION_PROVIDER`) and
`gh` is resolved through `PATH`, so tests stub both and never touch a live
session. `_bsg-script-path.sh` resolves a script name to the repo copy when one
exists, else the installed copy under `$CLAUDE_CONFIG_DIR`.

**Tech Stack:** Bash (the catalogue's existing idiom), `jq` for JSON emission,
`git`, `gh`, `lsof`, `ps`. Tests are self-asserting bash in the existing
`claude-skills/tests/` harness — no framework.

**Spec:** `claude-skills/prds/009-session-janitor.md` (§5.2 verbs, §5.3
resolver, §5.4 invariants, §5.6 path resolution, §9 testing)

## Global Constraints

- **Read-only.** Nothing in lot 1 writes: no `kill`, no `gh` mutation, no file
  written outside `$TMPDIR`. A step that mutates is a plan violation.
- **Verdict vocabulary is closed.** Exactly: `reapable`, `keep:self`,
  `keep:too-young`, `keep:busy`, `keep:dev-servers`, `keep:dirty`,
  `keep:unpushed`, `keep:pr-open`, `unknown`. No other value may be emitted.
- **Verdict precedence is this exact order**, first match wins:
  `keep:self` → `keep:too-young` → `keep:busy` → `keep:dev-servers` →
  `keep:dirty` → `keep:unpushed` → `keep:pr-open` → `reapable` → `unknown`.
  A session can satisfy several; the order makes the output deterministic.
- **Age floor:** 300 seconds (spec §5.4.7).
- **Busy heuristic:** a session is busy when its transcript file changed within
  the last 300 seconds (spec §12.3 fallback, adopted for lot 1).
- **Transcript directory encoding:** the session cwd with `/`, `.` and `+` each
  replaced by `-`, under `${CLAUDE_CONFIG_DIR:-$HOME/.claude}/projects/`.
- **No upstream means unpushed.** A branch with no configured upstream is
  `keep:unpushed` whatever its commit count (spec §5.4.2).
- **Every new `SKILL.md` needs the `## How to improve this skill` footer**
  referencing its own canonical path, and a row in the "Available skills" table
  of `claude-skills/INSTALL.md`. Both are enforced by
  `test_skill_invariants.py`.
- **Shell style:** `#!/usr/bin/env bash`, `set -euo pipefail`, a header comment
  block with a "Run locally:" example, matching `_bsg-paths.sh`.

---

### Task 1: Path helper

**Files:**
- Create: `claude-skills/scripts/_bsg-script-path.sh`
- Test: `claude-skills/tests/test_script_path.sh`

**Interfaces:**
- Consumes: nothing.
- Produces: `bsg_script_path <name>` — prints an absolute path to the named
  script. Sourced, never executed. Every later task sources this file.

- [ ] **Step 1: Write the failing test**

Create `claude-skills/tests/test_script_path.sh`:

```bash
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash claude-skills/tests/test_script_path.sh`
Expected: FAIL — `_bsg-script-path.sh: No such file or directory`

- [ ] **Step 3: Write minimal implementation**

Create `claude-skills/scripts/_bsg-script-path.sh`:

```bash
# _bsg-script-path.sh — resolve a BSG script name to a usable path.
#
# Sourced (not executed) by machine-scoped tools that may run from any
# directory, including outside a git repository.
#
# The repo copy is the source of truth and is preferred when present, so
# editing a script inside bsg-stack takes effect immediately. Everywhere
# else the installed copy under CLAUDE_CONFIG_DIR (default ~/.claude) is
# the only one that exists — target repos do not vendor claude-skills/.
#
# Usage from a sibling script:
#
#     # shellcheck source=_bsg-script-path.sh disable=SC1091
#     source "$(dirname "${BASH_SOURCE[0]}")/_bsg-script-path.sh"
#     resolver="$(bsg_script_path session-state.sh)"
#
# Idempotent — sourcing twice does no harm.

bsg_script_path() {
  local name="${1:?bsg_script_path: script name required}" root
  root="$(git rev-parse --show-toplevel 2>/dev/null)" || root=""
  if [ -n "$root" ] && [ -f "$root/claude-skills/scripts/$name" ]; then
    printf '%s\n' "$root/claude-skills/scripts/$name"
  else
    printf '%s\n' "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/scripts/$name"
  fi
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash claude-skills/tests/test_script_path.sh`
Expected: `test_script_path.sh: 4 passed, 0 failed`

- [ ] **Step 5: Commit**

```bash
git add claude-skills/scripts/_bsg-script-path.sh claude-skills/tests/test_script_path.sh
git commit -m "feat(scripts): add _bsg-script-path.sh resolver

Machine-scoped tools run from any cwd, where the repo-relative
claude-skills/scripts/ path does not resolve. Prefer the repo copy when
present, fall back to the installed copy under CLAUDE_CONFIG_DIR."
```

---

### Task 2: Session enumeration

**Files:**
- Create: `claude-skills/scripts/session-state.sh`
- Test: `claude-skills/tests/test_session_state.sh`

**Interfaces:**
- Consumes: nothing from Task 1 yet (the helper is for *callers* of the
  resolver, not the resolver itself).
- Produces: executable `session-state.sh` emitting one JSON object per line
  with keys `pid`, `ppid`, `cwd`, `rss_mb`, `age_seconds`, `verdict`.
  `verdict` is `"unknown"` for every row at this stage.
  Honours `BSG_SESSION_PROVIDER` (path to an executable printing
  `pid<TAB>ppid<TAB>cwd<TAB>rss_mb<TAB>age_seconds`) and
  `BSG_SESSION_SELF_PID`.

- [ ] **Step 1: Write the failing test**

Create `claude-skills/tests/test_session_state.sh`:

```bash
#!/usr/bin/env bash
# test_session_state.sh — unit tests for session-state.sh.
#
# Process enumeration is injected via BSG_SESSION_PROVIDER so no test
# ever inspects or signals a real Claude session.
#
# Run locally:
#   bash claude-skills/tests/test_session_state.sh
#
# Exit 0 = all pass, exit 1 = failure.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SUT="$REPO_ROOT/claude-skills/scripts/session-state.sh"

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

# make_provider <file> <lines...> — write a fake enumerator.
make_provider() {
  local path="$1"; shift
  {
    echo '#!/usr/bin/env bash'
    local line
    for line in "$@"; do
      printf 'printf "%%s\\n" %q\n' "$line"
    done
  } > "$path"
  chmod +x "$path"
}

WORK="$(mktemp -d)"

# 1. One plain session round-trips its fields.
prov="$WORK/p1.sh"
make_provider "$prov" "4242	1	$WORK/none	142	60000"
out="$(BSG_SESSION_PROVIDER="$prov" BSG_SESSION_SELF_PID=999 bash "$SUT")"
assert_eq "one row emitted" "1" "$(printf '%s\n' "$out" | wc -l | tr -d ' ')"
assert_eq "pid parsed"      "4242" "$(printf '%s' "$out" | jq -r '.pid')"
assert_eq "rss parsed"      "142"  "$(printf '%s' "$out" | jq -r '.rss_mb')"
assert_eq "age parsed"      "60000" "$(printf '%s' "$out" | jq -r '.age_seconds')"

# 2. The calling session is excluded by verdict, not by omission.
prov="$WORK/p2.sh"
make_provider "$prov" "555	1	$WORK/none	100	60000"
out="$(BSG_SESSION_PROVIDER="$prov" BSG_SESSION_SELF_PID=555 bash "$SUT")"
assert_eq "self is kept" "keep:self" "$(printf '%s' "$out" | jq -r '.verdict')"

# 3. A wrapper/child pair sharing a cwd collapses to the child.
prov="$WORK/p3.sh"
make_provider "$prov" \
  "700	1	$WORK/shared	0	5000" \
  "701	700	$WORK/shared	208	5000"
out="$(BSG_SESSION_PROVIDER="$prov" BSG_SESSION_SELF_PID=999 bash "$SUT")"
assert_eq "wrapper collapsed" "1" "$(printf '%s\n' "$out" | wc -l | tr -d ' ')"
assert_eq "child survives"    "701" "$(printf '%s' "$out" | jq -r '.pid')"

# 4. A session younger than the age floor is kept.
prov="$WORK/p4.sh"
make_provider "$prov" "800	1	$WORK/none	100	120"
out="$(BSG_SESSION_PROVIDER="$prov" BSG_SESSION_SELF_PID=999 bash "$SUT")"
assert_eq "too young" "keep:too-young" "$(printf '%s' "$out" | jq -r '.verdict')"

# 4b. etime parsing. macOS ps has no `etimes` keyword, so the default
# enumerator reads POSIX `etime` ([[dd-]hh:]mm:ss) and converts it. Sourcing
# the script defines the helpers without running main.
source "$SUT"
assert_eq "etime mm:ss"       "0"      "$(etime_to_seconds '00:00')"
assert_eq "etime mm:ss again" "330"    "$(etime_to_seconds '05:30')"
assert_eq "etime hh:mm:ss"    "5025"   "$(etime_to_seconds '01:23:45')"
assert_eq "etime dd-hh:mm:ss" "183845" "$(etime_to_seconds '2-03:04:05')"
assert_eq "etime leading zeros not octal" "489" "$(etime_to_seconds '08:09')"

rm -rf "$WORK"

echo "test_session_state.sh: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash claude-skills/tests/test_session_state.sh`
Expected: FAIL — `session-state.sh: No such file or directory`

- [ ] **Step 3: Write minimal implementation**

Create `claude-skills/scripts/session-state.sh`:

```bash
#!/usr/bin/env bash
# session-state.sh — emit one JSON object per live Claude Code session.
#
# The single source of truth for "what is this session, and may it be
# reaped". Consumers filter the `verdict` field; none re-derives the
# rules. Strictly read-only: it signals nothing and mutates nothing.
#
# Process enumeration is injectable so tests never touch a live session:
#   BSG_SESSION_PROVIDER  executable printing one TAB-separated row per
#                         session: pid, ppid, cwd, rss_mb, age_seconds
#   BSG_SESSION_SELF_PID  pid to classify as keep:self (default: $PPID)
#
# Run locally:
#   bash claude-skills/scripts/session-state.sh | jq .
#
# Exits 0 with no output when no session is found.

set -euo pipefail

MIN_AGE_SECONDS=300
SELF_PID="${BSG_SESSION_SELF_PID:-$PPID}"

# etime_to_seconds <etime> — POSIX `ps -o etime=` is [[dd-]hh:]mm:ss.
# macOS ps has no `etimes` keyword (verified: "ps: etimes: keyword not
# found"), and macOS is the supported target, so parse the portable form.
etime_to_seconds() {
  printf '%s\n' "$1" | awk -F'[-:]' '{
    n = NF
    s = $n + 0
    m = (n >= 2) ? $(n-1) + 0 : 0
    h = (n >= 3) ? $(n-2) + 0 : 0
    d = (n >= 4) ? $(n-3) + 0 : 0
    print ((d * 24 + h) * 60 + m) * 60 + s
  }'
}

# Default enumerator: live `claude` processes with a resolvable cwd.
default_provider() {
  local pid ppid cwd rss etime age
  for pid in $(pgrep -f '^claude|/claude ' 2>/dev/null || true); do
    cwd="$(lsof -a -p "$pid" -d cwd -Fn 2>/dev/null | sed -n 's/^n//p' | head -1)"
    [ -n "$cwd" ] || continue
    ppid="$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ')"
    rss="$(ps -o rss= -p "$pid" 2>/dev/null | tr -d ' ')"
    etime="$(ps -o etime= -p "$pid" 2>/dev/null | tr -d ' ')"
    [ -n "$rss" ] || continue
    age="$([ -n "$etime" ] && etime_to_seconds "$etime" || echo 0)"
    printf '%s\t%s\t%s\t%s\t%s\n' \
      "$pid" "${ppid:-1}" "$cwd" "$((rss / 1024))" "${age:-0}"
  done
}

verdict_for() {
  local pid="$1" age="$2"
  if [ "$pid" = "$SELF_PID" ]; then echo "keep:self"; return; fi
  if [ "$age" -lt "$MIN_AGE_SECONDS" ]; then echo "keep:too-young"; return; fi
  echo "unknown"
}

main() {
  local rows collapsed pid ppid cwd rss age

  rows="$(if [ -n "${BSG_SESSION_PROVIDER:-}" ]; then
    "$BSG_SESSION_PROVIDER"
  else
    default_provider
  fi)"

  [ -n "$rows" ] || return 0

  # Collapse wrapper/child pairs: when a row's pid is another row's ppid and
  # both share a cwd, THIS row is the launcher shell — drop it and keep the
  # child, which is the real session holding the memory.
  collapsed="$(awk -F'\t' '
    NR == FNR { child_cwd[$2] = $3; next }
    { if (($1 in child_cwd) && child_cwd[$1] == $3) next; print }
  ' <(printf '%s\n' "$rows") <(printf '%s\n' "$rows"))"

  printf '%s\n' "$collapsed" | while IFS=$'\t' read -r pid ppid cwd rss age; do
    [ -n "$pid" ] || continue
    jq -nc \
      --argjson pid "$pid" \
      --argjson ppid "$ppid" \
      --arg cwd "$cwd" \
      --argjson rss_mb "$rss" \
      --argjson age_seconds "$age" \
      --arg verdict "$(verdict_for "$pid" "$age")" \
      '{pid: $pid, ppid: $ppid, cwd: $cwd, rss_mb: $rss_mb,
        age_seconds: $age_seconds, verdict: $verdict}'
  done
}

# Run only when executed. Sourcing this file defines the helpers without
# emitting anything, so the pure functions above (etime_to_seconds here,
# git_field and base_ref in later tasks) can be unit-tested directly.
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  main "$@"
fi
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash claude-skills/tests/test_session_state.sh`
Expected: `test_session_state.sh: 13 passed, 0 failed`

- [ ] **Step 5: Verify it is read-only against the live machine**

Run: `bash claude-skills/scripts/session-state.sh | jq -r '.pid + " " + .verdict'`
Expected: one line per live session, every verdict `unknown`, `keep:self` or
`keep:too-young`. No process is signalled.

- [ ] **Step 6: Commit**

```bash
git add claude-skills/scripts/session-state.sh claude-skills/tests/test_session_state.sh
git commit -m "feat(scripts): enumerate live Claude sessions as JSON lines

Injectable process provider so tests never touch a live session.
Collapses wrapper/child pairs sharing a cwd (the Superconductor launcher
shell) and classifies self and too-young sessions."
```

---

### Task 3: Git state enrichment

**Files:**
- Modify: `claude-skills/scripts/session-state.sh`
- Modify: `claude-skills/tests/test_session_state.sh`

**Interfaces:**
- Consumes: the JSON rows from Task 2.
- Produces: the same rows, plus `repo` (`owner/name` or `null`), `branch`,
  `upstream` (or `null`), `dirty` (int), `unpushed` (int),
  `merged_into_base` (bool). Verdicts `keep:dirty` and `keep:unpushed` now
  emit.

- [ ] **Step 1: Write the failing test**

Append to `claude-skills/tests/test_session_state.sh`, before the `rm -rf`:

```bash
# make_repo <path> <state> — build a fixture repo in a known state.
make_repo() {
  local path="$1" state="$2"
  mkdir -p "$path"
  git -C "$path" init -q -b main
  git -C "$path" config user.email t@t.t
  git -C "$path" config user.name t
  git -C "$path" remote add origin https://github.com/acme/widget.git
  echo base > "$path/f.txt"
  git -C "$path" add f.txt
  git -C "$path" commit -qm base
  git -C "$path" update-ref refs/remotes/origin/main HEAD
  git -C "$path" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main
  case "$state" in
    clean) : ;;
    dirty) echo changed > "$path/f.txt" ;;
    unpushed)
      git -C "$path" checkout -qb feature
      echo more > "$path/g.txt"
      git -C "$path" add g.txt
      git -C "$path" commit -qm "local only"
      ;;
  esac
}

# 5. A clean repo whose HEAD is in origin/main is reapable.
make_repo "$WORK/clean" clean
prov="$WORK/p5.sh"
make_provider "$prov" "900	1	$WORK/clean	100	60000"
out="$(BSG_SESSION_PROVIDER="$prov" BSG_SESSION_SELF_PID=999 bash "$SUT")"
assert_eq "repo parsed"    "acme/widget" "$(printf '%s' "$out" | jq -r '.repo')"
assert_eq "clean is 0"     "0"    "$(printf '%s' "$out" | jq -r '.dirty')"
assert_eq "merged is true" "true" "$(printf '%s' "$out" | jq -r '.merged_into_base')"
assert_eq "clean+merged reapable" "reapable" "$(printf '%s' "$out" | jq -r '.verdict')"

# 6. A dirty tree is kept — the build+socle-v0 case from PRD-009 §1.
make_repo "$WORK/dirty" dirty
prov="$WORK/p6.sh"
make_provider "$prov" "901	1	$WORK/dirty	100	60000"
out="$(BSG_SESSION_PROVIDER="$prov" BSG_SESSION_SELF_PID=999 bash "$SUT")"
assert_eq "dirty counted" "1" "$(printf '%s' "$out" | jq -r '.dirty')"
assert_eq "dirty is kept"  "keep:dirty" "$(printf '%s' "$out" | jq -r '.verdict')"

# 7. Commits with no upstream are kept — the clear-harbor-6a62 case.
make_repo "$WORK/unpushed" unpushed
prov="$WORK/p7.sh"
make_provider "$prov" "902	1	$WORK/unpushed	100	60000"
out="$(BSG_SESSION_PROVIDER="$prov" BSG_SESSION_SELF_PID=999 bash "$SUT")"
assert_eq "no upstream"  "null" "$(printf '%s' "$out" | jq -r '.upstream')"
assert_eq "unpushed > 0" "1"    "$(printf '%s' "$out" | jq -r '.unpushed')"
assert_eq "unpushed kept" "keep:unpushed" "$(printf '%s' "$out" | jq -r '.verdict')"

# 8. A cwd that is not a git repo yields nulls, never a crash.
mkdir -p "$WORK/plain"
prov="$WORK/p8.sh"
make_provider "$prov" "903	1	$WORK/plain	100	60000"
out="$(BSG_SESSION_PROVIDER="$prov" BSG_SESSION_SELF_PID=999 bash "$SUT")"
assert_eq "non-repo has null repo" "null" "$(printf '%s' "$out" | jq -r '.repo')"
assert_eq "non-repo is unknown" "unknown" "$(printf '%s' "$out" | jq -r '.verdict')"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash claude-skills/tests/test_session_state.sh`
Expected: FAIL — `.repo` is `null` where `acme/widget` is expected, because
the field does not exist yet.

- [ ] **Step 3: Write minimal implementation**

In `session-state.sh`, add these functions above `verdict_for`:

```bash
# git_field <cwd> <what> — echo one piece of git state, empty when absent.
git_field() {
  local cwd="$1" what="$2"
  git -C "$cwd" rev-parse --git-dir >/dev/null 2>&1 || return 0
  case "$what" in
    repo)
      # owner/name from https, ssh and scp-style remotes alike. No
      # non-greedy quantifiers — POSIX ERE has none.
      git -C "$cwd" remote get-url origin 2>/dev/null \
        | sed -E 's#\.git$##; s#^git@[^:]+:##; s#^[a-z]+://[^/]+/##'
      ;;
    branch)   git -C "$cwd" rev-parse --abbrev-ref HEAD 2>/dev/null ;;
    upstream) git -C "$cwd" rev-parse --abbrev-ref '@{u}' 2>/dev/null ;;
    dirty)    git -C "$cwd" status --porcelain 2>/dev/null | wc -l | tr -d ' ' ;;
  esac
}

# base_ref <cwd> — the remote base branch, defaulting to main.
base_ref() {
  local cwd="$1" b
  b="$(git -C "$cwd" symbolic-ref refs/remotes/origin/HEAD 2>/dev/null \
       | sed 's#.*origin/##')"
  printf '%s\n' "${b:-main}"
}

# unpushed_count <cwd> <upstream> — commits not on the upstream. With no
# upstream every commit ahead of the base counts (PRD-009 §5.4.2).
unpushed_count() {
  local cwd="$1" upstream="$2" base
  git -C "$cwd" rev-parse --git-dir >/dev/null 2>&1 || { echo 0; return; }
  if [ -n "$upstream" ]; then
    git -C "$cwd" rev-list --count "$upstream..HEAD" 2>/dev/null || echo 0
  else
    base="origin/$(base_ref "$cwd")"
    git -C "$cwd" rev-list --count "$base..HEAD" 2>/dev/null || echo 0
  fi
}

# merged_into_base <cwd> — true when HEAD is already an ancestor of base.
merged_into_base() {
  local cwd="$1"
  git -C "$cwd" rev-parse --git-dir >/dev/null 2>&1 || { echo false; return; }
  if git -C "$cwd" merge-base --is-ancestor HEAD "origin/$(base_ref "$cwd")" 2>/dev/null
  then echo true; else echo false; fi
}
```

Replace `verdict_for` with:

```bash
verdict_for() {
  local pid="$1" age="$2" dirty="$3" unpushed="$4" merged="$5" is_repo="$6"
  if [ "$pid" = "$SELF_PID" ];        then echo "keep:self";      return; fi
  if [ "$age" -lt "$MIN_AGE_SECONDS" ]; then echo "keep:too-young"; return; fi
  if [ "$is_repo" != "true" ];        then echo "unknown";        return; fi
  if [ "$dirty" -gt 0 ];              then echo "keep:dirty";     return; fi
  if [ "$unpushed" -gt 0 ];           then echo "keep:unpushed";  return; fi
  if [ "$merged" = "true" ];          then echo "reapable";       return; fi
  echo "unknown"
}
```

Replace the emitting loop. It lives **inside `main()`**, so keep it at
`main()`'s indentation and extend that function's `local` declaration to
`local rows collapsed pid ppid cwd rss age is_repo repo branch upstream dirty
unpushed merged`. The new helpers above stay at top level, beside
`etime_to_seconds`, so sourcing the file still exposes them for unit tests:

```bash
  printf '%s\n' "$collapsed" | while IFS=$'\t' read -r pid ppid cwd rss age; do
    [ -n "$pid" ] || continue
    is_repo=false
  git -C "$cwd" rev-parse --git-dir >/dev/null 2>&1 && is_repo=true
  repo="$(git_field "$cwd" repo)"
  branch="$(git_field "$cwd" branch)"
  upstream="$(git_field "$cwd" upstream)"
  dirty="$(git_field "$cwd" dirty)"; dirty="${dirty:-0}"
  unpushed="$(unpushed_count "$cwd" "$upstream")"
  merged="$(merged_into_base "$cwd")"
  jq -nc \
    --argjson pid "$pid" \
    --argjson ppid "$ppid" \
    --arg cwd "$cwd" \
    --argjson rss_mb "$rss" \
    --argjson age_seconds "$age" \
    --arg repo "$repo" \
    --arg branch "$branch" \
    --arg upstream "$upstream" \
    --argjson dirty "$dirty" \
    --argjson unpushed "$unpushed" \
    --argjson merged_into_base "$merged" \
    --arg verdict "$(verdict_for "$pid" "$age" "$dirty" "$unpushed" "$merged" "$is_repo")" \
    '{pid: $pid, ppid: $ppid, cwd: $cwd, rss_mb: $rss_mb,
      age_seconds: $age_seconds,
      repo: (if $repo == "" then null else $repo end),
      branch: (if $branch == "" then null else $branch end),
      upstream: (if $upstream == "" then null else $upstream end),
      dirty: $dirty, unpushed: $unpushed,
      merged_into_base: $merged_into_base, verdict: $verdict}'
done
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash claude-skills/tests/test_session_state.sh`
Expected: `test_session_state.sh: 24 passed, 0 failed`

- [ ] **Step 5: Commit**

```bash
git add claude-skills/scripts/session-state.sh claude-skills/tests/test_session_state.sh
git commit -m "feat(scripts): derive git state per session

Adds repo, branch, upstream, dirty, unpushed and merged_into_base, and
the keep:dirty / keep:unpushed verdicts. Fixtures encode the three real
sessions from PRD-009 section 1 that a naive reaper would have killed."
```

---

### Task 4: PR, ticket, busy and dev-server detection

**Files:**
- Modify: `claude-skills/scripts/session-state.sh`
- Modify: `claude-skills/tests/test_session_state.sh`

**Interfaces:**
- Consumes: the rows from Task 3.
- Produces: the same rows plus `pr` (`{number, state}` or `null`), `issue`
  (int or `null`), `busy` (bool), `dev_servers` (array of ints). Verdicts
  `keep:pr-open`, `keep:busy` and `keep:dev-servers` now emit. The full
  precedence ladder from Global Constraints is in force.

- [ ] **Step 1: Write the failing test**

Append to `claude-skills/tests/test_session_state.sh`, before the `rm -rf`:

```bash
# stub_gh <dir> <json> — a fake `gh` on PATH returning fixed JSON.
stub_gh() {
  local dir="$1" json="$2"
  mkdir -p "$dir"
  {
    echo '#!/usr/bin/env bash'
    printf 'printf "%%s" %q\n' "$json"
  } > "$dir/gh"
  chmod +x "$dir/gh"
}

# 9. An open PR outranks a clean, merged tree.
make_repo "$WORK/propen" clean
stub_gh "$WORK/bin_open" '{"number":2816,"state":"OPEN"}'
prov="$WORK/p9.sh"
make_provider "$prov" "904	1	$WORK/propen	100	60000"
out="$(PATH="$WORK/bin_open:$PATH" BSG_SESSION_PROVIDER="$prov" \
  BSG_SESSION_SELF_PID=999 bash "$SUT")"
assert_eq "pr number" "2816" "$(printf '%s' "$out" | jq -r '.pr.number')"
assert_eq "open pr kept" "keep:pr-open" "$(printf '%s' "$out" | jq -r '.verdict')"

# 10. A merged PR on a clean tree is reapable.
make_repo "$WORK/prmerged" clean
stub_gh "$WORK/bin_merged" '{"number":8,"state":"MERGED"}'
prov="$WORK/p10.sh"
make_provider "$prov" "905	1	$WORK/prmerged	100	60000"
out="$(PATH="$WORK/bin_merged:$PATH" BSG_SESSION_PROVIDER="$prov" \
  BSG_SESSION_SELF_PID=999 bash "$SUT")"
assert_eq "merged pr reapable" "reapable" "$(printf '%s' "$out" | jq -r '.verdict')"

# 11. A dev server running under the worktree outranks a clean tree.
make_repo "$WORK/servers" clean
stub_gh "$WORK/bin_none" ''
prov="$WORK/p11.sh"
make_provider "$prov" "906	1	$WORK/servers	100	60000"
servers_stub="$WORK/servers_stub.sh"
printf '#!/usr/bin/env bash\necho 4306\n' > "$servers_stub"
chmod +x "$servers_stub"
out="$(PATH="$WORK/bin_none:$PATH" BSG_SESSION_PROVIDER="$prov" \
  BSG_SESSION_DEV_SERVER_CMD="$servers_stub" BSG_SESSION_SELF_PID=999 bash "$SUT")"
assert_eq "dev server listed" "4306" "$(printf '%s' "$out" | jq -r '.dev_servers[0]')"
assert_eq "dev servers kept" "keep:dev-servers" "$(printf '%s' "$out" | jq -r '.verdict')"

# 12. A transcript touched just now marks the session busy.
make_repo "$WORK/busy" clean
fake_cfg="$WORK/cfg"
enc="$(printf '%s' "$WORK/busy" | tr '/.+' '---')"
mkdir -p "$fake_cfg/projects/$enc"
touch "$fake_cfg/projects/$enc/session.jsonl"
prov="$WORK/p12.sh"
make_provider "$prov" "907	1	$WORK/busy	100	60000"
out="$(PATH="$WORK/bin_none:$PATH" CLAUDE_CONFIG_DIR="$fake_cfg" \
  BSG_SESSION_PROVIDER="$prov" BSG_SESSION_SELF_PID=999 bash "$SUT")"
assert_eq "busy detected" "true" "$(printf '%s' "$out" | jq -r '.busy')"
assert_eq "busy kept" "keep:busy" "$(printf '%s' "$out" | jq -r '.verdict')"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash claude-skills/tests/test_session_state.sh`
Expected: FAIL — `.pr.number` is `null`; the fields do not exist yet.

- [ ] **Step 3: Write minimal implementation**

In `session-state.sh`, add above `verdict_for`:

```bash
# pr_json <cwd> <branch> — {"number":N,"state":"..."} or empty.
pr_json() {
  local cwd="$1" branch="$2" out
  [ -n "$branch" ] || return 0
  command -v gh >/dev/null 2>&1 || return 0
  out="$(gh pr view "$branch" --json number,state 2>/dev/null)" || return 0
  # `|| true`: under `set -e` a jq failure on empty or malformed input
  # would abort the whole run. A missing PR is normal, not an error.
  printf '%s' "$out" | jq -c 'select(.number != null) | {number, state}' 2>/dev/null || true
}

# issue_for <cwd> — the linked ticket, from the registry first.
issue_for() {
  local cwd="$1" reg="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/bsg-sessions.json"
  [ -f "$reg" ] || return 0
  jq -r --arg k "$cwd" '.[$k].issue // empty' "$reg" 2>/dev/null
}

# is_busy <cwd> — true when the transcript changed within the age floor.
is_busy() {
  local cwd="$1" cfg enc dir newest now mtime
  cfg="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
  enc="$(printf '%s' "$cwd" | tr '/.+' '---')"
  dir="$cfg/projects/$enc"
  [ -d "$dir" ] || { echo false; return; }
  newest="$(ls -t "$dir"/*.jsonl 2>/dev/null | head -1)"
  [ -n "$newest" ] || { echo false; return; }
  now="$(date +%s)"
  mtime="$(stat -f %m "$newest" 2>/dev/null || stat -c %Y "$newest" 2>/dev/null)"
  [ -n "$mtime" ] || { echo false; return; }
  if [ $((now - mtime)) -lt "$MIN_AGE_SECONDS" ]; then echo true; else echo false; fi
}

# dev_servers <pid> <cwd> — pids of live servers rooted in the worktree.
dev_servers() {
  local pid="$1" cwd="$2"
  if [ -n "${BSG_SESSION_DEV_SERVER_CMD:-}" ]; then
    "$BSG_SESSION_DEV_SERVER_CMD" "$pid" "$cwd"
    return
  fi
  pgrep -P "$pid" 2>/dev/null | while read -r child; do
    lsof -a -p "$child" -d cwd -Fn 2>/dev/null \
      | sed -n 's/^n//p' | grep -q "^$cwd" && echo "$child"
  done
}
```

Replace `verdict_for` with the full ladder:

```bash
verdict_for() {
  local pid="$1" age="$2" dirty="$3" unpushed="$4" merged="$5" \
        is_repo="$6" busy="$7" servers="$8" pr_state="$9"
  if [ "$pid" = "$SELF_PID" ];          then echo "keep:self";        return; fi
  if [ "$age" -lt "$MIN_AGE_SECONDS" ]; then echo "keep:too-young";   return; fi
  if [ "$busy" = "true" ];              then echo "keep:busy";        return; fi
  if [ -n "$servers" ];                 then echo "keep:dev-servers"; return; fi
  if [ "$is_repo" != "true" ];          then echo "unknown";          return; fi
  if [ "$dirty" -gt 0 ];                then echo "keep:dirty";       return; fi
  if [ "$unpushed" -gt 0 ];             then echo "keep:unpushed";    return; fi
  if [ "$pr_state" = "OPEN" ];          then echo "keep:pr-open";     return; fi
  if [ "$merged" = "true" ] || [ "$pr_state" = "MERGED" ] \
     || [ "$pr_state" = "CLOSED" ];     then echo "reapable";         return; fi
  echo "unknown"
}
```

In the emitting loop, compute the new values before `jq` and add them:

```bash
  pr="$(pr_json "$cwd" "$branch")"
  pr_state="$(printf '%s' "$pr" | jq -r '.state // empty' 2>/dev/null)"
  issue="$(issue_for "$cwd")"
  busy="$(is_busy "$cwd")"
  servers="$(dev_servers "$pid" "$cwd" | tr '\n' ' ')"
  servers_json="$(printf '%s' "$servers" | tr ' ' '\n' \
    | jq -Rn '[inputs | select(length > 0) | tonumber]')"
```

and extend the `jq -nc` call with:

```bash
    --argjson pr "${pr:-null}" \
    --arg issue "$issue" \
    --argjson busy "$busy" \
    --argjson dev_servers "$servers_json" \
```

adding to the object body:

```
      pr: $pr,
      issue: (if $issue == "" then null else ($issue | tonumber) end),
      busy: $busy, dev_servers: $dev_servers,
```

and pass the new arguments to `verdict_for`:

```bash
    --arg verdict "$(verdict_for "$pid" "$age" "$dirty" "$unpushed" "$merged" \
                     "$is_repo" "$busy" "$servers" "$pr_state")" \
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash claude-skills/tests/test_session_state.sh`
Expected: `test_session_state.sh: 31 passed, 0 failed`

- [ ] **Step 5: Verify the live machine still yields sane verdicts**

Run: `bash claude-skills/scripts/session-state.sh | jq -r '[.pid, .verdict, .repo] | @tsv'`
Expected: one line per session; this session appears as `keep:self`; no
verdict outside the closed vocabulary.

- [ ] **Step 6: Commit**

```bash
git add claude-skills/scripts/session-state.sh claude-skills/tests/test_session_state.sh
git commit -m "feat(scripts): resolve PR, ticket, busy state and dev servers

Completes the verdict ladder from PRD-009 section 5.4. gh is stubbed on
PATH in tests and the dev-server walk is injectable, so no test reaches a
live session or the network."
```

---

### Task 5: The `doctor` verb and skill surface

**Files:**
- Create: `claude-skills/skills/session-janitor/SKILL.md`
- Create: `claude-skills/skills/session-janitor/references/doctor.md`
- Modify: `claude-skills/INSTALL.md` (the "Available skills" table)

**Interfaces:**
- Consumes: `session-state.sh` (via `bsg_script_path` from Task 1).
- Produces: the user-facing `session-janitor` skill exposing `doctor`.

- [ ] **Step 1: Write the failing test**

No new test file — the catalogue's own meta-tests cover this surface. Run
them first to see them fail:

Run: `python3 claude-skills/tests/test_skill_invariants.py`
Expected: FAIL — `Available skills` in INSTALL.md is missing
`session-janitor`.

- [ ] **Step 2: Create the skill entrypoint**

Create `claude-skills/skills/session-janitor/SKILL.md`:

````markdown
---
name: session-janitor
description: >
  Machine-scoped janitor for live Claude Code sessions. Walks every
  running session on the host, resolves each to its repository, branch,
  PR and ticket, and reports which ones are safe to close because their
  work has already landed. Read-only in this release. Use when the user
  asks "which sessions can I close?", "clean up my Claude sessions",
  "why is Claude eating my RAM?", "session janitor", "quelles sessions
  je peux fermer", or "nettoyer mes sessions".
version: 0.1.0
model: haiku
---

# /session-janitor — live session janitor

Machine-scoped, unlike every other BSG skill: its unit of work is a host
process, not a repository. It therefore exposes **no `tick`**, is not in
`registry.json`, and is not fired by `/tick-all`. Recurrence is the
user's own `/loop`, which CLAUDE.md sanctions.

Specified in [`claude-skills/prds/009-session-janitor.md`](../../prds/009-session-janitor.md).

## Verbs

| Verb | Read-only? | What it does |
|---|---|---|
| `doctor` | ✓ Yes | Print a scorecard of every live session and its verdict. Signals nothing, mutates nothing. |

`reap`, `sync` and `reconcile` are specified in PRD-009 and ship in later
lots. This release diagnoses only.

## Quick start

Bootstrap the helper from the installed copy — the only path that exists
from an arbitrary cwd — then let it resolve everything else, preferring the
repo copy when you are working inside `bsg-stack`:

```bash
source "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/scripts/_bsg-script-path.sh"
RESOLVER="$(bsg_script_path session-state.sh)"

# The scorecard
bash "$RESOLVER" | jq .

# Just the sessions that could be closed
bash "$RESOLVER" | jq -r 'select(.verdict == "reapable")'
```

Never invoke this skill's scripts through a bare `claude-skills/scripts/…`
path: it is repo-relative and resolves only inside `bsg-stack`, which is the
defect PRD-009 §10 records.

Under `/loop 30m /session-janitor`, stay silent unless a silence-breaker
in `references/doctor.md` fires.

## How to improve this skill

The shared catalog under `claude-skills/skills/session-janitor/` is
cached into every developer's `~/.claude/` on session start. **Edits to
the cached copy are wiped on the next sync** — always PR back to
`claude-skills/skills/session-janitor/SKILL.md` in this repo.

1. Edit the file in this repo's `claude-skills/skills/session-janitor/`.
2. Run `python3 claude-skills/tests/test_skills.py` and
   `bash claude-skills/tests/test_session_state.sh`.
3. Open a PR — your local cached copy will pick up the new content
   on the next `SessionStart`.
````

- [ ] **Step 3: Create the doctor reference**

Create `claude-skills/skills/session-janitor/references/doctor.md`:

````markdown
# `doctor` — session scorecard

Strictly read-only, per ADR-002. It runs `session-state.sh`, groups the
rows by verdict, and prints one table.

## Running it

```bash
source "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/scripts/_bsg-script-path.sh"
bash "$(bsg_script_path session-state.sh)" > "${TMPDIR:-/tmp}/sessions.jsonl"
jq -r '[.pid, .verdict, (.repo // "-"), (.branch // "-"), .rss_mb] | @tsv' \
  "${TMPDIR:-/tmp}/sessions.jsonl"
```

## Output contract

```
PID     VERDICT           REPO                       BRANCH              RSS
──────  ────────────────  ─────────────────────────  ──────────────────  ─────
87075   reapable          beyond-scale-group/bsg-lbo nidara              142 MB
3692    keep:dirty        acme/nidara.ai             build+socle-v0      190 MB
61528   keep:unpushed     beyond-scale-group/bsg-lbo clear-harbor-6a62   176 MB
```

Every `keep:*` row is printed with its reason. Silence about a skipped
session is a bug — the user must be able to see why a session survived.

## Silence-breakers under `/loop`

Print nothing unless one of these holds (PRD-009 §8):

1. one or more sessions reach `reapable`
2. a session's PR is `MERGED` while `dirty > 0` — work risks being
   stranded
3. a `verdict: unknown` persists across two consecutive runs
4. total `rss_mb` across sessions crosses 6144

## What it must never do

Send a signal, run a `gh` mutation, write outside `$TMPDIR`, or delete a
worktree. Those belong to `reap`, `reconcile` and `sync`.
````

- [ ] **Step 4: Add the catalog row**

In `claude-skills/INSTALL.md`, add a row to the "Available skills" table,
keeping the table's alphabetical ordering:

```markdown
| `session-janitor` | Machine-scoped janitor for live Claude Code sessions. Resolves each running session to its repo, branch, PR and ticket via `scripts/session-state.sh`, and reports which are safe to close because their work already landed. Read-only in this release (`doctor`); `reap`, `sync` and `reconcile` ship in later lots per PRD-009. Exposes no `tick` — it is the one machine-scoped component, scheduled through `/loop`, not `/tick-all`. |
```

- [ ] **Step 5: Run the meta-tests to verify they pass**

Run:
```bash
python3 claude-skills/tests/test_skill_invariants.py
python3 claude-skills/tests/test_skills.py
```
Expected: both pass — footer present and self-referencing, catalog in sync.

- [ ] **Step 6: Run the whole suite**

Run:
```bash
for t in claude-skills/tests/test_*.sh; do bash "$t" || break; done
for t in claude-skills/tests/test_*.py; do python3 "$t" || break; done
```
Expected: no failures. In particular `test_consumers_use_resolver.sh` must
still pass — the new script uses its own helper and must not have broken the
existing `_bsg-paths.sh` contract.

- [ ] **Step 7: Commit**

```bash
git add claude-skills/skills/session-janitor claude-skills/INSTALL.md
git commit -m "feat(skills): add session-janitor with read-only doctor verb

First machine-scoped component in the catalog: no tick, absent from
registry.json, scheduled through /loop per CLAUDE.md. Diagnoses only;
reap, sync and reconcile follow in lots 2-4 of PRD-009."
```

---

## Done when

- `bash claude-skills/scripts/session-state.sh` prints one JSON line per
  live session, and this session is `keep:self`.
- `test_session_state.sh` and `test_script_path.sh` pass, with the three
  real sessions from PRD-009 §1 encoded as fixtures that assert
  `keep:dirty` and `keep:unpushed` rather than `reapable`.
- `test_skill_invariants.py` passes with `session-janitor` in the catalog.
- Nothing in the lot sends a signal or mutates GitHub.
