# `/bsg-stack doctor` — health scorecard

Read-only audit of `.bsg/` agent infrastructure. Touches no files,
opens no PRs, makes no GitHub mutations. Safe to run on every
`SessionStart` hook, in CI, or in a `/loop`.

Defined by [ADR-002](../../../../.bsg/adr/002-doctor-skill-contract.md).

## When to invoke

- "Is this repo set up for BSG?"
- "What's missing from `.bsg/`?"
- "Audit my BSG configuration"
- "Are the agents configured?"
- Any read-only diagnosis of repo bootstrap state

## How to invoke

```bash
bash claude-skills/skills/bsg-stack/scripts/doctor.sh
bash claude-skills/skills/bsg-stack/scripts/doctor.sh --status   # one-line
bash claude-skills/skills/bsg-stack/scripts/doctor.sh --json     # for pipes / CI
```

## What it checks

For each agent in `claude-skills/agents/registry.json`:

- **Custom doc presence.** Resolves the agent's `custom-doc:` via
  `_bsg-paths.sh` (`.bsg/<DOC>` preferred, legacy folder as fallback).
  Reports `✓ present`, `⚠ stale (Nd old)`, `⚠ legacy path — migrate
  to .bsg/`, or `✗ missing — run /bsg-stack init`.
- **GitHub labels.** `needs-human-review`, `human-reviewed`, every
  bus label from the registry. Reports `✓ exists` or `✗ missing`.
- **Autopilot config.** Presence of `.bsg/AUTOPILOT.yml` (preferred)
  or `.bsg-autopilot.yml` (legacy).

## Exit codes

| Code | Meaning |
|---|---|
| `0` | Every checked row is `✓` or `⚠` (warnings don't fail) |
| `1` | At least one `✗ missing` row |
| `2` | Bad invocation (unknown flag, missing registry, …) |

The `1` exit lets you wire `doctor.sh` into a CI gate without parsing
output: `bash doctor.sh || echo "BSG bootstrap incomplete"`.

## Output glyphs

- `✓ present` — file/label/setting exists and is fresh
- `⚠` — exists but stale, partial, or on a legacy path
- `✗ missing` — must be created; suffix names the remediation

## Output modes

- **Default** — fixed-width scorecard table, one section per concern
  (agents, labels, autopilot)
- **`--status`** — one line: `BSG: 7/9 ✓, 1 ⚠, 1 ✗ — run /bsg-stack init`
- **`--json`** — machine-readable for CI:
  ```json
  {
    "agents": [{"name": "po-manager", "doc": ".bsg/PLAN.md", "status": "ok"}, …],
    "labels": [{"name": "needs-human-review", "status": "ok"}, …],
    "autopilot": {"path": ".bsg/AUTOPILOT.yml", "status": "ok"}
  }
  ```

## What it does NOT do

- **No mutations.** Read-only by contract. To fix gaps, run
  `/bsg-stack init` (fresh repos) or `/bsg-stack update` (refresh
  stale docs).
- **No issue filing.** Findings are visible in the scorecard; the
  human or umbrella skill decides what to do with them.
- **No cross-repo sweep.** Runs against `$PWD` only. For a fleet view,
  invoke from each repo separately.
