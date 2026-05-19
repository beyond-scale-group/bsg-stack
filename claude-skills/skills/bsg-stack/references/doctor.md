# `doctor` — health scorecard workflow

Use this when the user asks "is this repo set up for BSG?", "check BSG
health", "what's missing from `.bsg/`?", "audit my agent setup", or runs
`/bsg-stack doctor`.

`doctor` is **strictly read-only** (ADR-002). It never writes a file,
opens a PR, or mutates GitHub. It is safe to run on a `SessionStart`
hook, in CI, or inside a `/loop`.

## Steps

1. **Run the scorecard** from the target repo's root:

   ```bash
   bash claude-skills/skills/bsg-stack/scripts/doctor.sh
   ```

   For a machine-readable result (CI gates, piping into another tool):

   ```bash
   bash claude-skills/skills/bsg-stack/scripts/doctor.sh --json
   ```

2. **Read the exit code.** `0` means nothing is missing. `1` means at
   least one row is `✗` and the repo needs `/bsg-stack init`. Soft `⚠`
   warnings (stale, partial, legacy path) never raise the exit code.

3. **Reply to the user** with:
   - The one-line summary (`N ok / M warn / K missing`)
   - The specific `✗` rows and their remediation (`run /bsg-stack init`)
   - Any `⚠` rows worth flagging (stale docs, legacy paths to migrate)
   - The autopilot state (enabled / disabled / legacy path / missing)

## What to highlight

- `✗ missing` custom docs — these block the owning agent from
  producing useful output until bootstrapped.
- Missing required labels (`needs-human-review`, `human-reviewed`, bus
  labels) — agents cannot route work without them.
- `⚠ stale` docs older than 90 days — suggest `/bsg-stack update`.
- Legacy paths (`po/PLAN.md`, `.securityignore`, etc.) — suggest
  migrating to the `.bsg/` convention (see ADR-001).

## What NOT to do

- Do NOT auto-fix anything from `doctor` findings. `doctor` diagnoses;
  `init` / `update` write. This separation is the ADR-002 contract.
- Do NOT open a PR, create a label, or write a file from this verb.
- Do NOT run agent `tick`s — that is each agent's own job.
- Do NOT sweep other repos — `doctor` is repo-scoped by design.
