---
name: google-workspace
description: >-
  Official Google Workspace CLI (`gws` from github.com/googleworkspace/cli)
  for Gmail, Calendar, Drive, Sheets, Slides, Tasks, People, Chat, Meet,
  Forms, Keep, Classroom, plus cross-service workflow helpers. **This skill
  should be used proactively**: invoke it automatically whenever the
  conversation involves any Google Workspace action — do NOT run `gws`
  commands directly without going through this skill first. Use whenever
  the user works with Google Workspace from their own account — send/read/
  triage email, list/schedule/search calendar events, search/upload/share
  Drive files, read/append Sheets, create Slides, manage Tasks or Contacts,
  post in Chat, fetch Meet records, read/write Forms, or run
  `+standup-report`, `+meeting-prep`, `+email-to-task`, `+weekly-digest`,
  `+file-announce`. Triggers include "send an email", "check my inbox",
  "triage gmail", "what's on my calendar", "next meeting", "find a Drive
  file", "upload to Drive", "read this sheet", "post in Chat", "today's
  standup", "weekly digest", "envoyer un mail", "agenda du jour",
  "prochaine réunion", "Google Workspace", "créer un brouillon",
  "draft an email", "brouillon gmail", "envoie un mail". Not for Admin
  SDK / user provisioning — use the `workspace-admin` skill instead.
model: sonnet
---

# Google Workspace (`gws`)

## Mandatory: always invoke this skill — never bypass it

**This skill must be invoked for ANY Google Workspace interaction.** Do not
run `gws` commands directly, even if you know the syntax. The skill handles
preflight checks (auth, version), picks the right script or helper, applies
safety rules (confirm before send), and uses the correct alias + signature.

**Auto-invoke when the conversation contains any of these intents:**
- Sending, drafting, reading, triaging, replying to, or forwarding email
- Creating, reading, or managing calendar events
- Uploading, searching, or sharing Drive files
- Reading or writing Sheets, Docs, Slides
- Posting in Chat, managing Tasks or Contacts
- Any mention of Gmail, Google Calendar, Google Drive, Google Sheets, etc.
- Markdown files in `assets/` that look like email drafts (frontmatter with
  `De:`, `À:`, `Objet:` or `From:`, `To:`, `Subject:`)

**Common mistake to avoid:** seeing that `gws` commands are documented in
this skill, then running them directly without invoking the skill. The skill
exists to orchestrate — not just to document. When in doubt, invoke.

---

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

Browser automation for the GCP Console steps is available via the
`/browser` skill (`scripts/login-google.sh` for Google auth,
`scripts/with-profile.sh` for profile-based replay).

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

## Multi-account → `scripts/gws-switch.sh`

`gws` only authenticates one account at a time (credentials live under
`$GOOGLE_WORKSPACE_CLI_CONFIG_DIR`, default `~/.config/gws`). For
agents juggling a personal account + several client accounts, the switch
script wraps a per-profile config-dir pattern so toggling between them
is a single command — no re-auth, no browser re-consent.

```bash
# Create a profile (one-time browser consent, scoped to its own dir):
bash scripts/gws-switch.sh init prizoners
bash scripts/gws-switch.sh init client-acme --readonly

# Inspect:
bash scripts/gws-switch.sh list      # PROFILE | EMAIL | DIR
bash scripts/gws-switch.sh whoami    # current profile + bound email

# Activate in the current shell (needs eval because env exports don't
# survive a child bash):
eval "$(bash scripts/gws-switch.sh use prizoners)"
eval "$(bash scripts/gws-switch.sh use default)"

# Cleaner UX — install the shell function once, then `gws-switch X`:
bash scripts/gws-switch.sh install >> ~/.zshrc.user
source ~/.zshrc.user
gws-switch prizoners                 # → active
gws-switch default                   # → back to ~/.config/gws
gws-switch list

# Remove a profile when the engagement ends:
bash scripts/gws-switch.sh remove client-acme --yes
```

After `gws-switch.sh install`, every subsequent terminal can toggle
between accounts with a single word. Token caches stay alive across
switches — only the *first* auth on a profile requires the browser.

⚠ Each profile carries its **own** OAuth tokens and scope set. Running
`doctor.sh` or `signature-audit.sh` operates against whichever profile
is active in the current shell — be explicit about which account you're
auditing in any human-facing report.

## Gmail audit → aliases & signatures

The skill ships three companion scripts that close the loop on the most
common per-account hygiene gap: aliases that don't have an HTML
signature, or where the signature lives only inside Gmail's web composer
and was never copied into the sendAs settings.

