---
name: bsg-stack
description: >
  Umbrella skill for managing BSG agent infrastructure in any repository.
  Single entry point for the `.bsg/` directory health check, label
  bootstrapping, autopilot config inspection, and per-agent custom-doc
  status. Use when the user asks "is this repo set up for BSG?",
  "check BSG health", "are the agents configured?", "what's missing
  from .bsg/?", "bsg-stack doctor", "bsg-stack status",
  "bootstrap BSG in this repo", or "audit my agent setup".
custom-doc: .bsg/
init: >
  Bootstraps the `.bsg/` directory by orchestrating each agent's own
  --init action and creating the required GitHub labels. Per-agent
  init scripts are responsible for their own scan + draft logic;
  this skill routes the call.
version: 0.1.0
---

# /bsg-stack — BSG infrastructure umbrella

Single entry point for inspecting and bootstrapping the `.bsg/` agent
infrastructure in a repository. Implements the contract in
[`.bsg/adr/002-doctor-skill-contract.md`](../../../.bsg/adr/002-doctor-skill-contract.md):
**diagnose verbs are strictly read-only; write verbs are separate.**

## Verbs

| Verb | Read-only? | What it does |
|---|---|---|
| `doctor` | ✓ Yes | Print a health scorecard. Touches no files, opens no PRs. |
| `status` | ✓ Yes | One-line summary of agent configuration. |
| `init` | ✗ No | First-time bootstrap. Orchestrates each agent's `--init` and creates labels. Opens PR(s). |
| `update` | ✗ No | Re-run `--init` for agents whose custom doc is stale. Opens PR(s). |

`doctor` is safe to run on every `SessionStart` hook, in CI, or in a
`/loop` — it never mutates. `init` and `update` require explicit user
intent and open PRs.

## Intent routing

| User asks about... | Run | Reference |
|---|---|---|
| "Is this repo set up?", "what's missing?", "audit BSG" | `doctor` | `references/doctor.md` |
| "What agents are configured?", "BSG status" | `status` | `references/status.md` |
| "Bootstrap BSG", "set up the agents", "create the .bsg/ folder" | `init` | `references/init.md` |
| "Refresh my plan", "update stale docs" | `update` | `references/update.md` |

## Quick start

```bash
# Health scorecard — safe to run anywhere
bash claude-skills/skills/bsg-stack/scripts/doctor.sh

# One-line status
bash claude-skills/skills/bsg-stack/scripts/status.sh

# Preview what /bsg-stack init would create (no writes)
bash claude-skills/skills/bsg-stack/scripts/init.sh --dry-run

# Bootstrap a fresh repo (writes to disk, prints summary)
bash claude-skills/skills/bsg-stack/scripts/init.sh

# Refresh stale custom docs (>90 days old by default)
bash claude-skills/skills/bsg-stack/scripts/update.sh --dry-run
bash claude-skills/skills/bsg-stack/scripts/update.sh
```

## What `doctor` checks

For each row of the scorecard:

- **Each agent's `custom-doc:`** — present, missing, or stale. Resolves
  both the new `.bsg/` path and the legacy path so a partially-migrated
  repo shows up cleanly.
- **Required labels** — `needs-human-review`, `human-reviewed`, every
  bus label from `claude-skills/agents/registry.json`.
- **Autopilot config** — presence of `.bsg/AUTOPILOT.yml` (preferred)
  or `.bsg-autopilot.yml` (legacy), `enabled` flag, listed agents,
  `auto_merge` setting.

Each row reports one of:

- `✓ present` — fine, nothing to act on
- `⚠ stale | partial` — exists but needs attention (does not raise the
  exit code)
- `✗ missing — run /bsg-stack init` — must be fixed before agents can
  function

Exit code is `0` when there is nothing to act on, `1` when at least
one row is `✗`. Soft `⚠` warnings do not raise the exit code, so
`doctor` is safe to wire as a CI gate without forcing zero-warning
hygiene.

## What `init` and `update` do

`init` orchestrates the per-agent `--init` scripts shipped under
`claude-skills/skills/<skill>/scripts/init-*.sh`. For each registered
agent that has a matching init script and whose `.bsg/<DOC>` path is
not yet present, the orchestrator:

1. Runs the agent's init script and captures stdout
2. Writes the captured content to `.bsg/<DOC>`
3. Skips agents whose doc already exists (idempotent — safe to re-run)

Additionally, `init` creates the `.bsg/` skeleton (reports subdirs,
adr/, brand/), bootstraps missing GitHub labels (`needs-human-review`,
`human-reviewed`, every bus label from `agents/registry.json`), and
drops a disabled `.bsg/AUTOPILOT.yml` scaffold if neither file exists.
The orchestrator leaves the tree dirty — humans review the generated
files and commit them. Run `init --dry-run` first to preview.

`update` re-runs `--init` for agents whose custom doc is older than
the staleness threshold (default: 90 days, override with
`--threshold N`). Refreshed drafts land in `.bsg/.update-pending/`
for explicit human diff + merge — `update` never overwrites a
committed custom doc directly.

Agents whose `--init` script hasn't shipped yet (po-manager, tech-lead,
qa, md-to-office) are silently skipped during `init`/`update` and
re-listed as missing in `doctor`'s scorecard. As each script lands,
the orchestrator picks it up automatically — no SKILL.md edit needed.

## What `bsg-stack` does NOT do

- It does not edit ADRs, plans, or reports.
- It does not run agent `tick`s — that's each agent's job.
- It does not auto-fix from `doctor` findings — see ADR-002.
- It does not cross-repo sweep — repo-scoped per the on-demand
  principle in CLAUDE.md.

## How to improve this skill

The shared catalog under `claude-skills/skills/bsg-stack/` is cached
into every developer's `~/.claude/` on session start. **Edits to
the cached copy are wiped on the next sync** — always PR back to
`claude-skills/skills/bsg-stack/SKILL.md` in this repo.

1. Edit the file in this repo's `claude-skills/skills/bsg-stack/`.
2. Run `python3 claude-skills/tests/test_skills.py` to verify
   structural invariants (`custom-doc:`, `init:`, footer, catalog).
3. Open a PR — your local cached copy will pick up the new content
   on the next `SessionStart`.
