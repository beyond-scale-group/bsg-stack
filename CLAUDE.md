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
- **One-line tick receipt.** The in-chat return value of a `tick` is a
  single line of ≤~160 chars: `Tick: <state> — <PR url>` when green, or
  `⚠️ <N> sb: <shortlist> — <PR url>` when silence-breakers fire.
  Detailed narrative belongs in the committed report file, never duplicated
  in chat. Multi-line receipts break `/tick-all`'s summary format and leak
  tokens at scale (8 agents × recurring `/loop` cadence).
  Explicitly forbidden in chat output:
  1. Reasoning-narration ("Let me check the silence-breakers…", "Evaluating…")
     — reasoning happens silently; only the final receipt emits.
  2. Silence-breaker evaluation matrices (`scopeCreep: Non-empty`, `stale: Empty`)
     — that detail belongs in the report file.
  3. Contradictory receipts like `PR #94 opened. Nothing to report` — if a PR
     was opened, state what it says; if nothing to report, don't open a PR.
- **Short-circuit on same-day idempotency.** When today's report for the
  same agent is already merged and inputs haven't changed, the tick must
  skip its full aggregation and return `Tick: unchanged — see PR #NN`.
  Re-running the entire audit pipeline to produce a byte-identical PR is a
  pure token leak on recurring sweeps. `security` and `pr-comms` already
  implement this check — other agents should follow.
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

### Per-agent scope contract

Every agent frontmatter carries two lists that declare what it will
and won't attempt automatically when running in `output: commit` mode:

```yaml
auto-implements:
  - "label:bug + label:epic:* + label:safe-to-automate"
  - "LOC estimate <= 30"
never-auto-implements:
  - "files under security/*"
  - "dependency version bumps (belongs to Renovate)"
```

