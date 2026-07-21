<a href="../../README.md"><img src="../../assets/logo-bsg-holding.png" alt="Beyond Scale Group" height="40"></a>

**[Beyond Scale Group](../../README.md)** · [BSG Stack](../../README.md) · [Claude Skills](../README.md)

---

# `commands/` — slash commands

Single-file prompt commands invoked as `/<name>` in any Claude Code session.
Each is a Markdown file with frontmatter (`description`, optional
`argument-hint`, `allowed-tools`) plus the prompt body.

## The catalog

| Command | What it does |
|---|---|
| `/ship` | Run preflight checks, commit, push, and open a PR. Derives title + summary from the diff. |
| `/ship_and_merge` | `/ship`, then wait for CI green and merge — the full ship-to-main flow. |
| `/merge` | Signal a PR is ready for peer review: preflight, take out of draft, request a reviewer. Auto-runs `/ship` first if no PR exists. |
| `/babysit <cmd>` | Babysit a process: monitor failures, diagnose root causes, fix, and retry. |
| `/sync-worktree` | Synchronize git worktrees with their PRs and prune obsolete ones. |
| `/ocr <file>` | Extract text from an image or PDF without uploading it into Claude's context. |
| `/tick-all` | Run a full `tick` sweep across every registered BSG agent (each in its own worktree). |
| `/tick-one <agent>` | Fire a single agent's `tick` in an isolated worktree — the loopable unit for `/loop 15m /tick-one tech-lead`. |
| `/po-daily` | Run a full autonomous PO tick: triage tickets, organize milestones, audit the plan, report. |

## How to run one

Type the slash command in an interactive session, or headless:

```bash
claude -p "/tick-all"
```

Some commands take an argument (`/babysit bun run build`, `/tick-one qa`) —
see each file's `argument-hint` frontmatter.

For the difference between a **command** (single-file prompt) and a **skill**
(`SKILL.md` + scripts) or **agent** (role-scoped subagent), see
[`../README.md`](../README.md).

---

<sub>Source of truth — edit here and PR back, never edit the cached copies in
`~/.claude/commands/`. See [`../INSTALL.md`](../INSTALL.md).</sub>
