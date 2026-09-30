---
name: google-workspace
description: >-
  Google Workspace via the `gog` CLI (gogcli >= 0.42, github.com/openclaw/gogcli)
  for Gmail, Calendar, Drive, Sheets, Slides, Docs, Tasks, Contacts/People,
  Chat, Meet and Forms, with a Discovery-backed raw-API escape hatch
  (`gog api call`) and native multi-account. **This skill should be used
  proactively**: invoke it automatically whenever the conversation involves
  any Google Workspace action — do NOT run `gog` commands directly without
  going through this skill first. Use whenever the user works with Google
  Workspace from their own account — send/read/triage email, list/schedule/
  search calendar events, search/upload/share Drive files, read/append
  Sheets, create Slides, manage Tasks or Contacts, post in Chat, fetch Meet
  records, read/write Forms, or build a standup / meeting-prep / weekly
  digest from Gmail + Calendar + Tasks. Triggers include "send an email",
  "check my inbox", "triage gmail", "what's on my calendar", "next meeting",
  "find a Drive file", "upload to Drive", "read this sheet", "post in Chat",
  "today's standup", "weekly digest", "envoyer un mail", "agenda du jour",
  "prochaine réunion", "Google Workspace", "créer un brouillon",
  "draft an email", "brouillon gmail", "envoie un mail". Not for Admin
  SDK / user provisioning beyond what `gog admin` exposes.
model: sonnet
---

# Google Workspace (`gog`)

## Mandatory: always invoke this skill — never bypass it

**This skill must be invoked for ANY Google Workspace interaction.** Do not
run `gog` commands directly, even if you know the syntax. The skill handles
preflight checks (auth, version), picks the right script or command, applies
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

**Common mistake to avoid:** seeing that `gog` commands are documented in
this skill, then running them directly without invoking the skill. The skill
exists to orchestrate — not just to document. When in doubt, invoke.

---

`gog` is a Google Workspace CLI with curated, human-readable commands for
the common 90% of tasks, `--json` / `--plain` output for scripts, layered
safety flags, and a Discovery-backed `gog api call` for everything else.

Install: `brew install openclaw/tap/gogcli` (**>= 0.42.0** — the scripts
refuse older versions). Upgrade with `brew upgrade openclaw/tap/gogcli`.
The CLI moves fast — **never assume memorized flags**, verify with
`gog <group> --help`, `gog help <command>` or `gog schema --json` before
scripting.

## First-time setup → `scripts/onboard.sh`

If the user has never run `gog` on this machine — no binary, no OAuth
client, no consent-screen scopes registered, no Chat app — point them at
the orchestrator:

```bash
bash scripts/onboard.sh
```

It walks 7 idempotent steps (prereqs → enable APIs → OAuth client →
consent-screen scopes → Chat app → login → smoke tests). Steps that
require GCP Console interaction print the exact URL + checklist and
pause. Re-run a single step with `--step <name>` (`prereqs`, `apis`,
`oauth`, `scopes`, `chat-app`, `login`, `smoke`). `gog auth setup` can
also prepare the GCP project/APIs and install the OAuth client for you.

⚠ **GCP Console always demands passkey re-authentication**, even with a
saved browser session. Plan to authenticate once and run the manual
steps back-to-back so the session covers them all.

Browser automation for the GCP Console steps is available via the
`/browser` skill (`scripts/login-google.sh` for Google auth,
`scripts/with-profile.sh` for profile-based replay).

## Daily health check → `scripts/doctor.sh`

For sessions where `gog` is already configured, the doctor is the
fast read-only check:

```bash
bash scripts/doctor.sh           # full report
bash scripts/doctor.sh --quiet   # exit codes only, silent on green
```

Exits `0` (healthy), `1` (warnings — e.g. outdated version), or `2` (auth
or service failing). It verifies the refresh token (`gog auth doctor
--check`), audits which services the active account has granted, and
auto-repairs missing services by re-running `auth-login.sh` — only
escalating to manual if the scope is missing from the consent-screen
registration.

## Multi-account → native `gog` accounts

`gog` keeps several accounts (and several OAuth clients) side by side in
the OS keyring — no profile directories to swap. Add accounts once, then
pick one per command:

```bash
# Authorize an account (BSG service set; opens the browser once):
bash scripts/auth-login.sh you@company.com
bash scripts/auth-login.sh client@acme.com --readonly

# Inspect:
gog auth list --check          # accounts, granted services, token validity
gog auth status                # default account, client, keyring backend

# Friendly names, then use them:
gog auth alias set work you@company.com
gog --account work gmail search 'is:unread'

# Or pin one for the shell / session:
export GOG_ACCOUNT=work

# A second OAuth client (another GCP project) per account:
gog auth credentials set ~/Downloads/client_secret_other.json --client other
gog --client other --account you@other.com drive ls
```

