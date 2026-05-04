# Gmail

Prefer `gws gmail +send / +triage / +reply / +reply-all / +forward / +watch`
for common tasks. Raw API for attachments, history watches, label
management, settings, filters, and anything requiring full RFC 2822 control.

## Search operator cheat sheet

Pass any of these as `--query` to `+triage`, or as `q` inside `--params`
for `gws gmail users messages list`.

```
from:alice@x.com            sender
to:me                       recipient
subject:"quarterly report"  subject phrase
"invoice number"            body phrase (quoted)
label:important             label name (lowercased, hyphens for spaces)
has:attachment              has any attachment
filename:pdf                attachment filename/extension
is:unread  is:read  is:starred  is:important
in:inbox   in:sent   in:trash   in:spam   in:anywhere
category:primary|social|promotions|updates|forums
newer_than:7d   older_than:3m     relative (s/m/h/d/w/m/y)
after:2026/01/01  before:2026/02/01  absolute (YYYY/MM/DD)
larger:5M   smaller:1M               size
list:dev@x.com              mailing list
-from:alice@x.com           negate (NOT)
{from:a OR from:b}          OR group
rfc822msgid:<id@host>       exact message-id
```

Combine freely: `from:boss@x.com is:unread newer_than:3d has:attachment`.

## Raw listing

```bash
# List unread messages from the last week
gws gmail users messages list --params '{
  "userId":"me",
  "q":"is:unread newer_than:7d",
  "maxResults":25,
  "fields":"messages(id,threadId)"
}'

# Paginate all
gws gmail users messages list --params '{"userId":"me","q":"from:boss@x.com","maxResults":100}' \
  --page-all --page-limit 5
```

## Fetch a full message

```bash
gws gmail users messages get --params '{"userId":"me","id":"MSG_ID","format":"full"}'

# Plain text only (decodes MIME parts on the server)
gws gmail users messages get --params '{"userId":"me","id":"MSG_ID","format":"full"}' \
  | jq -r '.payload.parts[]? | select(.mimeType=="text/plain") | .body.data' \
  | base64 --decode
```

`format` options: `minimal` · `full` · `raw` · `metadata`.

## Threads

```bash
# List threads
gws gmail users threads list --params '{"userId":"me","q":"label:important","maxResults":20}'

# Get a thread with all messages
gws gmail users threads get --params '{"userId":"me","id":"THREAD_ID","format":"full"}'
```

## Labels

```bash
# List labels
gws gmail users labels list --params '{"userId":"me"}'

# Create a label
gws gmail users labels create --params '{"userId":"me"}' \
  --json '{"name":"Follow-Up","labelListVisibility":"labelShow","messageListVisibility":"show"}'

# Apply / remove labels
gws gmail users messages modify --params '{"userId":"me","id":"MSG_ID"}' \
  --json '{"addLabelIds":["Label_123"],"removeLabelIds":["UNREAD"]}'

# Batch modify
gws gmail users messages batchModify --params '{"userId":"me"}' \
  --json '{"ids":["MSG1","MSG2"],"addLabelIds":["IMPORTANT"],"removeLabelIds":["UNREAD"]}'
```

## Send with attachment (raw path)

`+send` cannot attach. Build an RFC 2822 message, base64-url-encode it,
and POST:

```bash
# Build an RFC 2822 MIME with a single attachment (bash one-liner)
BOUNDARY="boundary_$(date +%s)"
{
  printf 'From: me@x.com\r\n'
  printf 'To: alice@x.com\r\n'
  printf 'Subject: Report attached\r\n'
  printf 'MIME-Version: 1.0\r\n'
  printf 'Content-Type: multipart/mixed; boundary="%s"\r\n\r\n' "$BOUNDARY"
  printf -- '--%s\r\nContent-Type: text/plain; charset=UTF-8\r\n\r\n' "$BOUNDARY"
  printf 'See attached.\r\n'
  printf -- '--%s\r\nContent-Type: application/pdf\r\nContent-Disposition: attachment; filename="report.pdf"\r\nContent-Transfer-Encoding: base64\r\n\r\n' "$BOUNDARY"
  base64 < ./report.pdf
  printf -- '\r\n--%s--\r\n' "$BOUNDARY"
} > /tmp/msg.eml

RAW=$(base64 < /tmp/msg.eml | tr -d '\n' | tr '+/' '-_' | tr -d '=')
gws gmail users messages send --params '{"userId":"me"}' --json "{\"raw\":\"$RAW\"}"
```

