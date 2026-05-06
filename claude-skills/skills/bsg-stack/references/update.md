# `/bsg-stack update` — refresh stale `.bsg/` docs

Re-runs each agent's `--init` for custom-docs that have grown stale.
Pairs with `init`: `init` creates fresh docs, `update` refreshes
existing ones.

Defined by [ADR-002](../../../../.bsg/adr/002-doctor-skill-contract.md):
**write verb — touches the filesystem.** Does NOT open PRs.

## When to invoke

- "Refresh my plan / docs / custom-docs"
- "Update stale `.bsg/` files"
- "Re-run init for outdated docs"
- After a long quiet period when the repo's milestones / labels /
  README have drifted from the bootstrapped drafts
- On a `/loop` — `update` is safe to schedule, since it's a no-op
  for fresh docs and idempotent for stale ones

## How to invoke

```bash
# Default: 90-day staleness threshold
bash claude-skills/skills/bsg-stack/scripts/update.sh

# Preview
bash claude-skills/skills/bsg-stack/scripts/update.sh --dry-run

# Tighter threshold
bash claude-skills/skills/bsg-stack/scripts/update.sh --max-age-days 30

# Subset of agents
bash claude-skills/skills/bsg-stack/scripts/update.sh --only po,seo
```

## What it does

For each agent in `registry.json`:

1. **Resolve the custom-doc** via `_bsg-paths.sh` (`.bsg/<DOC>` first,
   legacy folder as fallback)
2. **If the doc is missing** → skip with a note (`run /bsg-stack
   init`); `update` does not create fresh docs
3. **Compute mtime in days.** If `≤ --max-age-days` (default 90),
   skip silently
4. **If stale**, re-run the per-agent init script with `--force`. If
   the agent has no init script yet, print a "manual refresh
   required" note and move on

## Why a separate verb

The `init` / `update` split exists because their semantics differ
sharply:

- `init` is the bootstrap — it expects no doc to exist and creates
  one. Running `init` on a configured repo is wrong (clobbers
  human-edited content) without `--force`.
- `update` is the refresh — it expects the doc to exist and only acts
  when it's old. Running `update` on a fresh repo is a no-op (every
  doc is missing).

Folding them into one verb would force every caller to know which
state the repo is in. Splitting lets `doctor` recommend the right one.

## Staleness threshold

Default: **90 days.** Override with `--max-age-days N`. The threshold
is uniform across agents — there is no per-agent override yet because
no agent has presented a domain-specific reason for one.

Common adjustments:

- `--max-age-days 30` for fast-moving repos where milestones change
  monthly
- `--max-age-days 180` for stable repos where the narrative / design
  rarely shifts

## Exit codes

| Code | Meaning |
|---|---|
| `0` | Every requested action succeeded or was a no-op |
| `1` | At least one per-agent re-init failed |
| `2` | Bad invocation |

## What it does NOT do

- **Never creates fresh docs.** That's `init`'s job. `update` only
  refreshes existing ones.
- **Never opens PRs.** The script writes files; humans open PRs.
- **Never touches GitHub labels.** That's `init`. Once labels exist
  they don't go stale.
- **No cross-repo sweep.** Runs against `$PWD` only.
