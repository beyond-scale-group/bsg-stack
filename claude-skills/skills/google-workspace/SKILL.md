---
name: google-workspace
description: >-
  Official Google Workspace CLI (`gws` from github.com/googleworkspace/cli)
  for Gmail, Calendar, Drive, Sheets, Slides, Tasks, People, Chat, Meet,
  Forms, Keep, Classroom, plus cross-service workflow helpers. Use whenever
  the user works with Google Workspace from their own account — send/read/
  triage email, list/schedule/search calendar events, search/upload/share
  Drive files, read/append Sheets, create Slides, manage Tasks or Contacts,
  post in Chat, fetch Meet records, read/write Forms, or run
  `+standup-report`, `+meeting-prep`, `+email-to-task`, `+weekly-digest`,
  `+file-announce`. Triggers include "send an email", "check my inbox",
  "triage gmail", "what's on my calendar", "next meeting", "find a Drive
  file", "upload to Drive", "read this sheet", "post in Chat", "today's
  standup", "weekly digest", "envoyer un mail", "agenda du jour",
  "prochaine réunion", "Google Workspace". Not for Admin SDK / user
  provisioning — use the `workspace-admin` skill instead.
---

# Google Workspace (`gws`)

The official Google Workspace CLI. Every Workspace API is reachable via a
uniform pattern, plus curated `+` helpers for the 90% of common tasks.

Binary: `/opt/homebrew/bin/gws` (npm package `@googleworkspace/cli`,
installed globally — upgrade with `npm install -g @googleworkspace/cli@latest`).
This CLI evolves fast — **never assume memorized flags**, verify with
`gws <svc> --help` or `gws schema <svc.res.method>` before scripting.

For Admin SDK (user provisioning on `the-shift.ai`), use the separate
`workspace-admin` skill — `gws` doesn't cover Admin APIs.

## First-time setup → `scripts/onboard.sh`

If the user has never run `gws` on this machine — no binary, no OAuth
client, no consent-screen scopes registered, no Chat app — point them at
the orchestrator:

```bash
bash scripts/onboard.sh
```

It walks 7 idempotent steps (prereqs → enable APIs → OAuth client →
consent-screen scopes → Chat app → login → smoke tests). Steps that
require GCP Console interaction print the exact URL + checklist and
pause. Re-run a single step with `--step <name>` (`prereqs`, `apis`,
`oauth`, `scopes`, `chat-app`, `login`, `smoke`).

⚠ **GCP Console always demands passkey re-authentication**, even with a
saved browser session. Plan to authenticate once and run the manual
steps back-to-back so the session covers them all.

