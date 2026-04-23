---
name: browser
description: >-
  Browser automation CLI for AI agents. Use when the user needs to interact
  with websites, including navigating pages, filling forms, clicking buttons,
  taking screenshots, extracting data, testing web apps, or automating any
  browser task. Triggers include requests to "open a website", "fill out a
  form", "click a button", "take a screenshot", "scrape data from a page",
  "test this web app", "login to a site", "automate browser actions", or any
  task requiring programmatic web interaction. Wraps `agent-browser` with
  persistent profile management, a curated Google login helper, and
  headed-first-then-headless defaults.
version: 0.1.0
---

# Browser Skill

Browser automation for AI agents, wrapping the
[`agent-browser`](https://www.npmjs.com/package/agent-browser) CLI with
persistent login profiles so authenticated sessions survive across runs.

Binary: `agent-browser` (npm package `agent-browser`, installed globally).
This CLI evolves fast -- **never assume memorized flags**, verify with
`agent-browser --help` before scripting.

## First-time setup -> `scripts/onboard.sh`

If the user has never logged in to BSG services via agent-browser, point them
at the onboarding orchestrator:

```bash
bash scripts/onboard.sh
```

It walks through **4 services** in headed mode, one at a time:

| Step | Profile | Service |
|------|---------|---------|
| 1 | `google` | Google (Gmail, Drive, GCP Console) |
| 2 | `github` | GitHub |
| 3 | `hubspot` | HubSpot (CRM, Marketing, Sales) |
| 4 | `yousign` | Yousign (e-signatures) |

For each service a browser window opens, the user logs in (including 2FA /
passkey), and the session is saved as a named profile. After onboarding,
every `agent-browser --profile <name>` call reuses the saved session
headlessly -- no more manual logins.

Re-run a single step:
```bash
bash scripts/onboard.sh --step google
bash scripts/onboard.sh --step yousign
```

Check all profiles:
```bash
bash scripts/onboard.sh --check
```

List available services:
```bash
bash scripts/onboard.sh --list
```

## Chrome MCP fallback

**Default tool is always `agent-browser`.** Try it first for every task.

Some sites actively block headless browsers and Playwright-based automation
(anti-bot walls, aggressive CAPTCHAs, device fingerprinting). When
`agent-browser` gets stuck — page won't load, CAPTCHA loop, login rejected —
**fall back to Chrome MCP** (`claude-in-chrome`), which connects to the user's
real Chrome instance with all existing sessions, cookies, and extensions.

Known sites that frequently require Chrome MCP fallback:

| Site | Typical blocker |
|---|---|
| LinkedIn | Anti-bot detection, login challenge |
| Pappers | CAPTCHA / bot wall |
| Gmail (complex flows) | Passkey re-auth, device trust |
| HubSpot | SSO redirect loops |
| Yousign | Session validation |

Decision flow:

```
1. Try agent-browser (with --profile if authenticated)
2. Blocked? (CAPTCHA, anti-bot, login rejected, blank page)
   → Switch to Chrome MCP — the user's real Chrome is already logged in
3. Chrome MCP unavailable? (no Chrome open, extension not running)
   → Ask the user to open Chrome and enable the MCP extension
```

Chrome MCP is **not** a replacement for `agent-browser` — it cannot run
headlessly, cannot save/replay profiles, and depends on the user's live
Chrome session. Use it only when `agent-browser` hits a wall.

## Hard rules

1. **Scripts do the work.** This SKILL.md narrates; the `scripts/` directory
   contains the actual logic. Do not re-implement browser automation in-chat.
2. **Headed for first-time logins, headless for replay.** When establishing a
   new login session, always use `--headed` so the user can complete 2FA /
   passkey prompts visually. Subsequent runs reuse the saved profile headlessly.
3. **Never store credentials in scripts.** Use `agent-browser`'s auth vault
   (`auth save` / `auth login`) or profile persistence -- never hardcode
   passwords.
4. **Confirm before navigating to sensitive sites.** If a script will open
   banking, email, or admin consoles, tell the user what's about to happen
   and why.
5. **Close the browser when done.** Always call `agent-browser close` at the
   end of an automation sequence to free resources.

## Preflight (run first, every session)

Before issuing any `agent-browser` command, run these checks once per session:

```bash
# 1. Binary present + version
command -v agent-browser >/dev/null \
  || { echo "agent-browser not installed: npm install -g agent-browser"; exit 1; }
INSTALLED=$(agent-browser --version 2>/dev/null | head -1)

# 2. Up-to-date? (soft check -- warn, don't block)
LATEST=$(npm view agent-browser version 2>/dev/null || echo "")
[ -n "$LATEST" ] && [ "$INSTALLED" != "$LATEST" ] && \
  echo "Warning: agent-browser $INSTALLED installed, $LATEST available -> npm install -g agent-browser"

# 3. Browser available?
agent-browser doctor --json 2>/dev/null | jq -e '.browser.ok' >/dev/null \
  || { echo "No browser found -- run: agent-browser install"; exit 1; }
```

If any check fails, surface it to the user **before** attempting the task:

- **Binary missing** -> `npm install -g agent-browser`
- **Outdated** -> warn, but continue; suggest the upgrade command.
- **No browser** -> `agent-browser install` (downloads Chrome for Testing).

## Profile management

Profiles persist full browser state (cookies, IndexedDB, service workers,
localStorage) across runs. The skill uses named profiles via `--profile`:

```bash
# Launch with a named profile (creates it if new)
agent-browser --profile google open https://accounts.google.com --headed

# Subsequent runs reuse the same profile (headless is fine)
agent-browser --profile google open https://console.cloud.google.com
```

Profiles are stored by `agent-browser` in its default data directory
(`~/.agent-browser/profiles/` or platform equivalent). Use
`agent-browser state list` to see saved states.

### Google login helper

For the common case of logging into a Google account:

```bash
bash scripts/login-google.sh [email@example.com]
```

This opens `accounts.google.com` in headed mode, waits for the user to
complete authentication (including 2FA / passkey), and saves the session
under the `google` profile. Subsequent `agent-browser --profile google`
calls land logged in.

### Generic profile wrapper

For any site that needs a persistent profile:

```bash
bash scripts/with-profile.sh <profile-name> [agent-browser args...]
```

Examples:

```bash
bash scripts/with-profile.sh github open https://github.com --headed
bash scripts/with-profile.sh notion open https://notion.so --headed
# After login, headless replay works:
bash scripts/with-profile.sh github open https://github.com/settings
```

## Decision tree

```
First time using agent-browser?  -> npm install -g agent-browser && agent-browser install
First time at BSG / new machine? -> bash scripts/onboard.sh         (all services)
Need to log in to Google?        -> bash scripts/onboard.sh --step google
Need to log in to another site?  -> bash scripts/with-profile.sh <name> open <url> --headed
Check all logins still valid?    -> bash scripts/onboard.sh --check
Replay an authenticated session? -> bash scripts/with-profile.sh <name> open <url>
One-off page interaction?        -> agent-browser open <url> [--headed]
Screenshot a page?               -> agent-browser screenshot [path] [--full]
Extract page text?               -> agent-browser snapshot | jq
```

## Core verbs reference

The verbs BSG agents tend to need most:

| Verb | Command | Notes |
|------|---------|-------|
| Open a URL | `agent-browser open <url>` | Add `--headed` to see the browser |
| Click | `agent-browser click <selector>` | Use `@ref` from snapshot or CSS selector |
| Fill a field | `agent-browser fill <selector> "text"` | Clears first, then types |
| Type (append) | `agent-browser type <selector> "text"` | Does not clear existing value |
| Press a key | `agent-browser press Enter` | Supports combos: `Control+a` |
| Screenshot | `agent-browser screenshot [path]` | `--full` for full page, `--annotate` for labeled elements |
| Accessibility tree | `agent-browser snapshot` | Best for AI -- returns refs like `@e1`, `@e2` |
| Get text | `agent-browser get text <selector>` | Extract text content of an element |
| Get page title | `agent-browser get title` | |
| Get current URL | `agent-browser get url` | |
| Wait for element | `agent-browser wait <selector>` | Waits for visibility |
| Wait for text | `agent-browser wait --text "Welcome"` | Substring match |
| Wait for URL | `agent-browser wait --url "**/dashboard"` | Glob pattern |
| Upload file | `agent-browser upload <selector> <file>` | |
| Close | `agent-browser close` | Always close when done |

## Dealing with 2FA, passkeys, and CAPTCHAs

These require human interaction. The pattern is always:

1. Open the page in **headed** mode (`--headed`)
2. Tell the user what to do ("complete the 2FA prompt in the browser window")
3. **Wait** for the expected post-auth state:
   ```bash
   agent-browser wait --url "**/dashboard" --timeout 120000
   # or
   agent-browser wait --text "Welcome back" --timeout 120000
   ```
4. Save the session (profile persistence handles this automatically)
5. Continue with the automation

For Google specifically, **GCP Console always demands passkey
re-authentication** even with a saved session. Batch manual GCP Console
steps into one session so the user authenticates once.

## Screenshotting on failure

When an automation step fails, take a diagnostic screenshot before
reporting the error:

```bash
agent-browser screenshot /tmp/browser-error-$(date +%s).png --full
```

This helps debug what state the page was in when the failure occurred.

## Extracting data

Two approaches depending on the use case:

**Structured (AI-friendly):** Use `snapshot` for the accessibility tree.
Returns element refs (`@e1`, `@e2`) that can be used in subsequent commands:
```bash
agent-browser snapshot
```

**Raw text:** Use `get text` on a specific element or `eval` for custom
extraction:
```bash
agent-browser get text "#main-content"
agent-browser eval "document.querySelectorAll('table tr').length"
```

## SPA navigation

Single-page apps don't trigger full page loads. After clicking a link in
an SPA:

```bash
agent-browser click "@e5"
agent-browser wait --url "**/new-route"    # wait for client-side route change
agent-browser snapshot                      # get the new page state
```

Do **not** rely on `wait --load networkidle` for SPAs -- it may never fire
if the app keeps open connections.

## Intent routing

| User says... | Do... |
|---|---|
| "Set up browser", "onboard", "log in to everything" | `bash scripts/onboard.sh` |
| "Log in to Google" | `bash scripts/onboard.sh --step google` |
| "Log in to GitHub" | `bash scripts/onboard.sh --step github` |
| "Log in to HubSpot" | `bash scripts/onboard.sh --step hubspot` |
| "Log in to Yousign" | `bash scripts/onboard.sh --step yousign` |
| "Blocked by CAPTCHA / anti-bot on LinkedIn, Pappers…" | Fall back to **Chrome MCP** (user's real Chrome) |
| "Check my logins", "are sessions still valid?" | `bash scripts/onboard.sh --check` |
| "Log in to X" (non-BSG site) | `bash scripts/with-profile.sh <name> open <url> --headed` |
| "Open this URL", "go to site" | `agent-browser open <url> [--headed]` |
| "Take a screenshot" | `agent-browser screenshot [path] [--full] [--annotate]` |
| "Click the submit button" | `agent-browser snapshot` then `agent-browser click @ref` |
| "Fill out the form" | `agent-browser snapshot`, identify fields, `agent-browser fill @ref "value"` |
| "Extract text from the page" | `agent-browser snapshot` or `agent-browser get text <sel>` |
| "Test this web app" | Open, interact, screenshot, assert with `get text` / `is visible` |
| "Install agent-browser" | `npm install -g agent-browser && agent-browser install` |
| "What version?" | `agent-browser --version` |

## Environment variables

| Variable | Purpose |
|---|---|
| `AGENT_BROWSER_PROFILE` | Default profile name (avoids `--profile` on every call) |
| `AGENT_BROWSER_HEADED` | `true` to always show browser window |
| `AGENT_BROWSER_SESSION` | Session name for multi-instance isolation |
| `AGENT_BROWSER_ENCRYPTION_KEY` | Encrypt state files at rest |
| `AGENT_BROWSER_DOWNLOAD_PATH` | Default download directory |
| `AGENT_BROWSER_CONTENT_BOUNDARIES` | Wrap output in LLM-safe delimiters |
| `AGENT_BROWSER_MAX_OUTPUT` | Truncate page output to N characters |
| `AGENT_BROWSER_ALLOWED_DOMAINS` | Restrict navigation to listed domains |

## Stay current with the tool

`agent-browser` adds features frequently. When in doubt, prefer discovery
over memory:

1. **Live help** (fastest, always right for this machine):
   ```bash
   agent-browser --help
   agent-browser <command> --help
   ```

2. **Context7** for upstream docs:
   ```
   Library ID: /vercel-labs/agent-browser
   Use mcp__context7__query-docs with that library ID and a specific question.
   ```

3. **This skill's reference files** -- stable baseline, may lag behind CLI.

---

## How to improve this skill

This file is a cached copy of `claude-skills/skills/browser/SKILL.md` in
[beyond-scale-group/bsg-stack](https://github.com/beyond-scale-group/bsg-stack).
That repo is the single source of truth -- `~/.claude/skills/browser/SKILL.md` is
overwritten every time the BSG install flow runs.

If the user asks you to improve, fix, or extend this skill, do **not** edit
the local file. Instead:

1. `gh repo clone beyond-scale-group/bsg-stack` (or work in an existing clone)
2. Edit `claude-skills/skills/browser/SKILL.md` on a feature branch
3. Open a pull request against `main`

Bug reports and ideas without a fix -> open an issue on the same repo.
