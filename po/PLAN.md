# Big plan — beyond-scale-group/bsg-stack

## Mission

`bsg-stack` is the single source of truth for Claude Code commands, skills,
and subagents shared across the BSG org. Its job: keep the catalog healthy,
install reliably on every developer machine, and run agent sweeps that are
cheap, idempotent, and trustworthy.

## Objectives

- Drive a no-change `/tick-all` sweep below 10 k tokens and enforce one-line receipts  [epic:#90] [epic:#91] [epic:#97]
- Keep `update-bsg-skills.py` resilient so every agent lands on every developer machine  [epic:#67]
- Make every reporting agent's tick receipt a GitHub PR URL, never a local worktree path  [epic:#84]
- Grow the catalog with backlog-hygiene, intent-file, and smarter-bootstrap capabilities  [epic:#62] [epic:#63] [epic:#115]
- Stop `/learn` from regenerating identical proposals on unchanged sessions  [epic:#104]
- Fix the silent parse-plan.sh failure and ship a plan validator  [epic:#128]
- Activate the GitHub coordination bus so agents actually claim, lock, and hand off issues  [epic:#199]
- Make repo bootstrap a one-command experience via `--init` enforcement and a `/doctor` skill  [epic:#237] [epic:#241]
- Extend md-to-office with PPTX support and a tool-agnostic format frontmatter  [epic:#250]

## Epics

- **E1 tick-hygiene** — make every agent tick cheap, one-line, and idempotent  [epic:#90] [epic:#91] [epic:#97] [label:enhancement]
- **E2 install-reliability** — the updater must never abort mid-sync; every agent must land on every developer machine  [epic:#67] [label:bug] [status:in-review (PR #249)]
- **E3 agent-pr-contract** — every reporting agent opens a PR via `open-report-pr.sh`; tick receipts contain a GitHub URL, never a local path  [epic:#84] [label:bug]
- **E4 catalog-growth** — grow the catalog with `@cleaner`, per-domain intent files, and a smarter `bootstrap-plan.sh`  [epic:#62] [epic:#63] [epic:#115] [label:enhancement]
- **E5 learn-skill-dedup** — the `/learn` skill should short-circuit when no new signal since the prior iteration  [epic:#104] [label:enhancement]
- **E6 plan-schema-hygiene** — surface format-mismatch errors from `parse-plan.sh` instead of silently emitting `[]`, and add a plan validator  [epic:#128] [label:bug]
- **E7 bus-activation** — wire `bus_claim` / `bus_lock` / `bus_handoff` into every agent's tick so the GitHub coordination bus stops being decorative  [epic:#199] [label:bug]
- **E8 bootstrap-ergonomics** — a fresh repo gets BSG conventions with one command: `--init` mandatory on every agent/skill, plus a `/doctor` skill that audits compliance and patches gaps  [epic:#237] [epic:#241] [label:enhancement]
- **E9 office-formats** — md-to-office grows beyond DOCX: PPTX target, format frontmatter that's tool-agnostic, and brand-token init that respects manual edits and Tailwind v4 `@theme` tokens  [epic:#250] [label:enhancement]

## Non-goals (scope-creep detection has teeth here)

Items below are deliberately out of scope. New issues matching these patterns
should be closed with a link to this section.

- CI automation for agent sweeps — tick runs are human-initiated only; no GitHub Actions cron, no Renovate scheduler, no `repo_dispatch` triggers
- Cross-repo portfolio view — `bsg-stack` is a catalog repo; it does not aggregate data from tracked repos
- Billing or quota enforcement infrastructure — token budgets are documented policy and dispatcher-level gates, not a metering service
- Agent UI / dashboard — no web frontend, Slack app, or external notification layer
- Changes to tracked repos' source code — this repo ships skills; it does not implement features in the repos that consume them

## Cadence and review rhythm

| Rhythm | What happens |
|---|---|
| Each `/tick-all` sweep | PO manager runs adherence check; silence-breakers fire if any issue is unbound or any epic is stale |
| Weekly (Monday) | Quick milestone scan; confirm E1–E9 progress; triage any new issues into an epic or into non-goals |
| On new issue | PO binds it to an epic within 1 business day or adds it to the non-goals list with a comment explaining why |
| On epic completion | Epic is marked `status: done` in this file; issues are closed; next candidate epic is proposed |

## Decision log

- 2026-04-23: Plan bootstrapped from `@po-manager propose plan` session output; first version used `###` headers + narrative paragraphs which `parse-plan.sh` couldn't parse. Rewrote to the bullet-with-inline-tags schema defined in `references/plan-schema.md`.  [tag:decision]
- 2026-04-23: Established the two-layer worktree cleanup (per-agent unlock in `open-report-pr.sh` + dispatcher-level prune in `/tick-all`) via PR #120 after observing 30+ stale worktrees accumulated across one `/loop 5m /tick-all` session.  [tag:decision]
- 2026-04-30: Plan amended to add **E7-bus-activation** (#199), **E8-bootstrap-ergonomics** (#237 + #241), and **E9-office-formats** (#250). #199, #237, #241, #250 were previously labeled `scope-creep` because no epic existed yet — they describe intentional next-wave work, not non-goal violations. #200 and #222 should close as already-shipped; their substance landed under the autopilot mode and per-agent scope contract conventions documented in CLAUDE.md.  [tag:decision]
- 2026-04-30: Tech-lead pilot tick auto-implemented #67 (PR #249), the first end-to-end run of the autopilot pipeline after the `human-reviewed` label-logic fix in PR #234. E2-install-reliability moves to `in-review`; will close when #249 merges.  [tag:decision]

## Tracked risks

- `/tick-all` at a 5-minute `/loop` cadence currently burns ~45 M tokens/day on unchanged state. If E1 is not closed within two weeks, the default recommended cadence in `claude-skills/commands/tick-all.md` should be raised to `30m`.  [tag:risk]
- `qa` subagent tokens have trended 18 k → 37 k per tick over one session on identical findings; root cause (likely growing report-archive scan) is embedded in E1 but should not be missed.  [tag:risk]
