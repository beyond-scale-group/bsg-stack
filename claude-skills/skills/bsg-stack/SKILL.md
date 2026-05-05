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
bash claude-skills/skills/bsg-stack/scripts/doctor.sh --status

# Bootstrap a fresh repo (interactive, opens PRs)
@bsg-stack init
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

## What `init` and `update` do (when implemented)

`init` orchestrates per-agent `--init` actions. The agents' frontmatter
declares what each one's `--init` generates (see the `init:` field in
each agent file). Today only `md-to-office` ships a working `--init`;
the others have the contract documented but not the implementation.
`init` lists what would be generated in dry-run mode until per-agent
scripts catch up — see `references/init.md` for status.

`update` is a future verb that re-runs `--init` for agents whose
custom doc is stale (older than 90 days, or when README has materially
changed since the doc was last regenerated). Not yet implemented.

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
