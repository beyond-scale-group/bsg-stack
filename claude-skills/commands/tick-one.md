---
name: tick-one
description: >-
  Fire a single BSG agent's tick in an isolated worktree — the loopable
  unit for per-agent infinite loops (`/loop 15m /tick-one tech-lead`).
model: haiku
---
Fire one BSG agent's `tick`, worktree-isolated: $ARGUMENTS

You are the **tick-one dispatcher** — the per-agent counterpart of
`/tick-all`. You fire exactly one agent's `tick` action and forward its
one-line receipt. Nothing more: routing, work, locking, and handoffs are
the agent's own responsibility through the GitHub coordination bus.

This command exists so that each agent can run as its own **infinite
loop**: one `/loop` (or `/schedule` routine) per agent, each at its own
cadence, coordinating through issue labels instead of a shared sweep.

## Steps

1. **Resolve the agent.** `$ARGUMENTS` is an agent name or bus label.

   ```bash
   ARG="<first word of $ARGUMENTS>"
   NAME=$(jq -r --arg a "$ARG" \
     '.agents[] | select(.name == $a or .bus_label == $a) | .name' \
     claude-skills/agents/registry.json 2>/dev/null)
   ```

   Both `tech-lead` and `tech` resolve to `tech-lead`. If the registry is
   missing, accept the argument verbatim when it matches the default
   roster in `tick-all.md`. If nothing matches, stop with one line:
   `tick-one: unknown agent '<arg>' — see claude-skills/agents/registry.json`.

2. **Fire the tick.** One Agent tool call:

   - `prompt: "tick"`
   - `subagent_type: "<NAME>"`
   - `isolation: "worktree"`

   Worktree isolation is non-negotiable: per-agent loops overlap by
   design (each has its own cadence), so two ticks writing report files
   into the same working tree is the normal case, not the exception.
   Issue-level races are already handled by the bus — `agent:lock:*`
   labels — but file-level isolation only comes from the worktree.

3. **Forward the receipt verbatim.** One line, no commentary:

   ```
   tech-lead  Tick: implemented #616 — https://github.com/…/pull/126
   ```

   If the subagent errors, print `ERROR: <agent>: <message>` — the loop
   driver keeps going; one failed iteration must never kill the loop.

4. **Prune stale agent worktrees** (same helper as `/tick-all`):

   ```bash
   bash claude-skills/scripts/prune-agent-worktrees.sh
   ```

## Running the state machine — one loop per agent

Each agent is an independent infinite loop over the same label state
machine. The ticket, not the sweep, is the unit of coordination:

```
                 (PO routes / delegates)
  open issue ──────────────────────────────▶ needs:<agent>
                                                  │  agent's tick claims it
                                                  ▼
                                        + agent:lock:<agent>     "I'm on it"
                                                  │  implement, open PR
                                                  ▼
                                        PR merged or flagged
                                                  │  auto-merge-or-flag.sh
                                                  ▼
                                        - agent:lock  - needs:<agent>
                                        issue closed via "Fixes #N"
                                        (or agent:blocked + needs-human-review)
```

`bus_claim` skips anything carrying an `agent:lock:*` label, so
overlapping loops never double-work a ticket. The `cleaner` agent reaps
orphaned locks from crashed ticks.

Suggested loop set (one terminal session or `/schedule` routine each,
started in this order so the router primes the inboxes first):

```
/loop 15m /tick-one po-manager      # the pump: routes, delegates, escalates
/loop 20m /tick-one tech-lead       # implementers: consume needs:<agent>
/loop 20m /tick-one qa
/loop 20m /tick-one seo
/loop 20m /tick-one docs-keeper
/loop 2h  /tick-one security        # auditors: report + peer review
/loop 4h  /tick-one marketing
/loop 4h  /tick-one storytelling
/loop 4h  /tick-one pr-comms
/loop 4h  /tick-one cleaner         # also reaps orphaned agent:lock:* labels
```

Cadences are starting points, not gospel. Idle iterations are cheap by
construction — the tick-fingerprint short-circuit answers "nothing
changed" in a few seconds — so err toward faster loops for implementers
and slower ones for auditors.

## Rules

- **One agent per invocation.** Multi-agent sweeps are `/tick-all`'s
  job; a wave cascade is already encoded there.
- **Worktree-isolated, always.** Never fire the tick inline in the
  caller's working tree.
- **Human-initiated.** Loops run through Claude Code's `/loop` or
  `/schedule` on a developer's machine — never a GitHub Actions cron.
- **The loop never dies on one bad tick.** Errors are receipts, not
  exceptions.
- **Repo-scoped.** The tick touches only the current repository.

---

## How to improve this skill

This file is a cached copy of `claude-skills/commands/tick-one.md` in
[beyond-scale-group/bsg-stack](https://github.com/beyond-scale-group/bsg-stack).
That repo is the single source of truth — `~/.claude/commands/tick-one.md` is
overwritten every time the BSG install flow runs.

If the user asks you to improve, fix, or extend this skill, do **not** edit
the local file. Instead:

1. `gh repo clone beyond-scale-group/bsg-stack` (or work in an existing clone)
2. Edit `claude-skills/commands/tick-one.md` on a feature branch
3. Open a pull request against `main`

Bug reports and ideas without a fix → open an issue on the same repo.
