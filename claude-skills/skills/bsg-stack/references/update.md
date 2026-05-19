# `update` — refresh stale custom docs workflow

Use this when the user asks to "refresh my plan", "update stale docs",
"the `.bsg/` docs are out of date", or runs `/bsg-stack update`. This
verb re-runs the per-agent `--init` scans for docs that exist but have
gone stale, producing fresh drafts for the human to diff and merge.

Per ADR-002 `update` is **NOT read-only**: it writes draft files. It
does **not** overwrite a committed custom doc — drafts land in
`.bsg/.update-pending/` for explicit human merge.

## Steps

1. **Preview first** to see which docs are stale:

   ```bash
   bash claude-skills/skills/bsg-stack/scripts/update.sh --dry-run
   ```

2. **Confirm with the user**, then apply:

   ```bash
   bash claude-skills/skills/bsg-stack/scripts/update.sh
   ```

   Useful flags:
   - `--threshold N` — staleness threshold in days (default `90`)
   - `--force` — refresh even fresh docs (override the threshold)

3. **What `update` does:**
   - For each agent whose `.bsg/<DOC>` exists and is older than the
     threshold, re-runs its `--init` script and writes the refreshed
     draft to `.bsg/.update-pending/<doc>.draft.md`
   - Skips docs that are still fresh, and docs not yet bootstrapped
     (those need `/bsg-stack init` first)

4. **Hand the drafts back for human merge.** Tell the user to:
   - Diff each `.bsg/.update-pending/*.draft.md` against its committed
     sibling
   - Merge or discard each draft based on what changed in the repo
   - Remove `.bsg/.update-pending/` once merged

## When to use `update` vs `init`

- `init` — the doc does **not exist yet**. First-time bootstrap.
- `update` — the doc **exists but is stale**. Refresh against the
  current repo state without clobbering human edits.

## What NOT to do

- Do NOT run `update` without a `--dry-run` preview and user consent.
- Do NOT overwrite the committed doc with the draft automatically —
  the diff-and-merge step is a human decision by design.
- Do NOT use `update` to bootstrap a missing doc — it skips
  non-existent docs. Use `init` for that.
- Do NOT leave `.bsg/.update-pending/` committed; it is a scratch
  area, not tracked content.
