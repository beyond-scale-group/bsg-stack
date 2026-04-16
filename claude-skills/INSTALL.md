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
> https://raw.githubusercontent.com/beyond-scale-group/bsg-stack/main/claude-skills/INSTALL.md

Claude will fetch this file, discover the commands, skills, and agents
listed below, and install them under `~/.claude/`. **To pick up updates
later, just ask the same thing again** — Claude will overwrite the local
copies with the latest version from `main`.

No git clone, no script to run, no cron to set up.

## Available commands

| Name | Description |
|------|-------------|
| `/babysit` | Monitor a long-running or flaky process (shell command or CI run), diagnose failures, fix root causes, retry until green. Includes PR mergeability rules. |
| `/ocr` | Extract text from images and PDFs without uploading them into Claude's multimodal context. Cascades through Apple Vision (macOS) → Tesseract/OCRmyPDF → Mistral OCR API, writing `<source>.ocr.md` next to the source. Designed to save Anthropic tokens on document-heavy workflows. |

## Available skills

| Name | Description |
|------|-------------|
| `ocr` | OCR toolkit that cascades local engines (Apple Vision, Tesseract) before reaching for the Mistral OCR API. Exposes `ocr.sh` as the orchestrator plus per-engine scripts. Any agent about to read an image or scanned PDF should call this skill first and read the resulting `.ocr.md` instead of sending the raw file to Claude. |
| `po-report` | Product owner reporting for the current GitHub repo. One paginated GraphQL snapshot feeds every report (status, milestone progress with risk flags, stale issues, PR flow) written under `po/reports/` with the raw snapshot committed to `po/history/<date>.json`. Heavy lifting in bash + jq (zero LLM cost), narration in the skill. |

## Available agents

| Name | Description |
|------|-------------|
| `po-manager` | Product owner / project manager orchestrator subagent. Delegated to for status reports, milestone progress, sprint health, stale ticket detection, standup summaries. Uses the `po-report` skill for reporting and `daily-standup` for meeting parsing. Reporting only — does not implement features. |

## Settings merged into `~/.claude/settings.json`

`claude-skills/settings.json` is the BSG-managed settings template. The
BSG updater **merges specific keys** from it into the user's
`~/.claude/settings.json` on every run, alongside the existing
SessionStart hook it registers. Other keys in `~/.claude/settings.json`
are left untouched.

Currently-managed keys:

| Key | Effect |
|---|---|
| `autoMemoryEnabled` | Set to `false` — disables the Claude Code auto-memory system globally so durable context lives in project `CLAUDE.md` files and committed agent outputs (`po/`, reports, etc.) instead of per-project memory stores. |
| `mcpServers.context7` | Pre-registers the [Context7](https://context7.com) MCP server so documentation lookups (React, Next.js, library APIs, …) are available in every session with no per-session setup. Honors `CONTEXT7_API_KEY` if set; works on the public-rate tier otherwise. |

The merge is **idempotent** and **narrow**:

- Only the keys listed in `BSG_MANAGED_SETTINGS_KEYS` and
  `BSG_MANAGED_MCP_SERVERS` inside `update-bsg-skills.py` are touched.
- Other top-level keys (including other `mcpServers.*` entries you've
  configured) are preserved exactly as they are.
- If `~/.claude/settings.json` is not valid JSON, the updater logs a
  warning and refuses to modify the file.

To add or remove a managed key, edit `claude-skills/settings.json` **and**
update the `BSG_MANAGED_*` lists in the installer in the same PR.

## How it works under the hood

The whole install flow boils down to: **drop one Python script in
`~/.claude/scripts/` and run it once.**

That script — `update-bsg-skills.py` — does everything else:

- Discovers and installs every command, skill, and subagent from this
  repo into `~/.claude/commands/`, `~/.claude/skills/`, and
  `~/.claude/agents/`.
- Self-registers a `SessionStart` hook in `~/.claude/settings.json` so
  every new Claude Code session re-runs it in the background. After the
  first install, you never have to think about updates again.
- Maintains a manifest at
  `~/.claude/scripts/.bsg-skills-manifest.json` listing every file it
  owns. **It will never overwrite a file it does not own**, so if you
  already have your own `~/.claude/commands/babysit.md` (or another
  shared-skills system writes there), the BSG updater leaves it alone
  and logs a SKIP. To adopt a BSG version of a file you already have,
  delete your local copy and re-run.
- Removes files locally when they are removed upstream — but only files
  in the manifest, so unrelated files in the same directories are
  never touched.
- Logs to `~/.claude/logs/update-bsg-skills.log` (rotated at 256 KiB).
- Swallows network errors (exits 0) so a flaky connection never blocks
  a Claude Code session from starting.

Re-running the install flow is just a way to reset to a known-good
script if the local copy got corrupted or deleted.

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
[beyond-scale-group/bsg-stack](https://github.com/beyond-scale-group/bsg-stack).
That repo is the single source of truth — `~/.claude/commands/<name>.md` is
overwritten every time the BSG install flow runs.

If the user asks you to improve, fix, or extend this skill, do **not** edit
the local file. Instead:

1. `gh repo clone beyond-scale-group/bsg-stack` (or work in an existing clone)
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
shared Claude Code skills system for the current user. Your job is
deliberately tiny: drop one script on disk and run it. The script does
everything else (discovers commands, skills, and subagents, installs
them, registers a self-updating hook, manages a manifest to avoid
clobbering files it does not own).**

### 1. Fetch the updater script

Fetch the raw content from:

```
https://raw.githubusercontent.com/beyond-scale-group/bsg-stack/main/claude-skills/scripts/update-bsg-skills.py
```

### 2. Install it

1. Create `~/.claude/scripts/` if it does not exist (resolve `~` to the
   actual home directory).
2. Write the fetched content to
   `~/.claude/scripts/update-bsg-skills.py`. Always overwrite — the
   remote is the source of truth.
3. `chmod +x` the file.

### 3. Run it once

Run the script in the foreground so you can capture and show its output
to the user:

```
python3 ~/.claude/scripts/update-bsg-skills.py
```

On its first run, the script will:

- Self-register a `SessionStart` hook in `~/.claude/settings.json`
  (idempotent — safe to re-run).
- Discover and install every command, skill, and subagent from this
  repo into `~/.claude/commands/`, `~/.claude/skills/`, and
  `~/.claude/agents/`, writing a manifest at
  `~/.claude/scripts/.bsg-skills-manifest.json` so it can avoid
  clobbering files it does not own on later runs.
- Log everything to `~/.claude/logs/update-bsg-skills.log`.

The script always exits 0, even on network failure, so do not treat a
zero exit as success on its own — read the log instead.

### 4. Report to the user

Show a short summary based on the script's output: how many commands,
skills, and subagents were installed or updated, any files that were
SKIPPED because they already existed and were not in the BSG manifest,
and a reminder that future Claude Code sessions will auto-update via
the SessionStart hook. If any subagents were installed or changed, also
remind the user to restart Claude Code so the new definitions are
loaded.

### Constraints

- Do **not** clone the repo. Use HTTPS fetches only.
- Do **not** touch any file outside
  `~/.claude/scripts/update-bsg-skills.py`. Everything else (commands,
  skills, agents, manifest, settings.json hook) is the script's
  responsibility.
- Do **not** edit `~/.claude/settings.json` yourself — the script
  handles it idempotently.
- Do **not** ask the user to confirm before overwriting the script — it
  is a cached copy of the remote source of truth.
- If the GitHub raw URL returns an HTTP error, report it to the user
  and stop — do not retry in a loop.
