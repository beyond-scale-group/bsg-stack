---
name: tick-all
description: >-
  Run a full tick sweep across all registered BSG agents for this repository.
model: haiku
---
Run a full tick sweep across all registered BSG agents for this repository.

You are the **tick-all dispatcher**. Your job is to fire every registered
BSG agent's `tick` action in three cascading waves, collect their one-line
results, and print a brief sweep summary. Nothing more — routing, work, and
handoffs are each agent's own responsibility.

Why waves and not one flat parallel batch: in a flat sweep the PO routes
labels and files issues *while* the implementers are already checking for
candidates — anything the PO routes is only picked up on the **next**
sweep, so tickets take two sweeps to travel from routing to implementation.
The cascade lets a ticket flow PO → implementer → peer review inside a
single `/tick-all` run. Pass `--flat` to force the legacy single-wave
parallel sweep (all agents at once, cheapest wall-clock).

## Steps

1. **Load the registry and partition the waves.**

   ```bash
   REGISTRY=$(cat claude-skills/agents/registry.json 2>/dev/null || echo '{"agents":[]}')
   ROUTERS=$(echo "$REGISTRY" | jq -r '.agents[] | select(.name == "po-manager") | .name')
   IMPLEMENTERS=$(echo "$REGISTRY" | jq -r '.agents[] | select(.output == "commit") | .name')
   AUDITORS=$(echo "$REGISTRY" | jq -r '.agents[] | select(.output != "commit" and .name != "po-manager") | .name')
   ```

   If `claude-skills/agents/registry.json` is absent, fall back to the
   hardcoded default list at the bottom of this file (po-manager is the
   router; `output: commit` rows are implementers; the rest are auditors).

2. **Fire the waves.** Every Agent tool call in every wave uses:

   - `prompt: "tick"`
   - `subagent_type: "<name>"`
   - `isolation: "worktree"`
   - `run_in_background: false` — **synchronous, always.** Waves are
     ordered by awaiting the previous wave's receipts; backgrounded
     ticks break that ordering, and in headless runs (`claude -p
     "/tick-all"`) the session terminates at the background-wait
     ceiling (~600 s) before the sweep finishes, orphaning the agents
     mid-wave. Parallelism within a wave comes from batching the
     synchronous calls in one tool-use block, not from backgrounding.

   **Wave 1 — routing.** Fire `po-manager` alone and wait for its
   receipt. Its routing phases (label normalization, orphan triage,
   delegation) are what put candidates in the implementers' inboxes.

   **Wave 2 — implementation.** Fire all `output: commit` agents
   (tech-lead, qa, seo, docs-keeper) in parallel — one tool-use block,
   do not wait between them. They consume the candidates wave 1 just
   routed.

   **Wave 3 — audit + peer review.** Fire the remaining `output: pr`
   agents (security, marketing, storytelling, pr-comms, cleaner) in
   parallel. Running them last means their peer-review phase sees the
   implementation PRs wave 2 just opened, not last sweep's.

   With `--flat`: fire all registered agents in a single parallel
   tool-use block instead (the pre-cascade behavior).

   The `isolation: "worktree"` flag is essential: it gives each agent
   its own git worktree branched off the current HEAD. Without it,
   parallel agents writing `po/`, `security/`, `qa/`,
   `tech/`, `seo/`, `marketing/`, `brand/`, and `comms/` into the
   same working tree produce cross-contamination — a sibling's
   untracked output dir can block another agent's
   `open-report-pr.sh` call, and race conditions on
   `git checkout -B` are real. With worktrees, each tick is
   hermetic: writes stay local, the report branch is created off a
   clean tree, and the PR merges back into `main` the normal way.

   Clean-up is automatic: the Agent runtime tears down the worktree
   once the agent returns (unless it made unstaged changes, in
   which case the runtime reports the worktree path for inspection).

3. **Collect results.**

   Each agent returns a one-line tick receipt (e.g.
   `Tick: all green, report at <PR url>` or a silence-breaker summary).
   If a subagent errors, record `ERROR: <agent>: <message>` and continue.

