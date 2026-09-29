# Workflows — task recipes with `gog`

`gog` has no `+helper` layer: every task below maps to first-class `gog`
commands (or a short recipe combining a few of them with `jq`). Prefer these
over `gog api call` when a match exists — they handle MIME encoding, threading,
timezones, and resolution for you.

Global flags worth knowing (details in [raw-api.md](raw-api.md)):

- `--json` (scripts) / `--plain` (stable TSV) / `--results-only` / `--select`
- `--dry-run` (`-n`) previews a mutation without executing it
- `--no-input` never prompts; `--force` (`-y`) skips destructive confirmations
- `-a <email>` picks the account when several are authenticated

> Upstream `gogcli` also ships optional agent workflow skills (install with
> `npx skills add https://github.com/openclaw/gogcli`): `gog-inbox-triage`,
> `gog-meeting-prep`, `gog-save-attachments`, `gog-drive-audit`,
> `gog-weekly-digest`, `gog-contacts-cleanup`. They complement the recipes below.

## Gmail

### Send an email — `gog gmail send`

```
--to <EMAILS>            comma-separated (required unless --reply-all)
--subject <SUBJECT>      required unless replying
--body <TEXT>            plain text
--body-file <PATH|->     plain text from file/stdin
--body-html <HTML>       HTML body
--body-html-file <PATH|->  HTML body from file/stdin
--cc / --bcc <EMAILS>    comma-separated
--attach <PATH>          repeatable
--from <EMAIL>           verified send-as alias
--signature              append the Gmail signature of the send-as address
--reply-to-message-id / --thread-id / --reply-all / --quote   reply mode
--raw-file <PATH|->      send an exact RFC822 message (no other compose flags)
```

**Always send HTML** (`--body-html` / `--body-html-file`): clickable links,
paragraphs, bold/italic. Structure with `<p>`, `<a href>`, `<img>`,
`<strong>`. `--body` alone yields plain text, which renders poorly.

```bash
# Send
gog gmail send --to alice@x.com --subject 'Hi' \
  --body-html '<p>Hello Alice,</p><p>See the <a href="https://example.com">report</a>.</p>'

# Attachment (native — no raw MIME needed)
gog gmail send --to alice@x.com --subject 'Report' \
  --body-html '<p>Attached.</p>' --attach ./report.pdf

# Draft instead of sending (same compose flags)
gog gmail drafts create --to alice@x.com --subject 'Review' \
  --body-html '<p>Please review.</p><p><strong>Thanks!</strong></p>'
gog gmail drafts send <draftId>        # later, once approved
```

Preview with `--dry-run`; block sends entirely in agent sessions with the
global `--gmail-no-send`.

### Unread inbox summary (triage) — `gog gmail search`

```
--max <N>          default 10
--all              fetch all pages
--page <TOKEN>     page token
--fail-empty       exit 3 when nothing matches
--count            report total matches
```

`gmail search` returns **threads**; `gog gmail messages search` returns
**messages** (add `--include-body`, `--include-attachments`).

```bash
gog gmail search 'is:unread' --max 20
gog gmail search 'from:boss@x.com newer_than:7d' --max 10
gog gmail search 'is:unread' --max 10 --json --results-only \
  | jq '.[] | {from,subject,date}'          # check keys on a first --json run
gog gmail get <messageId> --sanitize-content --json   # body for an agent
```

Labels: `is:unread label:important`, `category:promotions`, … all Gmail search
operators work in the query string.

### Reply / reply-all — `gog gmail reply`

Threading (In-Reply-To, References) is handled automatically. Takes a message
ID and a body; the original is quoted unless `--no-quote`.

```bash
gog gmail reply <messageId> --body-html '<p>Thanks, done.</p>'
gog gmail send --reply-all --reply-to-message-id <messageId> \
  --body-html '<p>Thanks all.</p>'                       # reply-all
gog gmail drafts reply <messageId> --body-html '<p>Draft reply</p>'   # save only
gog gmail drafts reply-all <messageId> --body-html '<p>Draft</p>'
```

### Forward — `gog gmail forward`

```bash
gog gmail forward <messageId> --to bob@x.com --note 'FYI, see below.'
gog gmail forward <messageId> --to bob@x.com --skip-attachments
```

### Watch for new mail — `gog gmail watch`

`gog` has no NDJSON stream. Real-time watching goes through Pub/Sub:
`gog gmail watch start|status|renew|stop` to manage the watch, then
`gog gmail watch serve` (push handler) or `gog gmail watch pull` (pull
consumer). Requires a Pub/Sub topic; see `gog gmail watch start --help`.
For a cheap poll instead, loop `gog gmail search 'is:unread newer_than:1h' --fail-empty`.

## Calendar

### Create an event — `gog calendar create`

```
<calendarId>            positional; `primary` for the main calendar
--summary <TEXT>
--from <RFC3339>        start (or date with --all-day)
--to <RFC3339>          end
--location <TEXT>
--description <TEXT>
--attendees <EMAILS>    comma-separated (modifiers: ;optional ;resource)
--with-meet             add a Google Meet link
--rrule 'RRULE:...'     recurrence (repeatable)
--send-updates all|externalOnly|none   default none
--reminder popup:30m    repeatable
```

