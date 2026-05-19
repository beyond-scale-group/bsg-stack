# `init` — first-time bootstrap workflow

Use this when the user asks to "bootstrap BSG", "set up the agents",
"create the `.bsg/` folder", or runs `/bsg-stack init`. This verb
turns a fresh repo into one where every BSG agent has its custom doc,
the required labels exist, and an autopilot scaffold is in place.

Per ADR-002 `init` is **NOT read-only**: it creates files and may
create GitHub labels. Only run it on explicit user intent.

## Steps

1. **Preview first.** Always show the user what would change before
   touching the repo:

   ```bash
   bash claude-skills/skills/bsg-stack/scripts/init.sh --dry-run
   ```

2. **Confirm with the user**, then apply:

   ```bash
   bash claude-skills/skills/bsg-stack/scripts/init.sh
   ```

   Useful flags:
   - `--no-labels` — skip GitHub label creation (e.g. no `gh` auth)
   - `--skip <agent>` — skip one agent's `--init` (repeatable)

3. **What `init` does, in order:**
   1. Creates the `.bsg/` skeleton (`reports/<bus>/`, `adr/`, `brand/`)
   2. Runs each registered agent's `--init` script and writes the
      captured output to `.bsg/<DOC>` — idempotent, skips docs that
      already exist
   3. Bootstraps missing labels (`needs-human-review`,
      `human-reviewed`, every bus label in `agents/registry.json`)
   4. Drops a disabled `.bsg/AUTOPILOT.yml` scaffold if neither the
      new nor legacy autopilot file exists

4. **Hand the tree back to the user for review.** `init` deliberately
   leaves `.bsg/` dirty — it does not commit or open a PR. Tell the
   user to:
   - Review the generated files (replace `_placeholder_` text)
   - `git add .bsg/ && git commit`
   - Run `/bsg-stack doctor` to verify the result

## Behaviour to know

- **Idempotent.** Re-running `init` never overwrites a doc that
  already exists; it only fills gaps. Safe to re-run after adding a
  new agent.
- **Partial agents.** Agents whose `--init` script has not shipped yet
  are silently skipped and re-listed as missing in `doctor`. The
  orchestrator picks up new scripts automatically — no SKILL.md edit.

## What NOT to do

- Do NOT run `init` without a `--dry-run` preview and user consent.
- Do NOT commit or open the PR for the user unless they ask — review
  of generated drafts is a human step by design.
- Do NOT hand-edit a generated doc and then re-run `init` expecting it
  to merge — `init` skips existing docs entirely. Use `update` for
  refreshes.