Precedence is `--account` > `GOG_ACCOUNT` > gog's default account. Each
account carries **its own** tokens and granted services. `doctor.sh` and
`signature-audit.sh` run against whichever account is active — set
`GOG_ACCOUNT` explicitly and name the account in any human-facing report.

## Gmail audit → aliases & signatures

The skill ships three companion scripts that close the loop on the most
common per-account hygiene gap: aliases that don't have an HTML
signature, or where the signature lives only inside Gmail's web composer
and was never copied into the sendAs settings.

| Script | Purpose | Mutates? |
|---|---|---|
| `scripts/signature-audit.sh`   | List every sendAs alias + signature status | no |
| `scripts/signature-extract.sh` | Pull the HTML signature out of a recent sent email | no |
| `scripts/signature-set.sh`     | Update the signature on a sendAs alias (`gog gmail settings sendas update`) | **yes** |
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
confirmation before updating. Pass `--dry-run` to print the gog command
without calling Google, or `--yes` to skip the prompt in scripted
flows.

> **Why the user must send at least one email from each alias first.**
> `signature-extract.sh` reads the gmail web composer's
> `<div class="gmail_signature">` wrapper out of recent sent
> messages — only present on emails sent from the Gmail web UI (or
> mobile app). API-sent messages (including those from `gog gmail
> send`) don't carry that wrapper. If extract fails, ask the user to
> compose & send one email from each alias in Gmail web first, then
> re-run.

## Markdown email → drafted/sent → with alias signature

When the user wants to "turn this markdown into a real email", route to
`scripts/email-md-send.sh`. It composes `email-from-md.sh` (markdown
→ Gmail-ready HTML with table/blockquote inline CSS + alias signature
auto-appended) with `gog gmail send` / `gog gmail drafts create`, validating the alias
along the way:

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
5. Passes `--reply-to` straight through — both `gog gmail send` and
   `drafts create` support the header natively

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

Before issuing any `gog` command, run these checks once per session.
They are cheap and catch the common failure modes up front:

```bash
source scripts/_gog.sh
gog_require            # binary present and >= 0.42 (exit 3 otherwise)
gog_auth_ok || bash scripts/auth-login.sh "$(gog_account)"   # refresh token usable?
# or the full report:
gog auth doctor --check --json --no-input
```

If any check fails, surface it to the user **before** attempting the task:

- **Binary missing / too old** → `brew install openclaw/tap/gogcli` or
  `brew upgrade openclaw/tap/gogcli`.
- **Outdated but >= 0.42** → warn, continue; if a flag behaves
  unexpectedly, re-check `gog <group> --help` for the installed version.
- **Auth invalid / exit code 4 / `invalid_grant` / `invalid_rapt`** →
  run **[`scripts/auth-login.sh`](scripts/auth-login.sh)**` <email>`. It wraps
  `gog auth add`, requests the BSG service set (gmail, calendar, drive,
  docs, sheets, slides, contacts, tasks, chat, forms, meet, people) with
  `--force-consent`, verifies the token, and lists which services Google
  actually granted (the consent screen lets the user untick some).

  ⚠ Even a full grant does **not** fix:
    - `403 Caller does not have required permission to use project …`
      → that's a **GCP IAM** problem; see the "403 on Drive/Tasks/Chat/People"
      section below.
    - `404 Google Chat app not found` on `gog chat *`
      → Chat needs the GCP project to have a registered Chat app
      configuration; see the "Chat API" section below or run
      `bash scripts/onboard.sh --step chat-app`.

  Override when you want narrower or wider access:
  ```
  bash scripts/auth-login.sh you@x.com --readonly
  bash scripts/auth-login.sh you@x.com --services gmail,calendar,drive
  bash scripts/auth-login.sh you@x.com --gmail-scope send      # least privilege: send only
  bash scripts/auth-login.sh you@x.com --manual                # headless: paste the redirect URL
  ```
  **Always prefer this helper over bare `gog auth add`** — it verifies
  success and reports dropped services.

### Stay current with the tool's shape

`gog` adds services and flags often. When in doubt, **prefer discovery
over memory** — in this order:

1. **Live help from the installed binary** (always right for *this* machine):
   ```bash
   gog --help                          # top-level groups
   gog <group> --help                  # subcommands
   gog help <group> <command>          # flags for one command
   gog schema --json                   # whole command tree, flags, exit codes
   gog schema gmail search --json      # one command
   gog api list                        # Google APIs reachable through Discovery
   gog api describe gmail v1           # methods of one API
   ```