```bash
gog calendar create primary --summary 'Standup' \
  --from '2026-06-17T09:00:00-07:00' --to '2026-06-17T09:30:00-07:00'

gog calendar create primary --summary 'Review' \
  --from '2026-06-17T14:00:00+02:00' --to '2026-06-17T15:00:00+02:00' \
  --attendees alice@x.com,bob@x.com --location 'Paris HQ' \
  --with-meet --send-updates all

gog calendar create primary --summary 'Weekly sync' \
  --from '2026-06-17T10:00:00+02:00' --to '2026-06-17T10:30:00+02:00' \
  --rrule 'RRULE:FREQ=WEEKLY;BYDAY=WE'
```

Meet links and recurrence are native flags — no raw `conferenceData` needed.
Edit later with `gog calendar update primary <eventId> …`.

### Upcoming events (agenda) — `gog calendar events`

```
[<calendarId>]          default primary
--today | --tomorrow | --week
--days <N>              window length, from --from or today
--from / --to           RFC3339, date, or relative (now, today, monday)
--all                   events from all calendars
--cal <NAME|ID>         repeatable calendar filter
--timezone <TZ>         IANA tz, e.g. Europe/Paris
--max <N>               default 10
--all-pages / --page    pagination
```

```bash
gog calendar events --today
gog calendar events --week --max 50
gog calendar events --days 3 --timezone Europe/Paris
gog calendar events --today --all --sort start        # every calendar
```

## Drive

### Upload a local file — `gog drive upload`

```
<localPath>             positional
--parent <ID>           destination folder ID
--name <NAME>           rename on upload
--mime-type <MIME>      override MIME inference
--convert | --convert-to doc|sheet|slides   convert to native Google format
--replace <fileId>      replace content of an existing file (keeps sharing)
```

```bash
gog drive upload ./report.pdf
gog drive upload ./data.csv --parent FOLDER_ID --name 'Sales Data.csv'
gog drive upload ./data.csv --parent FOLDER_ID --convert-to sheet
```

Content type is inferred from the extension. Use `--dry-run` to preview.

## Sheets

### Read a range — `gog sheets get`

```bash
gog sheets get SHEET_ID 'Sheet1!A1:D10'
gog sheets get SHEET_ID 'Sheet1!A1:D10' --json
gog sheets get SHEET_ID 'Sheet1'                 # whole sheet
gog sheets get SHEET_ID 'Sheet1!A1:D10' --plain  # TSV, pipe to csvkit etc.
```

`--render FORMATTED_VALUE|UNFORMATTED_VALUE|FORMULA`,
`--dimension ROWS|COLUMNS`.

### Append rows — `gog sheets append`

Rows are comma-separated, cells are pipe-separated (`|`); or pass a JSON 2D
array with `--values-json`.

```bash
gog sheets append SHEET_ID 'Sheet1!A:C' 'Alice|100|true'
gog sheets append SHEET_ID 'Sheet1!A:C' 'Alice|100|true,Bob|200|false'
gog sheets append SHEET_ID 'Sheet1!A:C' \
  --values-json '[["Alice",100,true],["Bob",200,false]]'
```

`--input RAW|USER_ENTERED` (default `USER_ENTERED`, so formulas evaluate),
`--insert OVERWRITE|INSERT_ROWS`.

## Chat

### Post a message — `gog chat messages send`

```
<space>          positional, e.g. spaces/AAAAxxxx
--text <TEXT>    message text
--thread <NAME>  reply into spaces/.../threads/...
--attach <PATH>  attachment (repeatable)
```

```bash
gog chat spaces list                       # list spaces
gog chat spaces find 'Engineering'         # by display name
gog chat messages send spaces/AAAAxxxx --text 'Deploy done ✅'
```

Cards / formatted blocks → `gog api call chat v1 spaces.messages.create`
(see [raw-api.md](raw-api.md)). Chat may need extra scopes/auth: check
`gog auth services`.

## Cross-service workflows

There are no built-in `workflow +…` commands; compose them. Read-only unless
marked **write**. Larger variants live in [recipes.md](recipes.md).

### Standup report (agenda + open tasks) — read-only

```bash
echo '── Calendar (today) ──'; gog calendar events --today
echo '── Tasks ──';            gog tasks list @default
```

### Meeting prep (next event) — read-only

```bash
gog calendar events --from now --max 1 --json --results-only   # attendees, description, attachments
```

Then, per attendee, `gog gmail search "from:$EMAIL OR to:$EMAIL newer_than:14d"`
(full loop in [recipes.md](recipes.md)). Upstream skill: `gog-meeting-prep`.

### Email to task — **write**

Reads a Gmail message and creates a Task (subject → title, snippet → notes).
Confirm with the user first.

```bash
SUBJ=$(gog gmail get MSG_ID --format metadata --headers Subject --json \
  | jq -r '[.. | objects | select(.name? == "Subject") | .value][0]')
gog tasks add @default --title "$SUBJ" \
  --notes "https://mail.google.com/mail/u/0/#all/MSG_ID" --dry-run
```

Drop `--dry-run` once the user confirms. `@default` is the Google Tasks alias
for the primary list; otherwise take an ID from `gog tasks lists list`.
Adjust the `jq` path if the `--json` shape differs.

### Weekly digest — read-only

```bash
gog calendar events --week --max 50
gog gmail search 'is:unread' --count --max 1
```

Upstream skill: `gog-weekly-digest`.

### Announce a Drive file in Chat — **write**

Confirm with the user first.

```bash
URL=$(gog drive get FILE_ID --json | jq -r '.webViewLink')
gog chat messages send spaces/ABC123 --text "New file: $URL"
```