4. **Print the sweep summary.**

   ```
   ## tick-all — 2026-04-22T14:00:00Z

   wave 1 — routing
   ✅ po-manager   Tick: routed 3 — see PR #123

   wave 2 — implementation
   ✅ tech-lead    Tick: implemented #616 — https://github.com/…/pull/126
   ✅ qa           Tick: unchanged — see PR #124 · pilot: no candidates

   wave 3 — audit + peer review
   ⚠️ seo         Tick: 3 pages missing canonical — report at …/pull/125
   ❌ marketing    ERROR: registry entry missing bus_label

   6 agents swept in 3 waves, 74 s
   ```

   Prefix: ✅ green (no silence-breaker), ⚠️ silence-breaker fired, ❌ error.
   Total elapsed time on the last line. With `--flat`, drop the wave
   headers and keep the flat list.

5. **Prune stale agent worktrees.**

   After the summary prints, call the shared cleanup helper:

   ```bash
   bash claude-skills/scripts/prune-agent-worktrees.sh
   ```

   Why this exists: the Agent runtime auto-removes a worktree only when
   its working tree is clean. Every tick that commits a report leaves a
   non-clean worktree behind (the report commit itself), which the
   runtime then preserves locked "for inspection." Those pile up across
   sweeps — 8 per sweep, hundreds per day at a `/loop 5m /tick-all`
   cadence.

   The helper removes any `.claude/worktrees/agent-*` worktree whose
   branch is either a pure scratch branch (`worktree-agent-*`) or a
   `reports/*` branch whose PR is already MERGED or CLOSED. It leaves
   everything else alone — live branches, dirty trees with
   unrecognized names, main, other worktrees — so it's safe to run
   at every tick. It emits a one-line `pruned=N kept=M` summary.

## GitHub bus inbox processing

Agents that implement the GitHub coordination bus additionally process their
issue inbox during `tick`. The bus primitives live in
`claude-skills/scripts/github-bus.sh`. `tick-all` itself does NOT touch
the bus — it only orchestrates the sweep. Each agent's own `tick` is
responsible for:

1. Sourcing `github-bus.sh`
2. Calling `bus_claim <bus_label>` to get its inbox
3. Locking, working, and handing off each issue

See `docs/label-taxonomy.md` for the full label schema and
`claude-skills/scripts/github-bus.sh` for the API.

## Rules

- **Repo-scoped.** Each agent's tick runs inside the current repo —
  specifically inside its own worktree of the repo — and touches only
  that repo.
- **Worktree-isolated.** Every agent gets `isolation: "worktree"`.
  Parallel ticks must never share a working tree.
- **Waves are barriers, not dependencies.** A wave-1 error (or a
  `Tick: unchanged` receipt) never cancels waves 2–3 — record the
  receipt and keep going. The cascade only orders the start times.
- **Human-initiated.** For recurring sweeps, use `/loop 30m /tick-all` or
  `/schedule` — never a GitHub Actions cron.
- **Idempotent.** Re-running is safe: `open-report-pr.sh` reuses existing
  open branches, and `bus_claim` skips locked issues.
- **No chat noise when all green.** Forward each agent's verbatim receipt;
  don't add commentary when everything is healthy.

## Default agent registry

Used when `claude-skills/agents/registry.json` is absent:

| Agent name     | bus_label     | output | wave |
|----------------|---------------|--------|------|
| `po-manager`   | `po`          | pr     | 1    |
| `tech-lead`    | `tech`        | commit | 2    |
| `qa`           | `qa`          | commit | 2    |
| `seo`          | `seo`         | commit | 2    |
| `docs-keeper`  | `docs-keeper` | commit | 2    |
| `security`     | `security`    | pr     | 3    |
| `marketing`    | `marketing`   | pr     | 3    |
| `storytelling` | `storytelling`| pr     | 3    |
| `pr-comms`     | `pr-comms`    | pr     | 3    |
| `cleaner`      | `cleaner`     | pr     | 3    |

---

## How to improve this skill

This file is a cached copy of `claude-skills/commands/tick-all.md` in
[beyond-scale-group/bsg-stack](https://github.com/beyond-scale-group/bsg-stack).
That repo is the single source of truth — `~/.claude/commands/tick-all.md` is
overwritten every time the BSG install flow runs.

If the user asks you to improve, fix, or extend this skill, do **not** edit
the local file. Instead:

1. `gh repo clone beyond-scale-group/bsg-stack` (or work in an existing clone)
2. Edit `claude-skills/commands/tick-all.md` on a feature branch
3. Open a pull request against `main`

Bug reports and ideas without a fix → open an issue on the same repo.