2. **Context7 / upstream docs** for anything newer than the installed
   binary: the repo is `openclaw/gogcli` (docs under `docs/`, generated
   command reference under `docs/commands/`). Use the
   `mcp__context7__resolve-library-id` tool to find it, then
   `query-docs` with a specific question. Call it whenever a command errors
   with "unknown flag", the user asks about a feature not documented here,
   or the installed version is behind the latest release.

3. **This skill's reference files** — stable baseline patterns, but may
   lag behind the upstream CLI. Treat as the starting point, not the
   source of truth.

This skill targets gog **0.42**. If the installed version is newer, trust
the live `--help` output over this document and mention any drift to the
user.

## Decision tree

```
First-time setup?  → bash scripts/onboard.sh         §First-time setup
Health check?      → bash scripts/doctor.sh          §Daily health check
Another account?   → gog auth add / --account        §Multi-account
Audit aliases?     → bash scripts/signature-audit.sh §Gmail audit
Set a signature?   → bash scripts/signature-set.sh   §Gmail audit
Markdown → email?  → bash scripts/email-md-send.sh   §Markdown email
CRM email asset?   → bash scripts/email-md-send.sh   §Markdown email
  (any .md in crm/*/assets/ with De:/À:/Objet: frontmatter)
Common task?       → first-class gog command         §Fast path
Cross-service?     → recipe in references/workflows.md
Raw API call?      → gog api call <api> <ver> <method>  §Raw API
Unknown command?   → gog schema --json | gog help <cmd>
```

Default to first-class commands before `gog api call`. They handle the
tedious encoding (RFC 2822 for Gmail, RFC 3339 for Calendar, A1 for
Sheets, multipart for Drive, space resolution for Chat).

## Fast path — first-class commands

Cross-service recipes (triage, standup, meeting prep, weekly digest,
email → task, file announce) are in
[references/workflows.md](references/workflows.md).

| Service | Start with |
|---|---|
| Gmail | `gog gmail search`, `messages search --include-body`, `get`, `thread get`, `send`, `drafts create`, `labels`, `settings sendas` |
| Calendar | `gog calendar events --today\|--tomorrow\|--week\|--days N`, `create`, `update`, `freebusy`, `respond` |
| Drive | `gog drive ls`, `search`, `download`, `upload`, `mkdir`, `share`, `permissions` |
| Sheets | `gog sheets get`, `update`, `append`, `clear`, `create`, `export` |
| Docs / Slides / Forms | `gog docs cat\|info\|export`, `gog slides info\|export`, `gog forms get\|create\|responses list` |
| Tasks / Contacts | `gog tasks lists list`, `tasks list <listId>`, `tasks add`, `gog contacts search`, `people me` |
| Chat / Meet | `gog chat spaces list`, `chat messages send`, `gog meet create\|get\|history` |

Quick taste:

```bash
gog gmail search 'is:unread newer_than:7d' --max 10
gog calendar events --today
gog calendar create primary --summary 'Review' \
  --from '2026-04-17T10:00:00+02:00' --to '2026-04-17T10:30:00+02:00' \
  --attendees alice@x.com --with-meet
gog drive upload ./report.pdf --parent FOLDER_ID --name 'Q1 Report.pdf'
gog sheets get $ID 'Sheet1!A1:D10' --plain
gog sheets append $ID 'Sheet1!A1' --values-json '[["Alice",100,true]]'
gog chat messages send spaces/AAAAxxxx --text 'Deploy done ✅'
```

## Raw API — everything else

Two escape hatches, both returning Google's canonical JSON:

```bash
# Any method of any Discovery API (writes need --allow-write --force):
gog api describe gmail v1                          # list methods
gog api call gmail v1 users.messages.list \
  --params '{"userId":"me","q":"is:unread newer_than:7d","maxResults":10}' --json
gog api call drive v3 files.list \
  --params '{"q":"mimeType=\"application/pdf\" and trashed=false","pageSize":20,"fields":"files(id,name,modifiedTime)"}' --json
gog api call sheets v4 spreadsheets.values.get \
  --params '{"spreadsheetId":"ID","range":"Sheet1!A1:D10"}' --json

# Lossless dump of one object (Gmail message, Drive file, Doc, Sheet, event…):
gog gmail raw <messageId> --format full --json
gog docs raw <docId> --all-tabs --json
```

