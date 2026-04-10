# BSG Claude Skills — Install Guide

This file is the entry point for installing the **BSG shared Claude Code
skills** (slash commands, full skills, and subagents) into a developer's
local `~/.claude/` directory.

It is written to be read **by [Claude Code](https://claude.com/claude-code)
itself**: a developer points their Claude session at this file, Claude
follows the instructions below, fetches each skill from this repo, and
writes it into the developer's home. A human can read it too — it doubles
as the catalog of what's available.

## How a developer installs (or updates)

In any Claude Code session, ask:

> Install the BSG Claude skills by following
> https://raw.githubusercontent.com/beyond-scale-group/bsg-workflows/main/claude-skills/INSTALL.md

Claude will fetch this file, discover the commands, skills, and agents
listed below, and install them under `~/.claude/`. **To pick up updates
later, just ask the same thing again** — Claude will overwrite the local
copies with the latest version from `main`.

No git clone, no script to run, no cron to set up.

## Available commands

| Name | Description |
|------|-------------|
| `/babysit` | Monitor a long-running or flaky process (shell command or CI run), diagnose failures, fix root causes, retry until green. Includes PR mergeability rules. |

## Available skills

| Name | Description |
|------|-------------|
| `po-report` | Product owner reporting for the current GitHub repo. Aggregates issues, milestones, stale tickets, PRs into a dated markdown report under `.claude/reports/`. Heavy lifting in bash scripts (zero LLM cost), narration in the skill. |

## Available agents

| Name | Description |
|------|-------------|
| `po-manager` | Product owner / project manager orchestrator subagent. Delegated to for status reports, milestone progress, sprint health, stale ticket detection, standup summaries. Uses the `po-report` skill for reporting and `daily-standup` for meeting parsing. Reporting only — does not implement features. |

## Adding a new command, skill, or agent to the catalog

1. Drop the file in the right place inside this repo:
   - Slash command → `claude-skills/commands/<name>.md`
   - Full skill → `claude-skills/skills/<name>/SKILL.md` (plus any extra
     resources in the same directory)
   - Subagent → `claude-skills/agents/<name>.md`
2. **Add the standard "How to improve this skill" footer** (see below) so
   that anyone using the cached copy in `~/.claude/` knows to PR back
   here instead of editing locally.
3. Add a row to the relevant table above.
4. Open a PR.

Once merged on `main`, every developer who re-runs the install command
gets the new skill.

### Required footer for every shared skill

Append this block (verbatim, with `<name>` replaced) at the very bottom of
each new command or skill file. The leading `---` separates it from the
skill's behavioral content so the agent treats it as out-of-band metadata
rather than part of its role:

````markdown
---

## How to improve this skill

This file is a cached copy of `claude-skills/commands/<name>.md` in
[beyond-scale-group/bsg-workflows](https://github.com/beyond-scale-group/bsg-workflows).
That repo is the single source of truth — `~/.claude/commands/<name>.md` is
overwritten every time the BSG install flow runs.

If the user asks you to improve, fix, or extend this skill, do **not** edit
the local file. Instead:

1. `gh repo clone beyond-scale-group/bsg-workflows` (or work in an existing clone)
2. Edit `claude-skills/commands/<name>.md` on a feature branch
3. Open a pull request against `main`

Bug reports and ideas without a fix → open an issue on the same repo.
````

For files under `claude-skills/skills/<name>/SKILL.md`, replace
`commands/<name>.md` with `skills/<name>/SKILL.md` everywhere in the
footer. **Only `SKILL.md` needs the footer** — supporting files like
`references/*.md` and `scripts/*.sh` inside a skill directory do not.

For files under `claude-skills/agents/<name>.md`, replace
`commands/<name>.md` with `agents/<name>.md` everywhere in the footer,
and replace `~/.claude/commands/<name>.md` with `~/.claude/agents/<name>.md`.

---

## Instructions for the Claude Code agent

**You — the Claude Code agent reading this file — are installing the BSG
shared Claude Code commands, skills, and subagents into the current
user's local `~/.claude/` directory. Follow these steps exactly. Use
your `WebFetch`, `Write`, and `Bash` tools.**

### 1. Discover available commands

Fetch this GitHub API endpoint:

```
https://api.github.com/repos/beyond-scale-group/bsg-workflows/contents/claude-skills/commands?ref=main
```

It returns a JSON array. For each entry where `"type": "file"` and `name`
ends with `.md`, note the `name` and the `download_url`.

### 2. Install each command

For each command discovered in step 1:

1. Fetch its raw content from the `download_url`.
2. Write it to `~/.claude/commands/<name>` (resolve `~` to the actual
   home directory). Create `~/.claude/commands/` first if it does not
   exist.
3. **Always overwrite** any existing file at that path — the remote is
   the source of truth, and the local file is a cached copy.

### 3. Discover and install skills

Fetch:

```
https://api.github.com/repos/beyond-scale-group/bsg-workflows/contents/claude-skills/skills?ref=main
```

If the response is `404`, there are no skills yet — skip to step 4.

Otherwise, for each entry with `"type": "dir"`:

1. Fetch that entry's `url` (also a GitHub API URL) to list the files
   inside the skill directory.
2. For each file, fetch its `download_url` and write it to
   `~/.claude/skills/<skill-name>/<file-name>`. Create directories as
   needed. Recurse into subdirectories the same way.
3. After writing, `chmod +x` any file under `scripts/` so the skill can
   execute its own helpers without the user fixing permissions.

### 4. Discover and install subagents

Fetch:

```
https://api.github.com/repos/beyond-scale-group/bsg-workflows/contents/claude-skills/agents?ref=main
```

If the response is `404`, there are no agents yet — skip to step 5.

Otherwise, for each entry where `"type": "file"` and `name` ends with
`.md`:

1. Fetch its raw content from the `download_url`.
2. Write it to `~/.claude/agents/<name>` (resolve `~` to the actual home
   directory). Create `~/.claude/agents/` first if it does not exist.
3. **Always overwrite** any existing file at that path — same rule as
   commands.

Subagents installed this way are user-scope and become available across
all the developer's projects. They are loaded at session start, so the
developer must restart Claude Code to pick up newly-installed agents.

### 5. Report to the user

Print a short summary listing every command, skill, and subagent that
was installed or updated, with the count, and remind the user that they
can re-run the same install flow any time to pull updates. If any
subagents were installed or changed, also remind the user to restart
Claude Code so the new definitions are loaded.

### Constraints

- Do **not** clone the repo. Use HTTPS fetches only.
- Do **not** touch any file outside `~/.claude/commands/`,
  `~/.claude/skills/`, and `~/.claude/agents/`.
- Do **not** ask the user to confirm before overwriting — files installed
  by this flow are cached copies of the remote source of truth. If a
  developer wants a customized variant of a command, they should fork it
  under a different name (e.g. `babysit-custom.md`) so this install flow
  leaves it alone.
- If the GitHub API returns a rate-limit error (HTTP 403 with
  `X-RateLimit-Remaining: 0`), report it to the user and stop — do not
  retry in a loop.
