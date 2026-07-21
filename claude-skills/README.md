<a href="../README.md"><img src="../assets/logo-bsg-holding.png" alt="Beyond Scale Group" height="40"></a>

**[Beyond Scale Group](../README.md)** · BSG Stack

---

# Claude Code Skills

Shared [Claude Code](https://claude.com/claude-code) slash commands,
skills, and subagents for the BSG portfolio. Every developer in the
group gets the same baseline Claude capabilities with one install
command and auto-updates on every new session.

## What's in here

| Directory | Purpose |
|-----------|---------|
| [`commands/`](commands/README.md) | Slash commands (`/ship`, `/tick-all`, …) — single-file prompts invoked as `/name` |
| `skills/` | Full skills (`po`, …) — `SKILL.md` + optional `scripts/` and `references/` |
| [`agents/`](agents/README.md) | Subagents (`po-manager`, …) — role-scoped agents with their own tool budget |
| [`scripts/`](scripts/README.md) | The installer (`update-bsg-skills.py`) and helper scripts/functions |
| [`templates/`](templates/README.md) | Per-agent intent-file starters (`ROADMAP.md`, `SECURITY.md`, …) |
| [`tests/`](tests/README.md) | Smoke & unit tests for the installer, scripts, and skill metadata |
| [`prds/`](prds/README.md) | Product requirement docs the agents & skills were built from |

Each subfolder now carries its own `README.md` listing every file it holds —
a new developer can open any directory and see what's available at a glance.
For the full catalog of installed commands, skills, and agents, see the
tables in [`INSTALL.md`](INSTALL.md).

## How to install

Ask your Claude Code agent:

> Install the BSG Claude skills by following
> https://raw.githubusercontent.com/beyond-scale-group/bsg-stack/main/claude-skills/INSTALL.md

Claude fetches that file, drops `update-bsg-skills.py` into
`~/.claude/scripts/`, runs it once, and registers a `SessionStart`
hook so every future Claude Code session pulls the latest from `main`
automatically.

Full installer behaviour (manifest, skip-if-not-owned, log rotation,
network-error handling) is documented in [`INSTALL.md`](INSTALL.md).

## How to contribute

To add a new command, skill, or agent to the shared catalog, follow the
"Adding a new command, skill, or agent to the catalog" section of
[`INSTALL.md`](INSTALL.md#adding-a-new-command-skill-or-agent-to-the-catalog).
In short:

1. Drop the file in the right subdirectory (`commands/`, `skills/`, or
   `agents/`).
2. Add the standard "How to improve this skill" footer so remote edits
   flow back here instead of diverging locally.
3. Add a row to the catalog table in `INSTALL.md`.
4. Open a PR.

## Source of truth

This directory is the single source of truth. Files in
`~/.claude/commands/`, `~/.claude/skills/`, and `~/.claude/agents/` on
any developer machine are cached copies — they get overwritten on every
install or SessionStart run. Always PR back here instead of editing the
local copies.