Preview any mutation with `--dry-run` first. See
[references/raw-api.md](references/raw-api.md) for pagination, field masks,
`--select` / `--results-only`, exit codes and the safety flags.

## Service-specific knowledge

Load only the file for the service being used:

- [references/gmail.md](references/gmail.md) — search operator cheat sheet, labels, threads, attachments
- [references/calendar.md](references/calendar.md) — RFC3339 time formats, recurrence, free/busy, calendar IDs vs names
- [references/drive.md](references/drive.md) — Drive query language, MIME types, sharing/permissions, shared drives
- [references/sheets.md](references/sheets.md) — A1 notation, `valueInputOption`, batchUpdate patterns
- [references/workflows.md](references/workflows.md) — triage, standup, meeting prep, weekly digest and other multi-command workflows
- [references/recipes.md](references/recipes.md) — cross-service multi-step recipes

For Slides, Docs, Tasks, People, Chat, Meet, Forms, Classroom:
discover via `gog <group> --help`, `gog help <group> <cmd>` and
`gog api describe`.

## Agent-friendly conventions

- **Send HTML email** — pass the body as HTML (`--body-html` /
  `--body-html-file -`; `--body` alone is plain text). HTML renders
  clickable links, inline images, and proper formatting.
- **Auto-append the signature on direct sends/drafts** — Gmail's web
  composer auto-adds the account signature; the API does **not**.
  `gog gmail send` can do it for you: `--signature` (active send-as),
  `--signature-from <alias>` or `--signature-file`. `drafts create` has no
  such flag, so for drafts (or any HTML you compose yourself — i.e. *not*
  going through `email-md-send.sh`, which already appends it) fetch the
  default sendAs signature and append it after the body:

  ```bash
  SIG=$(gog api call gmail v1 users.settings.sendAs.list --params '{"userId":"me"}' --json \
    | jq -r '.sendAs[] | select(.isDefault==true) | .signature // empty')
  BODY='<p>Hi Alice!</p>'
  [ -n "$SIG" ] && BODY="${BODY}<br><br>${SIG}"
  gog gmail drafts create --to alice@x.com --subject 'Ping' --body-html "$BODY"
  ```

  Rules:
  - Skip silently when the signature is empty/`null` (no separator added).
  - Fetch once per session and reuse — it doesn't change mid-task.
  - Honour an explicit **`--no-signature`** intent from the user (e.g.
    "send without signature"): skip the fetch/append entirely. Same
    opt-out keyword as `email-md-send.sh --no-signature`.
  - The markdown pipeline (`email-md-send.sh` / `email-from-md.sh`)
    already does this — do **not** double-append when routing through it.
- **`--dry-run`** validates the request locally without calling Google. Use
  it to verify shape before any mutating call.
- **Output**: `--json` for parsing (`--results-only` unwraps the primary
  result, `--select a,b.c` projects fields); `--plain` for stable TSV;
  default is human-readable. Prompts and progress go to stderr, data to
  stdout. Use `--no-input` in scripts so nothing blocks on a prompt.
- **Untrusted content**: add `--wrap-untrusted` when fetched mail/doc text
  will be pasted into an LLM context.
- **Exit codes** (branch on `$?`, not on error text):
  `0` ok · `1` error · `2` usage · `3` empty results · `4` auth required ·
  `5` not found · `6` permission denied · `7` rate limited · `8` retryable ·
  `10` config missing · `11` orphaned comment · `130` cancelled.
- **Environment**: `GOG_ACCOUNT` (default account/alias), `GOG_CLIENT`,
  `GOG_JSON`, `GOG_PLAIN`, `GOG_READONLY=1`, `GOG_ENABLE_COMMANDS`,
  `GOG_KEYRING_BACKEND` / `GOG_KEYRING_PASSWORD` (headless file keyring),
  `GOG_HOME` (config root). Scripts also read `GOG_BIN` to swap the binary
  and `GOG_PROJECT_ID` / `GOG_USER_EMAIL` (`fix-iam-403.sh`).

## Safety rules

Confirm with the user **before** any command that:

- **Sends** — `gog gmail send`, `drafts send`, `gog chat messages send`, any
  `gog api call … messages.send` / `spaces.messages.create`
- **Creates calendar events** with `--attendees` (invitations go out
  immediately; `--send-updates none` suppresses them)
- **Writes to Sheets/Docs/Slides** — `sheets update|append|clear`,
  `docs` / `slides` edit commands, any `batchUpdate`
- **Modifies Drive permissions** — `drive share|unshare|permissions`,
  shared-drive moves
- **Deletes anything** — `drive delete`, `gmail batch delete`,
  `calendar delete`, `tasks delete`

