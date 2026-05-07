# `/bsg-stack init` — first-time bootstrap

Set up a fresh repo for BSG agents. Creates the `.bsg/` skeleton,
runs each agent's `--init` (or writes a TODO stub when no per-agent
init exists yet), and bootstraps the required GitHub labels.

Defined by [ADR-002](../../../../.bsg/adr/002-doctor-skill-contract.md):
**write verb — touches the filesystem and the GitHub label set.** Does
NOT open PRs; the human or chat session opens one PR per generated
file via `open-report-pr.sh`, so each addition is reviewable.

## When to invoke

- "Bootstrap BSG in this repo"
- "Set up the agents"
- "Create the `.bsg/` folder"
- After cloning a fresh repo that has no `.bsg/` directory yet
- After adding the BSG cache to a repo that previously didn't use it

## How to invoke

```bash
# Default: every agent in registry.json, with labels
bash claude-skills/skills/bsg-stack/scripts/init.sh

# Preview without writing
bash claude-skills/skills/bsg-stack/scripts/init.sh --dry-run

# Skip GitHub label bootstrap (useful in private clones without auth)
bash claude-skills/skills/bsg-stack/scripts/init.sh --skip-labels

# Subset of agents
bash claude-skills/skills/bsg-stack/scripts/init.sh --only po,seo

# Overwrite existing custom-docs (rare — usually you want `update`)
bash claude-skills/skills/bsg-stack/scripts/init.sh --force
```

## What it does

1. **Ensure the `.bsg/` skeleton.** Creates `.bsg/`, `.bsg/adr/`,
   `.bsg/brand/templates/`, and `.bsg/reports/<agent>/` for each
   agent in the registry. Idempotent — existing dirs are left alone.

2. **Per-agent init.** For each agent in `registry.json`:
   - Read its `custom-doc:` declaration
   - If the doc already exists, skip (use `--force` or `update` to
     refresh)
   - If a per-agent init script exists at the documented path, run
     it. Today: po-manager (`skills/po/scripts/init.sh`) and
     md-to-office (`skills/md-to-office/scripts/init-brand.sh`)
   - Otherwise, write a TODO stub the human can replace by hand
     until the agent's own init lands

3. **Bootstrap GitHub labels.** Creates `needs-human-review`,
   `human-reviewed`, and every bus label from the registry. Skips
   when `gh` is missing, unauthenticated, or `--skip-labels` is set.

## Exit codes

| Code | Meaning |
|---|---|
| `0` | Every requested action succeeded or was a no-op |
| `1` | At least one per-agent init failed |
| `2` | Bad invocation |

## After it runs

The script prints a summary listing what was created. The next steps
are the human's:

1. Review the generated drafts under `.bsg/`
2. Replace bootstrapped suggestions with real content (objectives,
   keywords, narrative, etc.)
3. Commit and PR the result

For agents with no per-agent init script yet, the TODO stubs
explicitly say what to author in their place. They will be replaced
by real generators as #237 deliverable #2 rolls out per-agent.

## What it does NOT do

- **No PR opening.** The script writes files; humans open PRs. This
  preserves the on-demand, human-initiated principle.
- **No cross-repo sweep.** Runs against `$PWD` only.
- **No clobbering.** Existing custom-docs are skipped unless
  `--force`. For a periodic refresh of stale docs, use
  `/bsg-stack update`.

## Difference from `update`

| Concern | `init` | `update` |
|---|---|---|
| Target | Missing custom-docs | Existing-but-stale custom-docs |
| Fresh repo? | Yes — primary use case | No — needs existing docs |
| Default behavior on existing doc | Skip | Refresh if stale |
| Creates `.bsg/` skeleton? | Yes | No (assumes it exists) |
| Bootstraps labels? | Yes | No |
