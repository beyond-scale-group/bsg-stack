# `status` — quick configuration view workflow

Use this when the user asks "what agents are configured?", "BSG
status", "quick BSG check", or runs `/bsg-stack status`. This is the
fast, glanceable counterpart to `doctor` — same data, one line.

`status` is **strictly read-only** (ADR-002). It is a thin wrapper
around `doctor.sh --status` and shares its exit-code contract.

## Steps

1. **Run the one-line summary** from the target repo's root:

   ```bash
   bash claude-skills/skills/bsg-stack/scripts/status.sh
   ```

   For a machine-readable result:

   ```bash
   bash claude-skills/skills/bsg-stack/scripts/status.sh --json
   ```

2. **Read the exit code.** Identical to `doctor`: `0` when nothing is
   missing, `1` when at least one row is `✗`. Warnings do not raise it.

3. **Reply to the user** with the single summary line, e.g.
   `BSG: 6 ok / 2 warn / 1 missing (autopilot: disabled)`. If the user
   wants the breakdown behind those numbers, run `doctor` (see
   `references/doctor.md`) instead of paraphrasing.

## When to use `status` vs `doctor`

- `status` — a quick pulse: a `SessionStart` greeting, a CI gate, or a
  `/loop` heartbeat where the full table would be noise.
- `doctor` — the user wants the per-agent breakdown and remediation
  steps.

## What NOT to do

- Do NOT write files, open PRs, or create labels — same read-only
  contract as `doctor`.
- Do NOT reconstruct the full scorecard from the summary line; if the
  user needs detail, call `doctor`.