Everything else (read, list, search, export, `--dry-run`) proceeds directly.

Runtime guards when the task is read-only or the content is untrusted:
`--readonly` (blocks every mutating API request), `--gmail-no-send`,
`--enable-commands-exact gmail.search,gmail.get`. When uncertain, run with
`--dry-run` first and show the output before executing for real.

## Chat API: "Google Chat app not found"

Symptom: `gog chat spaces list` (and most `chat.*` endpoints) return
`403 insufficient authentication scopes`, but your token clearly has
`chat.spaces`. A direct curl reveals the real error:
`404 Google Chat app not found`.

Cause: the Chat API requires the GCP project to have a **registered Chat
app configuration** (name, description, state) before any endpoint will
respond — even for pure user-context reads. Unlike Drive/Calendar/etc.
which work with just the API enabled, Chat needs the app registered. (Chat
also needs a Google Workspace account — consumer accounts can't use it.)

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

Symptom: after a clean `gog auth add`, some services still fail with
`403 Request had insufficient authentication scopes` (gog exit code 6),
and `gog auth list --json` shows fewer services than you requested.

Cause: Google silently drops any scope in the OAuth URL that **isn't
registered on the project's consent screen**. The user can't tick a
scope they're not being shown.

Fix (one-time, manual — GCP Console):

1. Open https://console.cloud.google.com/apis/credentials/consent?project=<PROJECT_ID>
2. Edit the app → Scopes → "Add or Remove Scopes"
3. Paste the missing scopes (`bash scripts/onboard.sh --step scopes` prints
   the full list; `gog auth services` shows what each service needs) and
   check each
4. Save & Continue
5. Re-run `bash scripts/auth-login.sh <email>` and tick every checkbox on
   the consent screen

`auth-login.sh` lists the granted services after login and warns about
the ones that were dropped.

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
re-authing will **not** help.

Three fixes — pick one:

**A. Run the bundled IAM helper** (fastest if you own the project):
```bash
bash scripts/fix-iam-403.sh              # detect project + user, grant role, verify
bash scripts/fix-iam-403.sh --enable-apis  # also `gcloud services enable` the APIs
```
The helper derives the project from gog's stored OAuth client (the
`client_id` prefix is the project number), fetches your email via the
Gmail profile, ensures `gcloud` is authenticated, applies
`roles/serviceusage.serviceUsageConsumer`, waits for propagation, and
verifies with a Drive probe. Overrides: `GOG_PROJECT_ID=…` /
`GOG_USER_EMAIL=…`.

Equivalent raw command if you prefer to run gcloud yourself:
```bash
gcloud projects add-iam-policy-binding <PROJECT_ID> \
  --member=user:<your-email> \
  --role=roles/serviceusage.serviceUsageConsumer
```

**B. Bill a different GCP project you own** (cleanest, avoids touching
shared projects):
```bash
export GOG_QUOTA_PROJECT=<your-own-project-id>     # or --quota-project
# Add to ~/.zshrc.user to persist across shells
```
No re-auth required — gog sends `X-Goog-User-Project` with every request.

**C. Run `gog auth setup`** to let gog prepare a fresh GCP project (APIs
+ OAuth client) for you. Requires `gcloud` installed + logged in. This
also replaces the OAuth client, so accounts must be re-authorized.

Find the current project number with
`jq -r '.client_id | split("-")[0]' "$(gog auth status --json | jq -r .account.credentials_path)"`.

## Common pitfalls

- **Attachments**: `gog gmail send --attach FILE` (repeatable) — no raw
  MIME needed. To send an exact RFC 822 message use `--raw-file`.
- **Meet links**: `gog calendar create … --with-meet` adds conferencing.
- **Sheets ranges need quoting** when sheet names contain spaces:
  `gog sheets get $ID "'Sales Data'!A1:C10"`.
- **Drive search**: `gog drive search "text"` is full-text; pass Drive query
  language with `gog drive ls --query "..."`. See references/drive.md.
- **Chat space names** look like `spaces/AAAAxxxx`. Find them with
  `gog chat spaces list`.
- **Services not authorized** — `tasks`, `chat`, `forms`, `meet`, `slides`
  need to be part of the account's grant (`gog auth list`); re-run
  `auth-login.sh` to add them (existing services are kept with
  `--force-consent`).
- **Token invalidation** (`invalid_grant` / `invalid_rapt`, exit code 4)
  after sensitive account changes requires re-running `auth-login.sh`.
- **Version drift** — if a flag shown here errors out, the installed `gog`
  may differ from 0.42. Run `gog help <cmd>` and prefer the live output.
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