| Script | Purpose | Mutates? |
|---|---|---|
| `scripts/signature-audit.sh`   | List every sendAs alias + signature status | no |
| `scripts/signature-extract.sh` | Pull the HTML signature out of a recent sent email | no |
| `scripts/signature-set.sh`     | Patch the signature on a sendAs alias | **yes** |
| `scripts/email-md-send.sh`     | Markdown → styled HTML body + alias signature → draft/send | yes |

Run the audit first (read-only, never modifies anything):

```bash
bash scripts/signature-audit.sh                 # table summary
bash scripts/signature-audit.sh --format json   # machine-readable
bash scripts/signature-audit.sh --alias me@x.com  # narrow to one alias
```

The audit reports, per alias: `isPrimary`, `isDefault`, `displayName`,
`replyToAddress`, `verificationStatus`, signature length, whether it's
HTML or plain text, and a list of warnings (`signature_missing`,
`plain_text_only`, `empty_after_strip`,
`primary_missing_display_name`). Exits `1` when any alias is missing a
signature or carries plain text only — wire into a hook to surface
drift over time.

When the audit flags a missing or weak signature on an alias, two paths
to fix it:

```bash
# Path 1 — preview & write inline:
bash scripts/signature-set.sh --alias me@x.com \
  --html '<p><strong>Jane Doe</strong><br>CEO · <a href="https://x.com">x.com</a></p>'

# Path 2 — pull the HTML from a recent sent email and apply it:
bash scripts/signature-set.sh --alias me@x.com --from-latest-sent

# Cross-alias: copy a beautiful signature from one alias to another:
bash scripts/signature-extract.sh --alias me@old.com \
  | bash scripts/signature-set.sh --alias me@new.com --html-stdin
```

`signature-set.sh` always shows a text-only preview and asks for
confirmation before patching. Pass `--dry-run` to render the JSON body
without calling Google, or `--yes` to skip the prompt in scripted
flows.

> **Why the user must send at least one email from each alias first.**
> `signature-extract.sh` reads the gmail web composer's
> `<div class="gmail_signature">` wrapper out of recent sent
> messages — only present on emails sent from the Gmail web UI (or
> mobile app). API-sent messages (including those from `gws gmail
> +send`) don't carry that wrapper. If extract fails, ask the user to
> compose & send one email from each alias in Gmail web first, then
> re-run.

## Markdown email → drafted/sent → with alias signature

When the user wants to "turn this markdown into a real email", route to
`scripts/email-md-send.sh`. It composes `email-from-md.sh` (markdown
→ Gmail-ready HTML with table/blockquote inline CSS + alias signature
auto-appended) with `gws gmail +send`, validating the alias along the
way:

```bash
# Default: render to draft so the user can review in Gmail
bash scripts/email-md-send.sh \
  --markdown ./memo.md \
  --to alice@example.com \
  --subject 'Q2 recap' \
  --from me@bsg-holding.fr     # picks up the alias's HTML signature

# Actually deliver:
bash scripts/email-md-send.sh ... --send

# Multiple recipients + cc/bcc + reply-to:
bash scripts/email-md-send.sh ... \
  --to 'alice@x.com,bob@x.com' --cc carol@x.com \
  --bcc archives@x.com --reply-to support@x.com
```

The wrapper:
1. Validates `--from` is a configured sendAs alias (warns if not)
2. Warns when the alias has no signature (offers `signature-set.sh` hint)
3. Renders markdown → styled HTML via `email-from-md.sh`
4. Defaults to **`--draft`** for safety; only delivers when `--send` is
   explicitly passed (and asks for confirmation unless `--yes`)
