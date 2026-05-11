---
name: google-apps-script
description: >-
  Google Apps Script management via clasp (google/clasp). Clone, push, pull,
  run, deploy, and read logs for Apps Script projects from the terminal.
  Use when the user works with .gs files, Apps Script automation,
  or asks to debug/deploy/run Apps Script functions.
  Triggers include "google apps script", "clasp", "debug apps script",
  "run apps script", "push apps script", "deploy apps script",
  "pull apps script", "apps script logs".
---

# Google Apps Script (`clasp`)

CLI wrapper for [google/clasp](https://github.com/nicholasgasior/clasp) — the
official tool for developing Google Apps Script projects locally.

Binary: `clasp` (npm package `@google/clasp`, installed globally — upgrade
with `npm install -g @google/clasp`).

## First-time setup → `scripts/onboard.sh`

If the user has never run `clasp` on this machine — no binary, no OAuth
credentials — point them at the orchestrator:

```bash
bash scripts/onboard.sh
```

It runs 3 idempotent steps: install → login → verify. Re-run a single
step with `--step <name>` (`install`, `login`, `verify`).

## Health check → `scripts/doctor.sh`

For sessions where `clasp` is already configured:

```bash
bash scripts/doctor.sh           # full report
bash scripts/doctor.sh --quiet   # exit codes only, silent on green
```

Exits `0` (healthy), `1` (warnings — e.g. outdated version), or `2`
(auth broken).

## Preflight (run first, every session)

Before issuing any `clasp` command, run the preflight script once per
session. It checks binary, auth, and project context — and **auto-runs
`onboard.sh`** when clasp is missing or not authenticated:

```bash
bash scripts/preflight.sh
```

If `preflight.sh` exits non-zero, do not proceed — surface the error to
the user. The script already explains what's wrong and what to do.

If you need to check individual pieces without auto-remediation:

```bash
command -v clasp >/dev/null       # binary present?
[ -f ~/.clasprc.json ]            # authenticated?
[ -f .clasp.json ]                # inside a project?
```

## Multiple accounts

By default clasp stores credentials globally in `~/.clasprc.json` — one
account at a time. To work with a different Google account (e.g.
`gdumas@expert-flow.ai` instead of your default):

### Option 1: `CLASP_AUTH` env var (recommended for multi-account)

Point `CLASP_AUTH` to a separate credentials file per account:

```bash
# Login with the other account and store creds separately
CLASP_AUTH=~/.clasprc-expert-flow.json clasp login

# All subsequent commands use that account
export CLASP_AUTH=~/.clasprc-expert-flow.json
clasp clone <scriptId>
clasp push
clasp run myFunction
```

Add to `~/.zshrc.user` to persist:

```bash
export CLASP_AUTH_EXPERT_FLOW="$HOME/.clasprc-expert-flow.json"
# Then use: CLASP_AUTH=$CLASP_AUTH_EXPERT_FLOW clasp <command>
```

### Option 2: switch the global account

```bash
clasp logout
clasp login    # authenticate with the other account
```

This overwrites `~/.clasprc.json` — you lose the previous session.

### Option 3: per-project local auth

```bash
cd my-project/
clasp login --no-localhost   # stores .clasprc.json in the project dir
```

Clasp checks the project directory first, then `$CLASP_AUTH`, then
`~/.clasprc.json`.

### Which account am I using?

```bash
# Check the current credentials file
cat "${CLASP_AUTH:-$HOME/.clasprc.json}" | jq '.token.access_token' -r \
  | xargs -I{} curl -s "https://www.googleapis.com/oauth2/v1/tokeninfo?access_token={}" \
  | jq '.email'
```

The preflight script (`scripts/preflight.sh`) respects `CLASP_AUTH` — set
it before running and the auto-onboard will store credentials in the
right file.

## Decision tree

```
First-time setup?      → bash scripts/onboard.sh                §First-time setup
Health check?          → bash scripts/doctor.sh                  §Health check
Clone a project?       → clasp clone <scriptId>                  §Clone
Pull remote changes?   → clasp pull                              §Pull
Push local changes?    → clasp push                              §Push
Run a function?        → clasp run <functionName>                §Run
View logs?             → clasp logs                              §Logs
Create a deployment?   → clasp deploy                            §Deploy
List deployments?      → clasp deployments                       §Deploy
Create new project?    → clasp create                            §Create
Open in browser?       → clasp open                              §Open
Write .gs code?        → load references/writing-patterns.md     §Writing
```

## Core commands

### Clone

Pull an existing Apps Script project into the current directory:

```bash
clasp clone <scriptId>
```

The script ID is in the Apps Script editor URL:
`https://script.google.com/home/projects/<scriptId>/edit`

Creates `.clasp.json` (project binding) and `appsscript.json` (manifest)
plus all `.js`/`.html` files. The `.clasp.json` file should be committed
to the repo; it maps the local directory to the remote project.

To clone into a specific directory:

```bash
clasp clone <scriptId> --rootDir ./src
```

### Pull

Download the latest remote source into the local directory:

```bash
clasp pull
```

Overwrites local files with the remote version. Run before editing if
someone may have changed the script in the web editor.

### Push

Upload local files to the Apps Script project:

```bash
clasp push
clasp push --watch   # auto-push on file changes
```

Only files matching the `filePushOrder` and file extensions in
`appsscript.json` are uploaded. `.claspignore` works like `.gitignore`
for excluding files from push.

### Run

Execute a function remotely and get the return value:

```bash
clasp run <functionName>
clasp run <functionName> --params '[1, "hello", true]'
```

**Prerequisites for `clasp run`:**

1. The script must have an **Apps Script API Executable** deployment
   (not a web app deployment)
2. The GCP project linked to the script must have the
   **Apps Script API** enabled
3. The OAuth token must include
   `https://www.googleapis.com/auth/script.projects` scope

Setup steps if `clasp run` fails with permission errors:

```bash
# 1. Open the script's GCP project settings
clasp open --addon
# or navigate to: script.google.com → Project Settings → Google Cloud Platform (GCP) Project

# 2. In GCP Console, enable the Apps Script API:
#    APIs & Services → Library → search "Apps Script API" → Enable

# 3. Re-login with the required scope
clasp login --creds creds.json
```

### Logs

Read execution logs:

```bash
clasp logs            # recent executions
clasp logs --watch    # stream logs in real-time
clasp logs --json     # machine-readable output
```

`Logger.log()` output is **not** visible via `clasp logs` — only
`console.log()` (Cloud Logging) and execution metadata (start time,
duration, status, error messages) are returned.

For `Logger.log()` output, two workarounds:

1. Replace with `console.log()` (preferred — shows in `clasp logs`)
2. Return the logged values from the function and capture via
   `clasp run <fn>` (the return value is printed to stdout)

### Deploy

Create a versioned deployment:

```bash
clasp deploy                              # new deployment
clasp deploy -V 1 -d "Production v1"     # with version and description
clasp deployments                          # list all deployments
clasp undeploy <deploymentId>             # remove a deployment
```

### Create

Create a new Apps Script project:

```bash
clasp create --title "My Script"
clasp create --title "My Script" --type sheets    # bound to Sheets
clasp create --title "My Script" --type docs      # bound to Docs
clasp create --title "My Script" --type slides     # bound to Slides
clasp create --title "My Script" --type forms      # bound to Forms
clasp create --title "My Script" --rootDir ./src
```

### Open

Open the project in the browser:

```bash
clasp open           # open the script editor
clasp open --webapp  # open the deployed web app URL
clasp open --addon   # open the GCP project
```

## `.claspignore`

Works like `.gitignore`. Common patterns:

```
node_modules/
tests/
*.test.js
*.test.ts
README.md
CLAUDE.md
```

## TypeScript support

`clasp push` transpiles `.ts` files to `.gs` automatically. Use
`tsconfig.json` to control compilation. Install type definitions:

```bash
npm install -D @types/google-apps-script
```

This gives autocompletion and type checking for all Apps Script
services (`SpreadsheetApp`, `GmailApp`, `CalendarApp`, etc.).

## Debugging patterns

Since there's no interactive debugger via CLI, use these patterns:

**1. Return-value debugging** — wrap the suspect function:

```javascript
function debugMyFunction() {
  var result = myFunction();
  return JSON.stringify({
    result: result,
    type: typeof result,
    timestamp: new Date().toISOString()
  }, null, 2);
}
```

Then: `clasp run debugMyFunction` — the JSON is printed to stdout.

**2. Console.log debugging** — add `console.log()` calls, push, run,
then `clasp logs --json | jq` to read output.

**3. Try/catch wrapping** — for functions that fail silently:

```javascript
function safeSendSMS() {
  try {
    sendSMS();
    return { success: true };
  } catch (e) {
    return { error: e.message, stack: e.stack };
  }
}
```

Then: `clasp run safeSendSMS`

## Safety rules

Confirm with the user **before**:

- **`clasp push`** — overwrites remote code; ask if there are unsaved
  changes in the web editor
- **`clasp run`** on functions that send emails, modify calendars, write
  to sheets, or call external APIs — side effects are real and immediate
- **`clasp deploy`** — creates a new deployment that may be served to
  users or triggered automatically
- **`clasp undeploy`** — removes a deployment (may break live integrations)

Reads are always safe: `clasp pull`, `clasp logs`, `clasp open`,
`clasp deployments`, `clasp status`.

## Runtime and quotas

**V8 runtime only** — Rhino was removed in January 2026. All scripts run
on V8 and support modern JavaScript (arrow functions, `const`/`let`,
destructuring, template literals, `async`/`await` for `UrlFetchApp`).

Key execution limits:

| Limit | Value |
|---|---|
| Regular function execution | 6 minutes |
| Custom function in cell (`=MYFUNC()`) | 30 seconds |
| Trigger execution | 6 minutes (simple), 10 minutes (installable) |
| `UrlFetchApp.fetch()` per execution | 50 calls |
| `UrlFetchApp` response size | 50 MB |
| Email quota (consumer `@gmail.com`) | 100/day |
| Email quota (Workspace) | 1,500/day |
| Properties Service value size | 9 KB per value |
| Properties Service total | 500 KB per store |
| Script project size | 50 MB |
| Simultaneous executions | 30 per user |

When a function hits the 6-minute limit, it throws a
`ScriptError: Exceeded maximum execution time`. For long-running work,
split into batches and chain via time-driven triggers.

**Batch operations are mandatory for performance.** Cell-by-cell
`getValue()`/`setValue()` is ~70x slower than bulk
`getValues()`/`setValues()`. Always read a range into a 2D array,
process in-memory, and write back in one call. Call
`SpreadsheetApp.flush()` before returning from functions that modify
cells.

## Writing Apps Script code

For **writing** `.gs`/`.js` code (custom menus, triggers, dialogs, PDF
export, sidebars, data validation, UrlFetchApp, batch patterns), load
the reference file:

- [references/writing-patterns.md](references/writing-patterns.md) —
  script structure template, critical rules (public vs private functions,
  batch ops, flush, V8 quirks), common patterns (toast, alert, progress
  dialog, sidebar, triggers, email, PDF export, API calls, validation,
  Properties Service), recipes (archive rows, batch email with quota
  check), error prevention table, deployment checklist.

Load it when the user is authoring code — not needed for pure CLI
operations (push, pull, deploy).

Adapted from [jezweb/claude-skills](https://github.com/jezweb/claude-skills)
(google-apps-script, MIT license).

## Common pitfalls

- **`clasp run` "Script function not found"** — the function must be
  at the top level (not inside a module or class), and you must
  `clasp push` after local edits before running
- **`clasp run` permission errors** — see the "Prerequisites for
  clasp run" section above; the Apps Script API must be enabled and
  the deployment type must be "API Executable"
- **`Logger.log()` not visible** — use `console.log()` instead, or
  return values from `clasp run`
- **Push doesn't include a file** — check `.claspignore` and the
  `filePushOrder` in `appsscript.json`; only `.js`, `.gs`, `.ts`,
  and `.html` files are pushed by default
- **Manifest conflicts** — `appsscript.json` is both local and remote;
  `clasp pull` overwrites local, `clasp push` overwrites remote.
  Keep it in version control.
- **Bound scripts** (container-bound to a Sheet/Doc) can't be cloned
  by URL — use the script ID from
  Extensions → Apps Script → Project Settings

---

## How to improve this skill

This file is a cached copy of `claude-skills/skills/google-apps-script/SKILL.md` in
[beyond-scale-group/bsg-stack](https://github.com/beyond-scale-group/bsg-stack).
That repo is the single source of truth — `~/.claude/skills/google-apps-script/SKILL.md` is
overwritten every time the BSG install flow runs.

If the user asks you to improve, fix, or extend this skill, do **not** edit
the local file. Instead:

1. `gh repo clone beyond-scale-group/bsg-stack` (or work in an existing clone)
2. Edit `claude-skills/skills/google-apps-script/SKILL.md` on a feature branch
3. Open a pull request against `main`

Bug reports and ideas without a fix → open an issue on the same repo.