Browser automation for the GCP Console steps will land via a future
`/browser` skill (tracked in beyond-scale-group/bsg-stack#39); until then,
those steps are manual.

## Daily health check → `scripts/doctor.sh`

For sessions where `gws` is already configured, the doctor is the
fast read-only check:

```bash
bash scripts/doctor.sh           # full report
bash scripts/doctor.sh --quiet   # exit codes only, silent on green
```

Exits `0` (healthy), `1` (warnings — e.g. outdated version), or `2` (auth
or service failing). Auto-repairs missing scopes by re-running
`auth-login.sh` and re-checking — only escalates to manual if the scope
is missing from the consent-screen registration.

## Preflight (run first, every session)

Before issuing any `gws` command, run these three checks once per session.
They are cheap, catch the common failure modes up front, and take under a
second:

```bash
# 1. Binary present + version (installed via npm, not Homebrew)
command -v gws >/dev/null || { echo "gws not installed: npm install -g @googleworkspace/cli@latest"; exit 1; }
INSTALLED=$(gws --version | head -1 | awk '{print $2}')

# 2. Up-to-date? (soft check — warn, don't block)
LATEST=$(npm view @googleworkspace/cli version 2>/dev/null || echo "")
[ -n "$LATEST" ] && [ "$INSTALLED" != "$LATEST" ] && \
  echo "⚠ gws $INSTALLED installed, $LATEST available → npm install -g @googleworkspace/cli@latest"

# 3. Auth valid? stdout=JSON, stderr=keyring chatter (discarded).
#    v0.22+ rejects --format json; the command emits JSON unconditionally.
gws auth status 2>/dev/null \
  | jq -e '.token_valid == true and .encrypted_credentials_exists == true' >/dev/null \
  || { echo "⚠ gws auth invalid — running the auth helper…"; \
       bash "$(dirname "$0")/scripts/auth-login.sh"; }
```

If any check fails, surface it to the user **before** attempting the task:

- **Binary missing** → `npm install -g @googleworkspace/cli@latest`
- **Outdated** → warn, but continue; suggest the upgrade command.
  APIs and flags change — if a flag behaves unexpectedly, re-check
  `gws <svc> --help` against the user's installed version.
- **Auth invalid / `invalid_rapt`** → run **[`scripts/auth-login.sh`](scripts/auth-login.sh)**.
  It starts `gws auth login`, extracts the OAuth URL from stdout, opens
  it in Google Chrome (or the OS default browser as fallback), waits
  for the callback, and verifies `token_valid == true` before exiting.

  **Defaults to a curated 15-scope list** covering every Workspace API
  the skill exercises (Drive, Sheets, Gmail, Calendar, Docs, Slides,
  Tasks, Chat, Contacts, Directory, Forms, Meet, OpenID). Picking
  scopes explicitly — instead of `--full` — surfaces the silent drops
  Google performs when a scope isn't registered on the consent screen.

  ⚠ Even the curated list does **not** fix:
    - `403 Caller does not have required permission to use project …`
      → that's a **GCP IAM** problem; see the "403 on Drive/Tasks/Chat/People"
      section below.
    - `404 Google Chat app not found` on `gws chat *`
      → Chat needs the GCP project to have a registered Chat app
      configuration; see the "Chat API" section below or run
      `bash scripts/onboard.sh --step chat-app`.

  Override when you want narrower or wider scopes:
  ```
  bash scripts/auth-login.sh --readonly
  bash scripts/auth-login.sh --services gmail,calendar,drive
  bash scripts/auth-login.sh --scopes https://www.googleapis.com/auth/drive.readonly
  bash scripts/auth-login.sh --full   # everything gws knows about
  ```
  **Always prefer this helper over bare `gws auth login`** — it saves
  the user a copy/paste step, opens Chrome, and confirms success.

### Stay current with the tool's shape

`gws` adds services, helpers, and flags often. When in doubt, **prefer
discovery over memory** — in this order:

1. **Live help from the installed binary** (fastest, always right for *this* machine):
   ```bash
   gws --help                         # top-level services
   gws <service> --help               # resources + helpers for a service
   gws <service> <resource> --help    # methods on a resource
   gws schema <service.resource.method> [--resolve-refs]   # full params/body
   ```

2. **Context7 for the latest upstream docs** (recent README, new helpers,
   release notes — ahead of the installed binary if it's out of date):
   ```
   Library ID: /googleworkspace/cli
   Use the mcp__context7__query-docs tool with that library ID and a
   specific question, e.g. "How do I send a Gmail message with an
   attachment?" or "What's the new syntax for drive files list --page-all?"
   ```
   Call context7 whenever:
   - a command errors with "unknown flag" or unexpected output
   - the user asks about a feature not documented here
   - the installed `gws` version is lower than the latest Homebrew version
   - you need examples beyond the `--help` text

3. **This skill's reference files** — stable baseline patterns, but may
   lag behind the upstream CLI. Treat as the starting point, not the
   source of truth.

This skill documents v0.16.0 patterns. If the installed version is newer,
trust the live `--help` output and context7 over this document, and
mention any drift to the user.

## Decision tree

```
First-time setup?  → bash scripts/onboard.sh    §First-time setup
Health check?      → bash scripts/doctor.sh     §Daily health check
Common task?       → use a +helper (prefer)     §Helpers
Raw API call?      → gws <svc> <res> <method>   §Raw API
Cross-service?     → gws workflow +<name>       §Workflow
Unknown schema?    → gws schema <svc.res.method> references/raw-api.md
```

Default to `+helpers` before raw API calls. They handle tedious encoding
(RFC 2822 for Gmail, RFC 3339 for Calendar, A1 for Sheets, multipart for
Drive, space resolution for Chat).

## Helpers — the fast path

Full flags in [references/helpers.md](references/helpers.md).

| Service | Helpers |
|---|---|
| `gmail` | `+send`, `+triage`, `+reply`, `+reply-all`, `+forward`, `+watch` |
| `calendar` | `+insert`, `+agenda` (`--today` / `--tomorrow` / `--week` / `--days N`) |
| `drive` | `+upload` |
| `sheets` | `+read`, `+append` |
| `chat` | `+send` |
| `workflow` | `+standup-report`, `+meeting-prep`, `+email-to-task`, `+weekly-digest`, `+file-announce` |

Quick taste:

```bash
gws gmail +triage --max 10 --format table
gws gmail +send --to alice@x.com --subject 'Ping' --body 'hi'
gws calendar +agenda --today --format table
gws calendar +insert --summary 'Review' \
  --start '2026-04-17T10:00:00+02:00' --end '2026-04-17T10:30:00+02:00' \
  --attendee alice@x.com
gws drive +upload ./report.pdf --parent FOLDER_ID --name 'Q1 Report.pdf'
gws sheets +read --spreadsheet $ID --range 'Sheet1!A1:D10' --format csv
gws sheets +append --spreadsheet $ID --json-values '[["Alice",100,true]]'
gws chat +send --space spaces/AAAAxxxx --text 'Deploy done ✅'
gws workflow +standup-report --format table
```

## Raw API — everything else

Pattern: `gws <service> <resource> [sub-resource] <method> [--params JSON] [--json BODY]`

```bash
gws gmail users messages list --params '{"userId":"me","q":"is:unread newer_than:7d","maxResults":10}'
gws drive files list --params '{"q":"mimeType=\"application/pdf\" and trashed=false","pageSize":20,"fields":"files(id,name,modifiedTime)"}'
gws sheets spreadsheets values get --params '{"spreadsheetId":"ID","range":"Sheet1!A1:D10"}'
gws calendar events list --params '{"calendarId":"primary","timeMin":"2026-04-16T00:00:00Z","singleEvents":true,"orderBy":"startTime"}'
```

Discover any method's params **first**:

```bash
gws schema gmail.users.messages.list
gws schema drive.files.create --resolve-refs
```

See [references/raw-api.md](references/raw-api.md) for pagination
(`--page-all`, `--page-limit`), uploads (`--upload`, `--upload-content-type`),
binary downloads (`--output`), formats, and exit codes.

## Service-specific knowledge

Load only the file for the service being used:

- [references/gmail.md](references/gmail.md) — search operator cheat sheet, labels, threads, attachments
- [references/calendar.md](references/calendar.md) — RFC3339 time formats, recurrence, free/busy, calendar IDs vs names
- [references/drive.md](references/drive.md) — Drive query language, MIME types, sharing/permissions, shared drives
- [references/sheets.md](references/sheets.md) — A1 notation, `valueInputOption`, batchUpdate patterns
- [references/recipes.md](references/recipes.md) — cross-service multi-step recipes

For Slides, Docs, Tasks, People, Chat, Meet, Keep, Forms, Classroom:
discover via `gws <svc> --help` and `gws schema <svc.res.method>`.

## Agent-friendly conventions

- **`--dry-run`** validates the request locally without calling Google. Use
  it to verify shape before any mutating call.
- **`--format json`** (default) for parsing; `--format table` for humans;
  `--format csv` for spreadsheet paste; `--format yaml` for diffs.
- **`--page-all`** emits NDJSON (one JSON object per page). Pipe to `jq -s`
  for a single array. Limit with `--page-limit N --page-delay MS`.
- **Exit codes** (check `$?`):
  - `0` ok · `1` API error · `2` auth · `3` validation ·
  - `4` discovery · `5` internal.
- **Environment overrides**:
  - `GOOGLE_WORKSPACE_CLI_TOKEN` — pre-obtained access token (highest priority)
  - `GOOGLE_WORKSPACE_CLI_CONFIG_DIR` — alt config dir (default `~/.config/gws`)
  - `GOOGLE_WORKSPACE_PROJECT_ID` — alt GCP project for quota/billing
  - `GOOGLE_WORKSPACE_CLI_SANITIZE_TEMPLATE` / `_MODE` — Model Armor defaults

## Safety rules

Confirm with the user **before** any command that:

- **Sends** — `gmail +send`, `gmail +reply*`, `gmail +forward`, `chat +send`,
  `workflow +file-announce`, any `messages.send` / `spaces.messages.create`
- **Creates calendar events** with `--attendee` (invitations go out immediately)
- **Writes to Sheets/Docs/Slides** — `sheets +append`, `values.update`,
  `spreadsheets.batchUpdate`, `documents.batchUpdate`, `presentations.batchUpdate`
- **Modifies Drive permissions** — `drive permissions create/update/delete`,
  shared-drive moves
- **Deletes anything** — `files.delete`, `messages.trash`, `events.delete`,
  `tasks.delete`

Everything else (read, list, search, export, `--dry-run`) proceeds directly.

When uncertain, run with `--dry-run` first and show the output before
executing for real.

## Chat API: "Google Chat app not found"

Symptom: `gws chat spaces list` (and most `chat.*` endpoints) return
`403 insufficient authentication scopes`, but your token clearly has
`chat.spaces` / `chat.spaces.readonly`. A direct curl reveals the real
error: `404 Google Chat app not found`.

Cause: the Chat API requires the GCP project to have a **registered Chat
app configuration** (name, description, state) before any endpoint will
respond — even for pure user-context reads. Unlike Drive/Calendar/etc.
which work with just the API enabled, Chat needs the app registered.

Fix (one-time, GCP Console):

1. Open https://console.cloud.google.com/apis/api/chat.googleapis.com/hangouts-chat?project=<PROJECT_ID>
2. Fill in **App name**, **Avatar URL**, **Description**
3. Under **Functionality**, tick the boxes you need ("Receive 1:1 messages",
   "Join spaces and group conversations")
4. Leave **Connection settings** as "App URL" or "HTTP endpoint URL" — for
   read-only user-context CLI use, any placeholder URL works (it's never
   called; you're not a webhook bot)
5. Set **Visibility** to "Make this Chat app available to specific people
   and groups in Workspace domain" and add your email
6. Save

Then Chat APIs respond to user credentials.

## "Insufficient authentication scopes" — OAuth consent screen

Symptom: after a clean `gws auth login --full`, some services still fail
with `403 Request had insufficient authentication scopes`, and inspecting
the access token (`gws auth export --unmasked` → `tokeninfo`) shows only a
subset of the scopes you requested.

Cause: Google silently drops any scope in the OAuth URL that **isn't
registered on the project's consent screen**. The user can't tick a
scope they're not being shown.

Fix (one-time, manual — GCP Console):

1. Open https://console.cloud.google.com/apis/credentials/consent?project=<PROJECT_ID>
2. Edit the app → Scopes → "Add or Remove Scopes"
3. Paste the missing scopes (e.g. `.../chat.spaces`, `.../contacts`,
   `.../directory.readonly`) into the filter and check each
4. Save & Continue
5. Re-run `bash scripts/auth-login.sh --full` and tick every checkbox on
   the consent screen

The enhanced `auth-login.sh` introspects the granted scopes after login
and warns if `--full` was asked but specific scope families were dropped.

## 403 on Drive/Tasks/Chat/People — GCP project IAM

Symptom:

```
403 Caller does not have required permission to use project <PROJECT_ID>.
Grant the caller the roles/serviceusage.serviceUsageConsumer role …
```

This happens because Drive, Tasks, Chat, and People APIs enforce
`serviceusage.services.use` on the GCP project tied to the OAuth client.
Gmail and Calendar skip that check — which is why they work while the
rest return 403 on the same token. OAuth scopes are irrelevant here;
re-authing with `--full` will **not** help.

Three fixes — pick one:

**A. Run the bundled IAM helper** (fastest if you own the project):
```bash
bash scripts/fix-iam-403.sh              # detect project + user, grant role, verify
bash scripts/fix-iam-403.sh --enable-apis  # also `gcloud services enable` the APIs
```
The helper auto-derives the project from `gws auth status`, fetches your
email via Gmail (the one API that always works pre-fix), ensures `gcloud`
is authenticated, applies `roles/serviceusage.serviceUsageConsumer`,
waits for propagation, and verifies with a Drive probe. Overrides:
`GWS_PROJECT_ID=…` / `GWS_USER_EMAIL=…`.

Equivalent raw command if you prefer to run gcloud yourself:
```bash
gcloud projects add-iam-policy-binding <PROJECT_ID> \
  --member=user:<your-email> \
  --role=roles/serviceusage.serviceUsageConsumer
```

**B. Point `gws` at a different GCP project you own** (cleanest,
avoids touching shared projects):
```bash
export GOOGLE_WORKSPACE_PROJECT_ID=<your-own-project-id>
# Add to ~/.zshrc.user to persist across shells
```
No re-auth required — `gws` will route quota to the new project.

**C. Run `gws auth setup`** to let `gws` create a fresh GCP project
wired for you automatically. Requires `gcloud` installed + logged in.
This also replaces the OAuth client.

Find the current project with `gws auth status | jq .project_id`.

## Common pitfalls

- **Gmail `+send` can't attach files.** For attachments use the raw API:
  `gws gmail users messages send --json '{"raw":"<base64 RFC2822>"}'`.
- **Calendar `+insert` doesn't add Meet conferencing.** For conference
  links use `events insert` with `conferenceData` + `conferenceDataVersion=1`.
- **Sheets ranges need quoting** when sheet names contain spaces:
  `--range "'Sales Data'!A1:C10"`.
- **Drive search** uses the Drive query language by default —
  free-text: `q: fullText contains 'foo'`. See references/drive.md.
- **Chat space names** look like `spaces/AAAAxxxx`. Find them with
  `gws chat spaces list`.
- **Token invalidation** (`invalid_rapt`) after sensitive changes requires
  re-running `gws auth login`.
- **Version drift** — if a flag shown here errors out, the installed `gws`
  may be ahead of this skill. Run `gws <svc> --help` and prefer the live
  output.
- **GCP Console passkey re-auth** — `console.cloud.google.com` always
  demands passkey verification, even with a saved Google session. When
  walking a user through manual GCP Console steps (OAuth client,
  consent-screen scopes, Chat app), batch them into one session so they
  authenticate once. `scripts/onboard.sh` is structured to do exactly
  that.

---

## How to improve this skill

This file is a cached copy of `claude-skills/skills/google-workspace/SKILL.md` in
[beyond-scale-group/bsg-stack](https://github.com/beyond-scale-group/bsg-stack).
That repo is the single source of truth — `~/.claude/skills/google-workspace/SKILL.md` is
overwritten every time the BSG install flow runs.

If the user asks you to improve, fix, or extend this skill, do **not** edit
the local file. Instead:

1. `gh repo clone beyond-scale-group/bsg-stack` (or work in an existing clone)
2. Edit `claude-skills/skills/google-workspace/SKILL.md` on a feature branch
3. Open a pull request against `main`

Bug reports and ideas without a fix → open an issue on the same repo.