5. Falls back to the raw API path automatically when `--reply-to` is set
   (the `+send` helper doesn't expose that header)

### Markdown elements that survive the pipeline

Pandoc renders the markdown source; `email-from-md.sh` then merges
inline CSS onto the tags Gmail strips styles from. The following
elements are explicitly tested in `tests/test_email_from_md.sh`:

| Element                                | HTML tag(s)        | Inline CSS? |
|----------------------------------------|--------------------|-------------|
| Headings                               | `<h1>`–`<h4>`      | yes (font sizes, margins) |
| Bold / italic / strikethrough          | `<strong>` / `<em>` / `<del>` | no (Gmail-default OK) |
| Inline code / fenced code blocks       | `<code>` / `<pre>` | yes (monospace + bg) |
| Links                                  | `<a href>`         | no (Gmail-default OK) |
| Horizontal rule                        | `<hr>`             | yes (subtle border) |
| Unordered / ordered / nested lists     | `<ul>` / `<ol>` / `<li>` | yes (margins, indent) |
| Blockquotes                            | `<blockquote>`     | yes (left border, bg) |
| Tables                                 | `<table>` / `<th>` / `<td>` | yes (borders, padding) |
| Images                                 | `<img src>`        | yes (max-width:100%) |
| Definition lists                       | `<dl>` / `<dt>` / `<dd>` | yes (bold term, indent body) |
| Footnotes                              | `<sup>` + footer `<ol>` | inherits `<ol>` |
| Task lists `- [x]` / `- [ ]`           | Unicode `☑` / `☐` | yes (renders in every email client) |
| Fenced code blocks (syntax-highlighted) | `<pre>` + colored `<span>` | yes (GitHub-flavored colors per token) |
| Raw HTML inside markdown               | tag passes through | yes (any styled tag is recognized by name) |

The pipeline goes the extra distance for three Gmail-rendering pitfalls:

- **Syntax color in code blocks.** Pandoc's skylighting emits
  `<span class="kw">` (keyword), `<span class="st">` (string), `co`
  (comment), `fu` (function), `bu` (builtin), and ~25 more two-letter
  classes. Gmail strips the matching `<style>` block, so those classes
  render colorless. The script maps each class to a GitHub-flavored
  inline `style="color:#…"` so code blocks land in the inbox with full
  syntax color across every email client.

- **Task list checkboxes.** The raw `<input type="checkbox">` element
  Gmail renders inconsistently (or strips entirely) is rewritten to
  Unicode `☑` / `☐` glyphs in a monospace span — universal rendering,
  no JS, no client-specific quirks.

- **Raw HTML embedded in markdown.** When the author drops a `<table>`
  or `<blockquote>` directly into the markdown source, the same
  inline-CSS pass picks it up by tag name and styles it identically to
  pandoc-rendered output. No special handling required.

What **does not** survive cleanly:

- **`<figcaption>` wrappers** around images — stripped server-side
  before send; only the `<img>` is retained (Gmail otherwise renders
  the caption as orphan text underneath every image).
- **Non-standard HTML elements** the styling rules don't recognize —
  pandoc passes them through but they receive no inline CSS, so any
  `<style>` they rely on will be dropped by Gmail.

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
First-time setup?  → bash scripts/onboard.sh         §First-time setup
Health check?      → bash scripts/doctor.sh          §Daily health check
Switch accounts?   → bash scripts/gws-switch.sh      §Multi-account
Audit aliases?     → bash scripts/signature-audit.sh §Gmail audit
Set a signature?   → bash scripts/signature-set.sh   §Gmail audit
Markdown → email?  → bash scripts/email-md-send.sh   §Markdown email
CRM email asset?   → bash scripts/email-md-send.sh   §Markdown email
  (any .md in crm/*/assets/ with De:/À:/Objet: frontmatter)
Common task?       → use a +helper (prefer)          §Helpers
Raw API call?      → gws <svc> <res> <method>        §Raw API
Cross-service?     → gws workflow +<name>            §Workflow
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
gws gmail +send --to alice@x.com --subject 'Ping' \
  --body '<p>Hi Alice!</p>' --html
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

- **`--html` on all emails** — always pass `--html` to `gws gmail +send`
  (both send and `--draft`). Compose the `--body` as HTML (`<p>`, `<a>`,
  `<img>`, `<strong>`). HTML renders clickable links, inline images, and
  proper formatting. Plain text looks broken in modern email clients.
- **Auto-append the signature on direct `+send` / `+send --draft`** —
  Gmail's web composer auto-adds the account signature; a direct
  `gws gmail +send` does **not**. When you compose an HTML body yourself
  (i.e. *not* going through `email-md-send.sh`, which already appends it),
  fetch the default sendAs signature and append it after the body so
  drafts and sent mail match what the user sees in Gmail web:

  ```bash
  SIG=$(gws gmail users settings sendAs list --params '{"userId":"me"}' \
    | jq -r '.sendAs[] | select(.isDefault==true) | .signature // empty')
  BODY='<p>Hi Alice!</p>'
  [ -n "$SIG" ] && BODY="${BODY}<br><br>${SIG}"
  gws gmail +send --to alice@x.com --subject 'Ping' --body "$BODY" --html --draft
  ```

  Rules:
  - Only when `--html` is used; skip silently when the signature is
    empty/`null` (no separator added).
  - Fetch once per session and reuse — it doesn't change mid-task.
  - Honour an explicit **`--no-signature`** intent from the user (e.g.
    "send without signature"): skip the fetch/append entirely. Same
    opt-out keyword as `email-md-send.sh --no-signature`.
  - The markdown pipeline (`email-md-send.sh` / `email-from-md.sh`)
    already does this — do **not** double-append when routing through it.
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
