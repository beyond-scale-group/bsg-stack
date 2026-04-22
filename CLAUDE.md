# CLAUDE.md

Project instructions for [Claude Code](https://claude.com/claude-code) sessions
in this repository.

## What this repo is

`beyond-scale-group/bsg-stack` — source of truth for the BSG shared Claude Code
**commands, skills, and subagents**, plus the Renovate presets consumed across
the org. Files under `claude-skills/` are cached into every developer's
`~/.claude/` via the installer; files under `renovate/` are referenced by
tracked repos' `renovate.json`.

## Design principles for agents and skills

### Pure Claude-driven, per-repo, on-demand

Every agent or skill in `claude-skills/` runs **only when a human asks for it**,
from inside the target repository. Primary invocation is a subagent mention or
slash command:

```
@po-manager give me the full status
/babysit bun run build
```

Headless one-shot for scripted use:

```bash
claude -p "@po-manager run a full status report and commit the results"
```

**Do not add CI automation for these agents.** No reusable GitHub Actions
workflows, no scheduled cron jobs, no `repo_dispatch` orchestrators. Every run
must be initiated by a human so each run is visible, intentional, and
repo-scoped. If persistent state is needed, commit the agent's output to the
target repo at a stable path (e.g. `po/`) — git history is the trend store.

Escalating to CI automation requires explicit approval.

### The `tick` convention (periodic agent runs)

Agents that produce reports or check state should expose a `tick` action — a
single conventional verb across the catalog for "do your periodic job now."

```
@po-manager tick
@github-compliance tick
```

Semantics every `tick` must follow:

- **Idempotent and silent by default.** Write the dated output to the repo
  (`po/reports/YYYY-MM-DD-*.md`, `compliance/reports/...`), commit it, and
  return a short summary only if something needs human attention (risk flag,
  drift crossing a threshold, new blocker). No news = no chat noise.
- **Never pause for consent.** A `tick` on an `output: pr` agent must open
  the report PR without asking. If a silence-breaker requires a human
  decision, the report documents it and the PR *is* the consent surface —
  reviewers act on the finding by merging, commenting, or closing. Pausing
  mid-sweep with "do you want me to open a PR?" breaks `/tick-all` and is
  a bug. Consent belongs to explicit, non-`tick` user asks.
- **No CI cron.** `tick` is still human-initiated per the on-demand principle
  above. Scheduled execution goes through Claude Code's own `/schedule` or
  `/loop` (which the user sets up explicitly on their machine) — not through
  GitHub Actions, Renovate, or any org-level scheduler.
- **Repo-scoped.** `tick` runs inside one repo's working directory and touches
  only that repo. Multi-repo sweeps are out of scope for `tick`.
- **Worktree-isolated in parallel sweeps.** When `/tick-all` fires every
  agent in parallel, each agent runs in its own git worktree
  (`isolation: "worktree"`) branched off the current HEAD. A single
  working tree can't safely host eight agents writing into `po/`,
  `security/`, `qa/`, `tech/`, `seo/`, `marketing/`, `brand/`, and
  `comms/` concurrently — worktrees make each tick hermetic and let
  `open-report-pr.sh` keep its strict clean-tree guard.

Implementation tracked in beyond-scale-group/bsg-stack#33. Until that
lands, agents document `tick` as a planned alias in their frontmatter but
route to existing verbs (e.g. `po-manager tick` → full status report).

### BSG-managed settings in `~/.claude/settings.json`

`claude-skills/settings.json` is merged by the BSG updater into each
developer's `~/.claude/settings.json` on every run. The merge is narrow —
only the keys listed in `BSG_MANAGED_SETTINGS_KEYS` and
`BSG_MANAGED_MCP_SERVERS` inside `update-bsg-skills.py` are touched; all
other user-owned settings are preserved. Today that's:

- `autoMemoryEnabled: false` — disables the Claude Code auto-memory system
  so durable context lives in `CLAUDE.md` files and committed agent outputs
  (e.g. `po/`) rather than a per-project memory store.
- `mcpServers.context7` — pre-registers the Context7 MCP server so library
  documentation lookups are available automatically in every session.

See [`claude-skills/INSTALL.md`](claude-skills/INSTALL.md#settings-merged-into-claudesettingsjson)
for the full list of managed keys and how to add or remove one.

### Data lives in the target repo, not centrally

Agents that produce reports or plans write them into the repo they were invoked
in, at a root-level folder (e.g. `po/`), and commit them. No central portfolio
folder, no cross-repo database. "One repo, one agent, one plan."

### Reporting agents output via auto-merge PRs

Agents that **generate reports** (po-manager, github-compliance, future
similar agents) must not push their output directly to `main`. Every generated
file lands through a Pull Request opened by the shared helper:

```
claude-skills/scripts/open-report-pr.sh <file> --agent <agent-name>
```

The helper creates a branch `reports/<agent>/<slug>`, commits the file,
opens a PR, and enables auto-merge (squash). If the target repo doesn't have
the prerequisites for auto-merge (Settings → Allow auto-merge + a branch
protection rule with required checks or reviews), the helper falls back to a
direct squash merge — the report still lands on `main`, just without the
gate.

Why this is the rule even though it's more ceremony than a direct commit:

- Every report has a PR URL to link from Slack / notifications
- CI / branch-protection checks run on the report before it lands
- The PR list **is** the report archive — searchable, taggable, labelable
- Nothing automated bypasses the repo's merge gate by accident

Agents declare their output mode in frontmatter:

```yaml
output: pr        # reporting agents (po-manager, github-compliance, …)
output: commit    # agents that mutate source code directly (rare; explicit opt-out)
output: chat      # agents that only return a chat summary (no persisted artifact)
```

A unit test in `claude-skills/tests/test_skills.py` enforces that every agent
declares a valid `output` field.

### Label `needs-human-review` for human-gated items

Anything that requires a human decision — triage, merge, or scope — must carry
the `needs-human-review` label. This makes the triage queue a single filter:

```
is:open label:needs-human-review
```

When to add it:

- **Always** on an issue filed by an agent (bug, enhancement, audit finding).
  The person who merges or closes the issue removes the label as part of
  acting on it.
- **Always** on a PR that does not auto-merge — contentful code changes,
  docs PRs, convention updates. Report PRs opened via
  `open-report-pr.sh` skip the label because they auto-merge.
- **Never** removed automatically. Humans own the transition out of
  "needs review."

Filing an issue from a skill:

```bash
gh issue create \
  --title "<short title>" \
  --label "bug,needs-human-review" \
  --body "..."
```

Opening a non-report PR:

```bash
gh pr create ... && gh pr edit <n> --add-label "needs-human-review"
```

If the label doesn't exist in a repo, create it once:

```bash
gh label create "needs-human-review" \
  --color fbca04 \
  --description "Awaiting a human decision (triage, merge, or scope)"
```

### Scripts before LLM

Inside a skill, deterministic bash + jq scripts do the aggregation and
computation (counts, risk flags, tree walks). The LLM only narrates the
results. Agents should never re-derive numbers the scripts already emit.

## Contributing to the shared catalog

Files in `~/.claude/` on a developer's machine are cached copies — they get
overwritten on every install or SessionStart run. Always PR back here instead
of editing the local copies. See [`claude-skills/INSTALL.md`][install] for the
full add-a-skill checklist and required footer.

[install]: claude-skills/INSTALL.md#adding-a-new-command-skill-or-agent-to-the-catalog
