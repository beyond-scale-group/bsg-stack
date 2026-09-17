# `doctor` — session scorecard

Strictly read-only, per ADR-002. It runs `session-state.sh`, groups the
rows by verdict, and prints one table.

## Running it

```bash
source "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/scripts/_bsg-script-path.sh"
bash "$(bsg_script_path session-state.sh)" > "${TMPDIR:-/tmp}/sessions.jsonl" \
  || { echo "session-state.sh failed"; exit 1; }
jq -r '[.pid, .verdict, (.repo // "-"), (.branch // "-"), .rss_mb] | @tsv' \
  "${TMPDIR:-/tmp}/sessions.jsonl"
```

Check that exit status. The redirect sends everything to a file, so a
resolver that dies mid-sweep looks exactly like a machine with no
sessions: an empty table, no error. The resolver now degrades a bad
field on a bad row rather than losing the batch, but an unchecked
redirect would still hide any future failure the same way.

## What counts as a dev server

A descendant of the session, rooted in its worktree, that is **listening
on a TCP port** (PRD-009 §5.4.6). Not merely any child with that cwd:
every session spawns MCP stdio helpers under its worktree, and counting
those made 27 of 31 sessions `keep:dev-servers`, which silenced every
rung of the ladder below it. A `keep:dev-servers` row always names the
pids it is protecting.

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
