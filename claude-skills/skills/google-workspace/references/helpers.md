# `+` Helpers — full cheat sheet

Helpers prefixed with `+` are curated shortcuts for the 90% of common
tasks. Prefer them over raw API when a match exists — they handle
encoding, formatting, and resolution the raw API would require you to do
yourself.

All helpers accept `--format json|table|yaml|csv` and `--dry-run`.

## Gmail

### `gws gmail +send` — send an email

```
--to <EMAILS>          (required) comma-separated
--subject <SUBJECT>    (required)
--body <TEXT>          (required) HTML content (always use --html)
--cc <EMAILS>          comma-separated
--bcc <EMAILS>         comma-separated
--html                 treat --body as HTML (**always pass this flag**)
--draft                save as draft instead of sending
--from <EMAIL>         sender address (for send-as/alias)
```

**Always use `--html`** for all emails (send and draft). HTML gives proper
formatting: clickable links, inline images, paragraphs, bold/italic. Plain
text renders poorly in modern email clients. Structure the body with `<p>`,
`<a href>`, `<img>`, `<strong>` tags.

```bash
# Send (always --html)
gws gmail +send --to alice@x.com --subject 'Hi' \
  --body '<p>Hello Alice,</p><p>See the <a href="https://example.com">report</a>.</p>' --html

# Draft (always --html)
gws gmail +send --to alice@x.com --subject 'Review' \
  --body '<p>Please review the attached.</p><p><strong>Thanks!</strong></p>' --html --draft
```

No attachment support — use raw API (`gws gmail users messages send --json`)
with a base64-encoded RFC 2822 `raw` field.

### `gws gmail +triage` — unread inbox summary

```
--max <N>              default 20
--query <QUERY>        default "is:unread"
--labels               include label names
```

```bash
gws gmail +triage --max 10
gws gmail +triage --query 'from:boss@x.com newer_than:7d'
gws gmail +triage --format json | jq '.[] | {from,subject,date}'
```

### `gws gmail +reply` / `+reply-all`

Handles threading (In-Reply-To, References) automatically. Takes a message
ID and a body.

### `gws gmail +forward`

Forwards a message to new recipients, preserves original content.

### `gws gmail +watch` — streaming

Watches for new emails and streams them as NDJSON. Good for pipelines.

## Calendar

### `gws calendar +insert` — create an event

```
--summary <TEXT>       (required)
--start <TIME>         (required) RFC 3339, e.g. 2026-06-17T09:00:00-07:00
--end <TIME>           (required)
--calendar <ID>        default: primary
--location <TEXT>
--description <TEXT>
--attendee <EMAIL>     repeatable (each --attendee adds one)
```

```bash
gws calendar +insert --summary 'Standup' \
  --start '2026-06-17T09:00:00-07:00' \
  --end   '2026-06-17T09:30:00-07:00'

gws calendar +insert --summary 'Review' \
  --start '2026-06-17T14:00:00+02:00' --end '2026-06-17T15:00:00+02:00' \
  --attendee alice@x.com --attendee bob@x.com --location 'Paris HQ'
```

Recurring events or Meet conference links → use raw `events insert` with
`recurrence` / `conferenceData` + `conferenceDataVersion=1`.

### `gws calendar +agenda` — upcoming events

```
--today
--tomorrow
--week
--days <N>
--calendar <NAME>      filter by calendar name or ID
--timezone <TZ>        IANA tz, e.g. Europe/Paris
```

```bash
gws calendar +agenda --today --format table
gws calendar +agenda --week
gws calendar +agenda --days 3 --timezone Europe/Paris
```

## Drive

### `gws drive +upload` — upload a local file

```
<file>                 (positional) local path
--parent <ID>          destination folder ID
--name <NAME>          rename on upload
```

```bash
gws drive +upload ./report.pdf
gws drive +upload ./data.csv --parent FOLDER_ID --name 'Sales Data.csv'
```

Content type is auto-detected from extension. For non-standard types or
resumable upload behavior use raw `files create` with `--upload` +
`--upload-content-type`.

## Sheets

### `gws sheets +read` — read a range

```
--spreadsheet <ID>     (required)
--range <RANGE>        (required) A1 notation
```

```bash
gws sheets +read --spreadsheet ID --range 'Sheet1!A1:D10' --format csv
gws sheets +read --spreadsheet ID --range Sheet1      # whole sheet
```

### `gws sheets +append` — append rows

```
--spreadsheet <ID>     (required)
--values <CSV>         single-row shorthand
--json-values <JSON>   array of arrays for multi-row
```

```bash
gws sheets +append --spreadsheet ID --values 'Alice,100,true'
gws sheets +append --spreadsheet ID --json-values '[["Alice",100,true],["Bob",200,false]]'
```

## Chat

### `gws chat +send` — post a message

```
--space <NAME>         (required) e.g. spaces/AAAAxxxx
--text <TEXT>          (required) plain text
```

```bash
gws chat spaces list   # find the space name first
gws chat +send --space spaces/AAAAxxxx --text 'Deploy done ✅'
```

For cards / threaded replies / formatted blocks → raw
`spaces.messages.create` with `--json`.

## Workflow — cross-service

All read-only except `+email-to-task` and `+file-announce`.

### `gws workflow +standup-report`

Today's calendar agenda + open tasks, combined. Read-only.

### `gws workflow +meeting-prep`

Next upcoming event with attendees, description, linked docs. Read-only.

```
--calendar <ID>   default: primary
```

### `gws workflow +email-to-task` — write

Reads a Gmail message and creates a Tasks entry (subject → title,
snippet → notes). Confirm with the user first.

```
--message-id <ID>       (required)
--tasklist <ID>         default: @default
```

### `gws workflow +weekly-digest`

This week's agenda + unread email count. Read-only.

### `gws workflow +file-announce` — write

Posts a Chat message announcing a Drive file. Confirm with the user first.

```
--file-id <ID>    (required)
--space <SPACE>   (required) e.g. spaces/ABC123
--message <TEXT>  optional custom text
```
