# po/PLAN.md — beyond-scale-group/bsg-stack

## Mission

`bsg-stack` is the single source of truth for Claude Code commands, skills,
and subagents shared across the BSG org. Its job: keep the catalog healthy,
install reliably on every developer machine, and run agent sweeps that are
cheap, idempotent, and trustworthy.

---

## Epics

### E1 — tick-hygiene
> Make every agent tick cheap, one-line, and idempotent.

The recurring `/tick-all` sweep currently costs ~131–160 k tokens per run
with an 8-agent roster. Three failure modes compound: receipts exceed the
one-line contract, same-day reports are regenerated in full, and no budget
gate exists on the dispatcher. This epic drives all three to zero.

**Binds:** [epic:#90] [epic:#91] [epic:#97]

**Done when:** a no-change `/tick-all` sweep costs < 10 k tokens and all 8
agents return a single-line receipt.

---

### E2 — install-reliability
> The updater must never abort mid-sync; every agent must land on every
> developer machine.

A dangling symlink under `~/.claude/` currently crashes
`update-bsg-skills.py` before it reaches the `agents/` section, silently
leaving 7 of 8 agents uninstalled. Per-section error isolation and
resilient path handling are the fix.

**Binds:** [epic:#67]

**Done when:** `update-bsg-skills.py` completes all four sections even if
one path is unresolvable, and all 8 agents are present in
`~/.claude/agents/` after a fresh install on a machine with path
conflicts.

---

### E3 — agent-pr-contract
> Every reporting agent must open a PR via `open-report-pr.sh`; tick
> receipts must contain a GitHub URL, never a local path.

`tech-lead` currently returns a worktree-local path on some ticks; the
2026-04-23 sweeps showed `security` and `storytelling` also fall back to
worktree paths in the short-circuit code path. PR #92 codifies the
one-line receipt and same-day short-circuit conventions in `CLAUDE.md`
so future agents can't diverge silently.

**Binds:** [epic:#84] [tag:pr-92]

**Done when:** all 8 agents' tick receipts contain a
`https://github.com/…/pull/NN` URL; no agent writes a local path to the
receipt line.

---

### E4 — catalog-growth
> Grow the agent catalog with backlog-hygiene and intent-file
> capabilities, and sharpen the `/po` skill's bootstrap path.

Three greenfield features: the `@cleaner` agent for label/backlog
hygiene, per-domain intent files (`ROADMAP.md`, `ARCHITECTURE.md`, etc.)
that give agents repo-specific context without coupling them to a shared
config format, and a smarter `bootstrap-plan.sh` that seeds epics from
open issues when milestones are absent. All are enhancements with no
current blockers from E1–E3.

**Binds:** [epic:#62] [epic:#63] [epic:#115]

**Done when:** `@cleaner` is in `registry.json` and runs last in
`/tick-all`; `read-intent-file.sh` exists and `@po-manager` reads
`ROADMAP.md` for stale threshold and milestone scope;
`bootstrap-plan.sh` proposes clustered epics instead of placeholders
when no milestones exist.

---

### E5 — learn-skill-dedup
> The `/learn` skill should not regenerate identical proposals when run
> repeatedly on an unchanged session.

When `/loop 5m /learn all and create tickets` fires, successive
iterations re-analyze unchanged state and produce 80 %+ overlapping
proposals. A pre-flight overlap check lets the skill short-circuit with
a one-line skip receipt instead.

**Binds:** [epic:#104]

**Done when:** a third consecutive `/learn` run on an unchanged session
emits a one-line skip receipt citing the prior ticket(s).

---

## Non-goals (scope-creep detection has teeth here)

- **CI automation for agent sweeps.** Tick runs are human-initiated
  only; no GitHub Actions cron, no Renovate scheduler, no
  `repo_dispatch` triggers.
- **Cross-repo portfolio view.** `bsg-stack` is a catalog repo; it does
  not aggregate data from tracked repos. Each tracked repo runs its own
  agents.
- **Billing or quota enforcement infrastructure.** Token budgets (#97)
  are documented policy and dispatcher-level gates, not a metering
  service.
- **Agent UI / dashboard.** No web frontend, Slack app, or external
  notification layer unless a separate proposal is approved.
- **Changes to tracked repos' source code.** This repo ships skills; it
  does not implement features in the repos that consume them.

---

## Cadence and review rhythm

| Rhythm | What happens |
|---|---|
| Each `/tick-all` sweep | PO manager runs adherence check; silence-breakers fire if any issue is unbound or any epic is stale |
| Weekly (Monday) | Quick milestone scan; confirm E1–E3 progress; triage any new issues into an epic or into non-goals |
| On new issue | PO binds it to an epic within 1 business day or adds it to the non-goals list with a comment explaining why |
| On epic completion | Epic is marked `status: done` in this file; issues are closed; next candidate epic is proposed |

---

## Decision log

- 2026-04-23: Plan bootstrapped from `@po-manager propose plan` session
  output after 4 consecutive `/tick-all` ticks reported all 8 open
  issues as unbound scope creep. Scripted `bootstrap-plan.sh` output
  was a skeleton (no open milestones) — ticket #115 tracks making it
  produce issue-clustered epics in future repos. `[tag:decision]`

---

## Tracked risks

- `/tick-all` at a 5-minute `/loop` cadence currently burns ~45 M
  tokens/day on unchanged state. If E1 is not closed within two weeks,
  the default recommended cadence in `claude-skills/commands/tick-all.md`
  should be raised to `30m`. `[tag:risk]`
