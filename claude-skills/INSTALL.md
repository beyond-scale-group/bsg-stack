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
| `/tick-all` | Fire every registered BSG agent's `tick` in parallel and print a one-line sweep summary per agent. Uses `claude-skills/agents/registry.json` as the agent roster. Each agent handles its own GitHub-bus inbox (claim → work → handoff) via `claude-skills/scripts/github-bus.sh`. Run with `/loop 30m /tick-all` for a recurring sweep — no CI cron required. |

## Available skills

| Name | Description |
|------|-------------|
| `google-workspace` | Google Workspace CLI skill wrapping the official `gws` tool (github.com/googleworkspace/cli) across Gmail, Calendar, Drive, Sheets, Slides, Docs, Tasks, People, Chat, Meet, Forms, Keep, and the built-in `+workflow` helpers. Ships a preflight (binary/version/auth), an auto-Chrome OAuth helper (`scripts/auth-login.sh`), and an IAM-elevation helper (`scripts/fix-iam-403.sh`) that grants `serviceusage.serviceUsageConsumer` so Drive/Tasks/Chat/People stop 403'ing. Documents the GCP-project gotchas (consent-screen scope registration, Chat app registration) that `--full` alone can't solve. |
| `ocr` | OCR toolkit that cascades local engines (Apple Vision, Tesseract) before reaching for the Mistral OCR API. Exposes `ocr.sh` as the orchestrator plus per-engine scripts. Any agent about to read an image or scanned PDF should call this skill first and read the resulting `.ocr.md` instead of sending the raw file to Claude. |
| `browser` | Browser automation wrapping [`agent-browser`](https://www.npmjs.com/package/agent-browser) with persistent profile management, a Google login helper (`scripts/login-google.sh`), and a generic profile wrapper (`scripts/with-profile.sh`). Headed mode for first-time logins, headless for replay. Core verbs: open, click, fill, type, screenshot, snapshot (accessibility tree). |
| `github-compliance` | GitHub organization compliance checker for `beyond-scale-group`. Audits that every non-archived private repo has the `board` team assigned with `admin` permission, and (with `--fix`) assigns missing teams. Exposes a `tick` action that lands the audit under `compliance/reports/YYYY-MM-DD-compliance.md` via `open-report-pr.sh` and stays silent unless a non-compliant repo is found. |
| `po` | Product owner skill for the current GitHub repo. Covers plan adherence, backlog triage, milestone tracking, sprint planning, scope-creep detection, PR flow health, and stakeholder reporting. One paginated GraphQL snapshot feeds every capability; reports land under `po/reports/` with the raw snapshot in `po/history/<date>.json`. Heavy lifting in bash + jq (zero LLM cost), narration in the skill. |
| `security-report` | Security audit toolkit for the current repo. Auto-detects the package ecosystem (npm/pip/go/cargo), runs vulnerability scanners, cross-checks with Dependabot alerts, scans tracked files for secret patterns (AWS keys, GitHub tokens, private keys), and audits HTTP security headers on web-serving repos. Exposes a `tick` action that lands the audit under `security/reports/YYYY-MM-DD-audit.md` via `open-report-pr.sh` and stays silent unless a critical/high CVE, secret finding, missing critical header, or tracked `.env` is detected. |
| `qa-report` | Quality-assurance audit toolkit for the current repo. Parses coverage reports in any of lcov / Istanbul JSON / Cobertura / scoverage / Python / Go formats, computes regression risk from churn × coverage, detects flaky tests from recent CI runs, and emits a dated audit. Exposes a `tick` action that lands the audit under `qa/reports/YYYY-MM-DD-audit.md` and archives the raw snapshot in `qa/history/` for trend analysis. |
| `tech-report` | Tech-health audit toolkit for the current repo. Tracks dependency upgrade gaps (`npm outdated` / `pip list --outdated` + Dependabot alerts), flags oversized files (> 500 LOC) and circular imports, inventories TODO/FIXME/HACK with age via `git blame`, and detects new top-level dependencies added without a matching ADR. Lands reports under `tech/reports/YYYY-MM-DD-health.md` and commits them locally. |
| `seo-report` | Technical-SEO audit toolkit for the current repo. Parses HTML / JSX / Vue / Svelte / Astro templates for title, meta description, canonical, Open Graph, and JSON-LD blocks; builds an internal link graph to find orphan pages and broken links; checks sitemap.xml / robots.txt and target-keyword coverage against `seo/KEYWORDS.md`. Lands audits under `seo/reports/YYYY-MM-DD-audit.md` via `open-report-pr.sh`. No external API calls — everything is source-at-rest. |
| `marketing-report` | Marketing audit toolkit for the current repo. Parses `marketing/CALENDAR.md` for overdue content items, enumerates recent releases and milestones via `gh`, scans `marketing/`, README, and landing-oriented `docs/` files for feature claims, then diffs shipped vs marketed to surface unmarketed releases and premature claims. Auto-generates campaign-brief stubs under `marketing/briefs/`. Lands audits under `marketing/reports/YYYY-MM-DD-audit.md` via `open-report-pr.sh`. |
| `storytelling-report` | Brand narrative + voice audit toolkit for the current repo. Parses `brand/NARRATIVE.md` for voice guidelines, key messages, and positioning; scores each public-facing asset (README, docs/, landing, CHANGELOG, blog) on a 0–10 tone scale derived from Flesch reading ease minus passive-voice and jargon penalties; flags drift > 2σ from the bible target. Checks key-message coverage and positioning staleness, and drafts talking-point stubs for releases that do not yet have one under `brand/talking-points/`. Lands audits under `brand/reports/YYYY-MM-DD-audit.md` via `open-report-pr.sh`. No external NLP APIs. |
| `pr-comms-report` | PR / communications toolkit for the current repo. Classifies releases (major / minor / patch / skip), closed milestones, security advisories, and contributor / PR-merged milestones by newsworthiness; detects which events are unannounced via `comms/ANNOUNCED.md` and existing drafts under `comms/press-releases/`; audits `comms/press-kit/` freshness with a 90-day staleness rule; drafts press-release stubs (plan mode by default, materialized with `--write`) that inline boilerplate + contact when present and carry a CONFIDENTIAL header in private repos. Lands audits under `comms/reports/YYYY-MM-DD-events.md` via `open-report-pr.sh`. Never drafts security-incident responses. |

## Available agents

| Name | Description |
|------|-------------|
| `po-manager` | Product owner / project manager orchestrator subagent. Delegated to for plan adherence, backlog triage, milestone progress, sprint health, stale ticket detection, standup summaries. Uses the `po` skill and `daily-standup` for meeting parsing. Does not implement features. |
| `security` | Security posture auditor subagent. Delegated to for "security audit", "vulnerability scan", "secret scan", "OWASP check", "are we secure". Uses the `security-report` skill for deps / secrets / headers / OWASP heuristics. Reports only — does not remediate, upgrade packages, or edit source. |
| `qa` | Quality-assurance auditor subagent. Delegated to for "test coverage", "regression risk", "flaky tests", "QA audit", "quality report". Uses the `qa-report` skill for coverage / risk / flake analysis. Reports only — does not write tests or execute the test suite. |
| `tech-lead` | Virtual senior developer / CTO subagent. Delegated to for "architecture review", "dependency health", "tech debt", "code quality", "ADR", "complexity". Uses the `tech-report` skill for deps / quality / debt / ADR gap detection. Reports only — does not refactor or choose frameworks. |
| `seo` | SEO auditor subagent. Delegated to for "SEO audit", "meta tags", "sitemap", "internal links", "content gaps", "structured data". Uses the `seo-report` skill for meta / links / content / technical / structured-data analysis. Reports only — does not write meta tags or author content. |
| `marketing` | Marketing auditor subagent. Delegated to for "marketing audit", "content calendar", "campaign brief", "feature alignment", "landing page check". Uses the `marketing-report` skill to detect overdue content, unmarketed releases, premature claims, and stale campaign briefs. Reports and drafts brief stubs only — does not write copy or launch campaigns. |
| `storytelling` | Brand narrative auditor subagent. Delegated to for "brand audit", "narrative check", "voice consistency", "talking points", "positioning", "tone of voice". Uses the `storytelling-report` skill for voice scoring, key-message alignment, positioning staleness, and talking-point drafting. Reports only — never edits the narrative bible or final copy. |
| `pr-comms` | PR / communications subagent. Delegated to for "press release", "announcement draft", "PR events", "press kit", "communication plan", "newsworthy". Uses the `pr-comms-report` skill for event classification, press-kit freshness, and draft-stub generation. Drafts only — never publishes, contacts journalists, or responds to security incidents. |

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

## GitHub labels used by BSG agents

BSG agents expect the following labels to exist on any repo where they file
issues or open PRs. `claude-skills/scripts/file-issue.sh` auto-creates
`needs-human-review` on first use; the others are standard GitHub defaults
that most repos already have.

| Label | Color | Applied by | Meaning |
|---|---|---|---|
| `needs-human-review` | `fbca04` (yellow) | Agents **and** humans | Awaiting a human decision (triage, merge, or scope). `file-issue.sh` adds it to every agent-filed issue; humans add it to non-auto-merge PRs at creation. Never removed automatically. |
| `human-reviewed` | `0e8a16` (green) | **Humans only — agents forbidden** | A human has made a disposition decision on the item: merged, closed, bound to a plan item, or commented with a decision. Proves the audit trail. Only a human GitHub account may apply this label; if a non-human actor ever applies it, that is a bug. |
| `bug` | `d73a4a` (red) | Agents and humans | Standard GitHub label for defects. |
| `enhancement` | `a2eeef` (cyan) | Agents and humans | Standard GitHub label for feature requests and improvements. |

Why `human-reviewed` matters: agents operate under the developer's own `gh`
credentials, so GitHub records every agent-driven merge/close/comment under
the human's account. The label is the one signal that cleanly distinguishes
"a human actually looked at this" from "Claude ran `gh` as me." Humans
apply it as part of the action — `gh pr edit <n> --add-label human-reviewed`
when they merge — and agents treat its absence as "still unverified."

To bootstrap the two BSG labels on a new repo (one-time, idempotent):

```bash
gh label create needs-human-review \
  --color fbca04 \
  --description "Awaiting a human decision (triage, merge, or scope)"

gh label create human-reviewed \
  --color 0e8a16 \
  --description "A human has reviewed and validated this item (agents MUST NOT apply)"
```

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

### The `tick` convention (periodic agent and skill runs)

All BSG agents and reporting skills expose a single conventional verb
for "do your periodic job now": `tick`. Users invoke it as
`@<agent> tick` (for subagents) or `<skill> tick` / a routed slash
command (for skills), typically driven by Claude Code's own
[`/loop`][loop] or [`/schedule`][schedule] — never by GitHub Actions,
Renovate, or any org-level cron. See the "The `tick` convention"
section of the top-level [`CLAUDE.md`][claude-md] for the full
rationale.

Every `tick` implementation must satisfy three rules:

1. **Idempotent and silent by default.** Write the dated output to the
   repo (`po/reports/YYYY-MM-DD-*.md`,
   `compliance/reports/YYYY-MM-DD-*.md`, etc.), land it through
   [`open-report-pr.sh`][open-report-pr] so it ships via auto-merge PR,
   and reply in chat with **one line** unless an explicit
   silence-breaker fires. "All green" is not a chat message — it is a
   committed file.
2. **Explicit silence-breakers.** Each agent or reporting skill must
   list, in its own body, the exact conditions that allow it to break
   silence (drift score crossed a threshold, a non-compliant repo
   appeared, a milestone went overdue, …). Thresholds live in the
   agent's or skill's own file, not centrally — they are part of that
   agent's product definition.
3. **Repo-scoped.** `tick` runs inside one repo's working directory and
   touches only that repo. Multi-repo sweeps are out of scope.

#### For agents

Every file in `claude-skills/agents/` must declare a `tick:` field in
its YAML frontmatter, describing what the agent's periodic run does.
The test in [`claude-skills/tests/test_skills.py`][tests]
(`test_every_agent_declares_a_tick_action`) enforces that the field
exists and is non-empty.

A minimal example:

```yaml
---
name: my-agent
output: pr
tick: >
  Run the periodic audit, land the report under <agent>/reports/YYYY-MM-DD-*.md
  via open-report-pr.sh, and stay silent in chat unless a silence-breaker
  fires (list them explicitly in the agent body).
---
```

Best practice: keep the frontmatter summary short and put the concrete
step-by-step + silence-breaker table in a dedicated "Tick action"
section of the agent body, so the LLM has a single place to look when
the user types `tick`.

#### For reporting skills

Skills under `claude-skills/skills/<name>/` that produce a periodic
report or audit (today: `po`, `github-compliance`) document their
`tick` as a top-level **"Tick action"** section in `SKILL.md`. There is
no frontmatter test for skills — the section is the contract. Mirror
the agent layout: numbered steps, a silence-breakers table, and a
"Silence is a feature" reminder so the LLM does not pad the chat reply.

[claude-md]: https://github.com/beyond-scale-group/bsg-stack/blob/main/CLAUDE.md
[tests]: https://github.com/beyond-scale-group/bsg-stack/blob/main/claude-skills/tests/test_skills.py
[open-report-pr]: https://github.com/beyond-scale-group/bsg-stack/blob/main/claude-skills/scripts/open-report-pr.sh
[loop]: https://docs.claude.com/en/docs/claude-code/skills
[schedule]: https://docs.claude.com/en/docs/claude-code/skills

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
