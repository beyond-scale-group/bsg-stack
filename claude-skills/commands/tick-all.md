Run a full tick sweep across all registered BSG agents for this repository.

You are the **tick-all dispatcher**. Your job is to fire every registered
BSG agent's `tick` action in parallel, collect their one-line results, and
print a brief sweep summary. Nothing more — routing, work, and handoffs are
each agent's own responsibility.

## Steps

1. **Load the registry.**

   ```bash
   REGISTRY=$(cat claude-skills/agents/registry.json 2>/dev/null || echo '{"agents":[]}')
   AGENTS=$(echo "$REGISTRY" | jq -r '.agents[].name')
   ```

   If `claude-skills/agents/registry.json` is absent, fall back to the
   hardcoded default list at the bottom of this file.

2. **Fire each agent's tick in parallel.**

   Spawn one Agent tool call per entry with `prompt: "tick"` and
   `subagent_type: "<name>"`. Do **not** wait for one to finish before
   starting the next — send all calls in the same tool-use block.

3. **Collect results.**

   Each agent returns a one-line tick receipt (e.g.
   `Tick: all green, report at <PR url>` or a silence-breaker summary).
   If a subagent errors, record `ERROR: <agent>: <message>` and continue.

4. **Print the sweep summary.**

   ```
   ## tick-all — 2026-04-22T14:00:00Z

   ✅ po-manager   Tick: all green, report at https://github.com/…/pull/123
   ✅ security     Tick: all green, report at https://github.com/…/pull/124
   ⚠️ seo         Tick: 3 pages missing canonical — report at …/pull/125
   ❌ marketing    ERROR: registry entry missing bus_label

   4 agents swept in 18 s
   ```

   Prefix: ✅ green (no silence-breaker), ⚠️ silence-breaker fired, ❌ error.
   Total elapsed time on the last line.

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

- **Repo-scoped.** Each agent's tick runs inside the current repo's working
  directory and touches only that repo.
- **Human-initiated.** For recurring sweeps, use `/loop 30m /tick-all` or
  `/schedule` — never a GitHub Actions cron.
- **Idempotent.** Re-running is safe: `open-report-pr.sh` reuses existing
  open branches, and `bus_claim` skips locked issues.
- **No chat noise when all green.** Forward each agent's verbatim receipt;
  don't add commentary when everything is healthy.

## Default agent registry

Used when `claude-skills/agents/registry.json` is absent:

| Agent name     | bus_label     | output |
|----------------|---------------|--------|
| `po-manager`   | `po`          | pr     |
| `security`     | `security`    | pr     |
| `qa`           | `qa`          | pr     |
| `tech-lead`    | `tech`        | pr     |
| `seo`          | `seo`         | pr     |
| `marketing`    | `marketing`   | pr     |
| `storytelling` | `storytelling`| pr     |
| `pr-comms`     | `pr-comms`    | pr     |

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