Three agents are now `output: commit` with live auto-implementation
pilots: **tech-lead** (#181), **seo** (#216), and **qa** (#219). Each
one picks up at most one `safe-to-automate` issue per tick, applies a
scoped fix (≤ 30 LOC / ≤ 3 files), and opens a PR with
`needs-human-review` — never self-merging. The remaining five agents
(`po-manager`, `security`, `marketing`, `storytelling`, `pr-comms`)
stay `output: pr` with explicit `never-auto-implements` clauses
documenting *why* auto-implementation is out of scope for their domain.
**po-manager** additionally carries a `delegates-to: [tech, qa, seo]`
field — it files issues routed to `output: commit` agents during its
tick (phase A.5), acting as the project's task router.

When an agent is `output: commit`, `test_skills.py` requires both lists
to carry at least one clause so the scope decision is explicit in the
diff, not implicit in the agent's narrative. When an agent is
`output: pr`, `auto-implements` stays empty and `never-auto-implements`
carries at least one clause explaining the exclusion.

### Enabling auto-implementation on a target repository

To let `output: commit` agents (tech-lead, seo, qa) auto-implement
fixes in a repository, a human must:

1. **Bootstrap the required labels** (one-time, idempotent):

   ```bash
   # Inside the target repo:
   gh label create safe-to-automate \
     --color c2e0c6 \
     --description "Human-applied: this item is safe for an agent's output:commit tick to attempt"

   # Plus the standard BSG labels if not already present:
   gh label create needs-human-review \
     --color fbca04 \
     --description "Awaiting a human decision (triage, merge, or scope)"

   for bus in $(jq -r '.agents[].bus_label' claude-skills/agents/registry.json); do
     gh label create "$bus" \
       --color 5319e7 \
       --description "Owned by @$bus (agent bus label from registry.json)"
   done
   ```

2. **Feed the backlog.** File or label issues with:
   - `label:bug` — only bugs are eligible today
   - The agent's bus label (`tech`, `seo`, or `qa`)
   - `label:human-reviewed` — proves a human triaged this (unless
     autopilot mode is enabled, see below)
   - `label:safe-to-automate` — **human-only gate** (unless autopilot
     mode is enabled, see below)
   - At least one `epic:*` label binding the issue to a plan item

3. **Run the tick** (or let `/loop` / `/schedule` drive it):

   ```bash
   # Single agent:
   claude -p "@tech-lead tick"

   # All agents in parallel:
   /tick-all
   ```

   The agent's phase (B) calls `list-pilot-candidates.sh --agent <name>`
   to find eligible issues. If a candidate exists, the agent attempts
   exactly one fix per sweep, opens a PR with `Fixes #NN` and
   `needs-human-review`, and reports a one-line receipt.

4. **Review and merge.** The human reviews the PR, merges (or closes),
   and applies `human-reviewed` via `mark-reviewed.sh <pr-number>`.

The `--repo OWNER/NAME` flag on `list-pilot-candidates.sh` allows
running against a different repository than the current working
directory — useful for cross-repo sweeps from a central session.

### Autopilot mode (`.bsg-autopilot.yml`) — #221

For repos with a steady stream of labeled issues, the per-issue
`safe-to-automate` gate adds friction. **Autopilot mode** replaces the
per-issue gate with a repo-level opt-in.

Drop a `.bsg-autopilot.yml` at the repo root:

```yaml
enabled: true
agents:
  - tech
  - seo
  - qa
budget:
  max_prs_per_tick: 1
  max_prs_per_day: 3
  max_loc_per_issue: 30
  max_files_per_issue: 3
```

When this file exists, is `enabled: true`, and lists the calling agent
in `agents:`, `list-pilot-candidates.sh` drops both the `human-reviewed`
and `safe-to-automate` label filters. Issues only need `label:bug` +
bus label + `label:epic:*` to be eligible.

The per-issue labels (`human-reviewed`, `safe-to-automate`) still work
as gates on repos without the file or for agents not listed in `agents:`.

**Daily circuit-breaker.** `pilot-circuit-breaker.sh` counts
implementation PRs opened today and compares against `max_prs_per_day`
(default: 3). When the cap is reached, phase (B) is skipped entirely —
preventing a runaway `/loop` from flooding the repo.

**What stays the same in autopilot mode:**
- Agents still open PRs with `needs-human-review` — a human merges
  (unless `auto_merge: true` is set, see below)
- `never-auto-implements` deny-list still applies
- 30 LOC / 3 files budget still applies
- One issue per agent per tick
- `output: pr` agents are unaffected

### Fully autonomous mode (`auto_merge: true`)

Adding `auto_merge: true` to `.bsg-autopilot.yml` flips the
finalization behavior of the 3 `output: commit` agents (tech-lead,
qa, seo). Instead of stopping at `needs-human-review` after `gh pr
create`, they call `auto-merge-or-flag.sh <pr> <agent>` which
squash-merges the PR, deletes the branch, and stamps
`human-reviewed`.

**This is the only documented path for an agent to apply
`human-reviewed`.** It is repo-scoped, opt-in via the autopilot
file, and contingent on the calling agent being listed under
`agents:`. Without `auto_merge: true`, the original "only humans
apply human-reviewed" invariant still holds.

**What you accept when you flip this flag:**
- Implementation PRs land on main without a human in the loop
- The 30 LOC / 3 file pilot budget becomes your only quality gate
  (CI excepted — auto-merge respects branch protection if any)
- Peer review (when configured) is purely advisory; reviews don't
  block merges
- A buggy agent or a poorly-labeled issue can pour broken commits
  into main faster than you can read PRs

bsg-stack opts in as the demonstrator repo. Other repos using the
cached agents stay on the human-review default unless they set the
flag themselves.

### Audit-to-issue pipeline (#222)

In autopilot repos, agents can file GitHub issues from their audit
findings — closing the loop from audit to implementation without
human issue-creation.

Two patterns exist:

1. **Self-filing** (`output: commit` agents): tech-lead, seo, qa scan
   their own audit for mechanically-fixable findings that match
   `auto-implements`. Filed issues become phase (B) candidates on the
   *next* tick.

2. **Delegation** (`output: pr` agents with `delegates-to`): po-manager
   scans the project state and files issues routed to the appropriate
   `output: commit` agent's bus label. The PO sees the whole picture —
   stale bugs, regression risk hotspots, plan items at risk — and
   creates targeted issues that tech/qa/seo pick up on the next sweep.

The tick gains a phase **(A.5)** between audit and implementation:

1. After phase (A) completes, the agent scans its audit for
   actionable findings (self-filing: must match `auto-implements`;
   delegation: must be mechanically routable to a target agent)
2. For each finding, it computes a dedup fingerprint
   (`<agent>:<finding-type>:<path>`) and calls `file-issue.sh` with
   `--filed-by <agent> --dedup <fingerprint>`
3. `file-issue.sh` checks for existing open issues with the same
   fingerprint (idempotent — won't create duplicates)
4. Filed issues carry `filed-by:<agent>` for traceability
5. Max `max_issues_per_tick` issues per agent per tick (default 3)
6. The filed issues become phase (B) candidates for the target
   agent on the *next* tick

**Guard rails:**
- Self-filing: only findings matching `auto-implements` are eligible
- Delegation: only mechanically-actionable findings are eligible
  (scope creep, abandoned items, and milestones stay as
  silence-breakers requiring human judgment)
- Dedup by fingerprint prevents flooding
- Rate-limited per tick
- Every agent-filed issue carries `needs-human-review`
- `filed-by:*` label distinguishes agent-filed from human-filed

### Peer review (#222 phase 3b)

In autopilot repos, agents can review each other's implementation PRs.
The tick gains a phase **(C)** after implementation:

1. Agent runs `peer-review-candidates.sh --reviewer <bus_label>`
2. The script reads the review matrix from `.bsg-autopilot.yml`:

   ```yaml
   peer_review:
     tech:
       reviews: [qa, seo]
       criteria: [code-quality, architecture-fit, naming]
     qa:
       reviews: [tech, seo]
       criteria: [test-coverage, regression-risk]
     security:
       reviews: [tech, qa, seo]
       criteria: [secret-patterns, injection-risk, dependency-safety]
   ```

3. For each eligible PR (max 2 per tick): read the diff, evaluate
   against the agent's criteria, post a review comment
4. Apply `peer-reviewed:<reviewer>` label after review
5. If issues found, also apply `needs-rework`

**Hard rules for peer review:**
- Agents NEVER merge PRs — only comment and label
- Agents NEVER apply `human-reviewed` — only humans can
- Security agent NEVER auto-approves — only flags concerns
- Peer review is advisory, not dispositive
- A PR with all peer reviews + `needs-human-review` is ready for
  quick human disposition in the weekly review

**Labels used by peer review:**

| Label | Applied by | Meaning |
|---|---|---|
| `peer-reviewed:<agent>` | Reviewing agent | This agent has reviewed the PR |
| `needs-rework` | Reviewing agent | Issues found — author should address before human review |

### Coordination bus (GitHub labels as queues)

`claude-skills/scripts/github-bus.sh` exposes `bus_claim`, `bus_lock`,
`bus_handoff`, `bus_unlock` primitives. The label schema is:

- `needs:<agent>` — inbox item waiting for that agent
- `agent:lock:<agent>` — mutex held while a tick works on the issue
- `agent:done` / `agent:blocked` — terminal pipeline states

Every agent's `tick:` starts with step 0: `source github-bus.sh`
then `bus_claim <name>`. Today the inbox is empty for every agent
(no `needs:*` labels have been applied yet), so the call is defensive
plumbing — it runs without effect. Ticket #199 tracks the rest: each
agent needs a per-role handler that decides what to do with a claimed
issue. Until that lands, tick behavior is unchanged — audit only.

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

Filing an issue from a skill — use the shared helper:

```bash
claude-skills/scripts/file-issue.sh \
  --title "<short title>" \
  --label "bug" \
  --body "..."
```

The helper always appends `needs-human-review` to the caller's `--label`
list and creates the label on the target repo if missing. Every other flag
is forwarded to `gh issue create` unchanged. This makes the convention
org-wide: any repo that has the BSG skills cached gets the behavior
without per-repo setup.

Opening a non-report PR:

```bash
gh pr create ... && gh pr edit <n> --add-label "needs-human-review"
```

A `file-pr.sh` wrapper for non-report PRs can be added later if the
pattern shows up often enough to warrant the abstraction.

### Label `human-reviewed` — proof a human touched it

Reciprocal to `needs-human-review`. Marks items where a human has made a
disposition decision: merged, closed, bound to a plan item, or commented
with a disposition. Because agents operate under the developer's own `gh`
credentials, GitHub records every agent-driven action under the human's
account. This label is the one signal that cleanly distinguishes "a human
actually looked at this" from "Claude ran `gh` as me."

**What counts as review.** A human has reviewed an item when they made a
disposition call on it:

| Action | Counts as review? |
|---|---|
| Read the diff / issue, then merge, close, or bind to a plan item | ✅ Yes |
| Remove `needs-human-review` as part of acting | ✅ Yes |
| Comment with a decision (e.g. "defer to Q3", "wontfix", "merge after CI") | ✅ Yes |
| Glance at a GitHub notification | ❌ No |
| An agent auto-applies a label | ❌ No |
| Automation (CI bots, Renovate, Dependabot) | ❌ No |

**Hard rule: only a human may apply `human-reviewed`.** Agents MUST NOT add
this label under any circumstance — with one explicit, opt-in exception:
when a repo sets `auto_merge: true` in `.bsg-autopilot.yml`, the
`auto-merge-or-flag.sh` helper applies `human-reviewed` after squash-merging
an implementation PR (see "Fully autonomous mode" above). Outside that
single helper invocation, any non-human use of the label is still a bug.
The label marks the *fact* of review, not the outcome — merge, close, and
defer all count.

How a human applies it — use the shared helper so the merge and the
label swap are one atomic action:

```bash
claude-skills/scripts/mark-reviewed.sh <pr-number>

# Equivalent manual flow (error-prone; session 2026-04-23 left 11 items
# with both labels because the --remove step was skipped):
gh pr merge <n> --squash
gh pr edit <n> --add-label human-reviewed --remove-label needs-human-review
```

For issues (close + relabel):

```bash
gh issue close <n> --reason completed
gh issue edit <n> --add-label human-reviewed --remove-label needs-human-review
```

Bootstrap the label once per repo — see `claude-skills/INSTALL.md#github-labels-used-by-bsg-agents`
for the full label table and bootstrap commands.

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
