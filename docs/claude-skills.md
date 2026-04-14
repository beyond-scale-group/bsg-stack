# Claude Code Skills

Shared Claude Code slash commands, skills, and subagents for the BSG
portfolio.

- **Component README:** [`claude-skills/README.md`](../claude-skills/README.md) —
  directory layout and contribution flow.
- **Full install guide + catalog:** [`claude-skills/INSTALL.md`](../claude-skills/INSTALL.md) —
  the Claude-driven installer and the current catalog of commands,
  skills, and agents.
- **Install snippet:** [`INSTALL.md` §3](../INSTALL.md#3-claude-code-skills) —
  the one-line ask for Claude Code.

## Quick reference

Ask your Claude Code agent:

> Install the BSG Claude skills by following
> https://raw.githubusercontent.com/beyond-scale-group/bsg-stack/main/claude-skills/INSTALL.md

Claude drops `update-bsg-skills.py` into `~/.claude/scripts/`, runs it
once, and registers a `SessionStart` hook so every future session
pulls the latest from `main`. Re-ask any time to force-refresh.