## Drafts

```bash
# Create draft (same RAW encoding as send)
gws gmail users drafts create --params '{"userId":"me"}' --json "{\"message\":{\"raw\":\"$RAW\"}}"

# Send a saved draft
gws gmail users drafts send --params '{"userId":"me"}' --json '{"id":"DRAFT_ID"}'
```

## History watch / push notifications

```bash
gws gmail users watch --params '{"userId":"me"}' \
  --json '{"topicName":"projects/PROJECT/topics/TOPIC","labelIds":["INBOX"]}'
gws gmail users stop  --params '{"userId":"me"}'
```

Push notifications go to Pub/Sub. For local polling use `gws gmail +watch`
which streams NDJSON of new messages as they arrive.

## Compose Gmail-ready HTML from markdown (`+email-from-md`)

Use `scripts/email-from-md.sh` to convert a markdown file into HTML
that renders correctly in Gmail web: tables get inline borders, blockquotes
get a left-border, and the sender's Gmail signature is auto-appended.

**Quick usage:**

```bash
# Generate HTML body, save to temp file
bash claude-skills/skills/google-workspace/scripts/email-from-md.sh \
  --markdown ./memo.md \
  --from me@example.com \
  > /tmp/body.html

# Pipe straight into gws +send as a draft
gws gmail +send \
  --to alice@example.com \
  --from me@example.com \
  --subject "Q2 recap" \
  --body "$(bash claude-skills/skills/google-workspace/scripts/email-from-md.sh \
              --markdown ./memo.md --from me@example.com)" \
  --html --draft
```

**Flags:**

| Flag | Required | Description |
|------|----------|-------------|
| `--markdown FILE` | yes | Path to the markdown source file |
| `--from ALIAS` | no | Gmail sendAs alias — used to fetch the matching signature |
| `--no-signature` | no | Skip signature injection (useful for tests / CI) |

**What it does:**

1. Converts markdown to HTML via `pandoc`
2. Inlines CSS on `<table>`, `<th>`, `<td>`, `<blockquote>` (Gmail strips
   stylesheet; inline is required for rendering)
3. Calls `gws gmail users settings sendAs list` to fetch the HTML signature
   for `--from`; appends it after the body. Skipped when `--no-signature`
   or `gws` is unavailable.

**Manual workaround** (if you need a one-liner without the script):

```bash
FROM="me@example.com"
SIG=$(gws gmail users settings sendAs list --params '{"userId":"me"}' \
  | jq -r ".sendAs[] | select(.sendAsEmail == \"$FROM\") | .signature")
pandoc -f markdown -t html --wrap=none body.md \
  | sed -E \
    -e 's|<table>|<table style="border-collapse:collapse;border:1px solid #ccc;margin:12px 0;font-family:Arial,sans-serif;font-size:13px;">|g' \
    -e 's|<th>|<th style="background:#f4f4f4;border:1px solid #ccc;padding:8px 10px;text-align:left;font-weight:600;">|g' \
    -e 's|<td>|<td style="border:1px solid #ccc;padding:8px 10px;vertical-align:top;">|g' \
  > /tmp/body.html
echo "$SIG" >> /tmp/body.html
gws gmail +send --to "$TO" --from "$FROM" --subject "$SUBJECT" \
  --body "$(cat /tmp/body.html)" --html --draft
```

## Cheap patterns

```bash
# Unread count
gws gmail users messages list --params '{"userId":"me","q":"is:unread","maxResults":1}' \
  | jq '.resultSizeEstimate'

# Archive a message
gws gmail users messages modify --params '{"userId":"me","id":"MSG_ID"}' \
  --json '{"removeLabelIds":["INBOX"]}'

# Trash / delete
gws gmail users messages trash  --params '{"userId":"me","id":"MSG_ID"}'
gws gmail users messages delete --params '{"userId":"me","id":"MSG_ID"}'   # permanent, needs extra scope
```
