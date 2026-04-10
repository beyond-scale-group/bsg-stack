# BSG Claude Skills — Install Guide

This file is the entry point for installing the **BSG shared Claude Code
skills** (slash commands + full skills) into a developer's local
`~/.claude/` directory.

It is written to be read **by [Claude Code](https://claude.com/claude-code)
itself**: a developer points their Claude session at this file, Claude
follows the instructions below, fetches each skill from this repo, and
writes it into the developer's home. A human can read it too — it doubles
as the catalog of what's available.

## How a developer installs (or updates)

In any Claude Code session, ask:

> Install the BSG Claude skills by following
> https://raw.githubusercontent.com/beyond-scale-group/bsg-workflows/main/claude-skills/INSTALL.md

Claude will fetch this file, discover the commands and skills listed
below, and install them under `~/.claude/`. **To pick up updates later,
just ask the same thing again** — Claude will overwrite the local copies
with the latest version from `main`.

No git clone, no script to run, no cron to set up.

## Available commands

| Name | Description |
|------|-------------|
| `/babysit` | Monitor a long-running or flaky process (shell command or CI run), diagnose failures, fix root causes, retry until green. Includes PR mergeability rules. |

## Available skills

_None yet._

## Adding a new command or skill to the catalog

1. Drop the file in the right place inside this repo:
   - Slash command → `claude-skills/commands/<name>.md`
   - Full skill → `claude-skills/skills/<name>/SKILL.md` (plus any extra
     resources in the same directory)
2. Add a row to the relevant table above.
3. Open a PR.

Once merged on `main`, every developer who re-runs the install command
gets the new skill.

---

## Instructions for the Claude Code agent

**You — the Claude Code agent reading this file — are installing the BSG
shared Claude Code commands and skills into the current user's local
`~/.claude/` directory. Follow these steps exactly. Use your `WebFetch`,
`Write`, and `Bash` tools.**

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

### 4. Report to the user

Print a short summary listing every command and skill that was installed
or updated, with the count, and remind the user that they can re-run the
same install flow any time to pull updates.

### Constraints

- Do **not** clone the repo. Use HTTPS fetches only.
- Do **not** touch any file outside `~/.claude/commands/` and
  `~/.claude/skills/`.
- Do **not** ask the user to confirm before overwriting — files installed
  by this flow are cached copies of the remote source of truth. If a
  developer wants a customized variant of a command, they should fork it
  under a different name (e.g. `babysit-custom.md`) so this install flow
  leaves it alone.
- If the GitHub API returns a rate-limit error (HTTP 403 with
  `X-RateLimit-Remaining: 0`), report it to the user and stop — do not
  retry in a loop.
