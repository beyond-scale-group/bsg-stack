# Gmail

Prefer the first-class `gog gmail` commands (`search`, `messages search`,
`get`, `thread get`, `send`, `reply`, `forward`, `drafts`, `labels`, `archive`,
`trash`). Use `gog api call gmail v1 ...` for anything they do not cover
(filters by raw body, history, `batchModify` with arbitrary payloads), and
`gog gmail raw <id>` for a lossless message dump.

Global flags worth knowing: `--json` / `--plain`, `--results-only` (drop
envelope fields), `--select a,b.c` (pick fields), `--account <email|alias>`
(or `GOG_ACCOUNT`), `--dry-run`, `--no-input`, `--force`, `--readonly`,
`--gmail-no-send`. Exit codes: 0 ok, 2 usage, 3 empty results
(`--fail-empty`), 4 auth_required, 5 not_found, 6 permission_denied,
7 rate_limited, 8 retryable, 10 config.

## Search operator cheat sheet

Pass any of these as the `<query>` argument of `gog gmail search` (threads)
or `gog gmail messages search` (individual messages), or as `q` inside
`--params` for `gog api call gmail v1 users.messages.list`.

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

## Search / list

```bash
# Unread threads from the last week (default --max 10)
gog gmail search 'is:unread newer_than:7d' --max 25 --json

# Individual messages instead of threads, with bodies
gog gmail messages search 'from:boss@x.com' --max 100 --include-body --json

# Every page (or one page at a time with --page <token>)
gog gmail messages search 'from:boss@x.com' --all --json

# Script-friendly: exit code 3 when nothing matches
gog gmail search 'label:follow-up is:unread' --fail-empty --plain

# Raw Discovery call when you need exact API fields
gog api call gmail v1 users.messages.list \
  --params '{"userId":"me","q":"is:unread newer_than:7d","maxResults":25,"fields":"messages(id,threadId)"}' --json
```

## Fetch a full message

```bash
gog gmail get MSG_ID                       # --format full (default)
gog gmail get MSG_ID --format metadata --headers From,Subject,Date
gog gmail get MSG_ID --sanitize-content    # agent-friendly: strips active content

# Lossless API dump (Users.Messages.Get), then decode the text/plain part
gog gmail raw MSG_ID \
  | jq -r '.payload.parts[]? | select(.mimeType=="text/plain") | .body.data' \
  | tr '_-' '/+' | base64 --decode
```

`--format` options: `full` · `metadata` · `raw`.

Attachments:

```bash
gog gmail thread attachments THREAD_ID                      # list
gog gmail attachment MSG_ID ATTACHMENT_ID --out ./file.pdf  # download one
gog gmail thread get THREAD_ID --download --out-dir ./att   # all in a thread
```

## Threads

```bash
# List threads (search returns threads)
gog gmail search 'label:important' --max 20 --json

# Get a thread with all messages
gog gmail thread get THREAD_ID --json
gog gmail thread get THREAD_ID --full        # untruncated bodies

# Web URL of a thread
gog gmail url THREAD_ID
```

## Labels

```bash
# List labels / details with counts
gog gmail labels list --json
gog gmail labels get Follow-Up

# Create / rename / delete a label
gog gmail labels create "Follow-Up"
gog gmail labels rename "Follow-Up" "Follow-Up 2026"
gog gmail labels delete "Follow-Up 2026"

# Apply / remove labels on one message (names or IDs, comma-separated)
gog gmail messages modify MSG_ID --add Label_123 --remove UNREAD

# Batch modify several messages
gog gmail batch modify MSG1 MSG2 --add IMPORTANT --remove UNREAD

# Whole thread
gog gmail thread modify THREAD_ID --add "Follow-Up" --remove INBOX
```

`labelListVisibility` / `messageListVisibility` at creation time are not
exposed by `labels create`; use `gog api call gmail v1 users.labels.create
--allow-write --force --params '{"userId":"me"}' --body '{...}'` when you need
them, or `gog gmail labels style` for color/visibility afterwards.

## Send, reply, forward

```bash
gog gmail send --to alice@x.com --subject 'Ping' --body 'Hello'
gog gmail send --to alice@x.com --subject 'Ping' --body-html '<p>Hi <b>Alice</b></p>' --signature
gog gmail reply MSG_ID --body 'Thanks!'
gog gmail reply-all MSG_ID --body 'Thanks all' --quote
gog gmail forward MSG_ID --to bob@x.com
```

Preview any of them with `--dry-run`; `--gmail-no-send` blocks sending
entirely (useful for agent sessions that should only draft).

## Send with attachment

`--attach` is repeatable and `send` builds the MIME for you:

```bash
gog gmail send --to alice@x.com --from me@x.com \
  --subject 'Report attached' --body 'See attached.' \
  --attach ./report.pdf --attach ./data.csv
```

For full RFC 2822 control, hand-build the message and send it verbatim
with `--raw-file` (cannot be combined with compose flags; `-` reads stdin):

```bash
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

gog gmail send --raw-file /tmp/msg.eml
```

No base64url step: `gog` encodes the raw message itself.

## Drafts

```bash
# Create a draft (same compose flags as send, incl. --attach / --body-html)
gog gmail drafts create --to alice@x.com --subject 'Q2 recap' --body-html '<p>Hi</p>'
gog gmail drafts create --raw-file /tmp/msg.eml

# Draft a reply / reply-all / forward
gog gmail drafts reply MSG_ID --body 'Draft answer'

# Inspect, edit, send, delete
gog gmail drafts list --json
gog gmail drafts get DRAFT_ID
gog gmail drafts update DRAFT_ID --body 'New text'
gog gmail drafts send DRAFT_ID
gog gmail drafts delete DRAFT_ID     # permanent, drafts do not go to Trash
```

## History watch / push notifications

```bash
gog gmail settings watch start --topic projects/PROJECT/topics/TOPIC --label INBOX
gog gmail settings watch status
gog gmail settings watch renew
gog gmail settings watch stop
```

Push notifications go to Pub/Sub. For local handling, `gog gmail settings
watch serve` (push handler) or `watch pull` (pull consumer) run a listener,
and `--hook-url` forwards messages to a webhook. To poll changes yourself:

```bash
gog gmail history --since HISTORY_ID --all --json
```

## sendAs aliases & signatures

Gmail's "Send mail as" feature lets a single account send from multiple
verified addresses (custom domains, work aliases, etc.). Each alias has
its own `displayName`, `replyToAddress`, and `signature` — independent
of the primary login. `gog` exposes them as `gog gmail settings sendas ...`
(`list`, `get`, `create`, `update`, `verify`, `delete`); the raw API method
IDs are `users.settings.sendAs.*` (see `gog api describe gmail v1`).

### List every alias on the account

```bash
gog api call gmail v1 users.settings.sendAs.list --params '{"userId":"me"}' --json \
  | jq '.sendAs[] | {sendAsEmail, isPrimary, isDefault, displayName, verificationStatus, signature_len: (.signature // "" | length)}'
```

Returned fields per entry:

| Field | Meaning |
|---|---|
| `sendAsEmail`        | The "From:" address |
| `isPrimary`          | Read-only — true for the login address |
| `isDefault`          | True for the default "From:" (vacation auto-replies use this) |
| `displayName`        | Friendly name in the From header |
| `replyToAddress`     | Optional Reply-To (e.g. shared inbox) |
| `treatAsAlias`       | True for true aliases of the primary address |
| `verificationStatus` | `accepted` / `pending` for custom froms |
| `signature`          | HTML signature (Gmail sanitizes on save) |

### Get a single alias

```bash
gog gmail settings sendas get me@example.com --json
```

### Update an alias (signature, displayName, replyTo)

```bash
gog gmail settings sendas update me@example.com \
  --signature '<p><strong>Jane Doe</strong></p>' \
  --display-name 'Jane Doe' --reply-to jane@example.com
```

`update` is partial — fields you omit are left unchanged. Gmail
sanitizes the HTML server-side before storing it (script tags, dangerous
attributes get stripped).

### Audit the account in one call → `signature-audit.sh`

For day-to-day use, prefer the bundled audit script over hand-rolling
the jq:

```bash
bash claude-skills/skills/google-workspace/scripts/signature-audit.sh
bash claude-skills/skills/google-workspace/scripts/signature-audit.sh --format json
bash claude-skills/skills/google-workspace/scripts/signature-audit.sh --alias me@x.com
```

It enumerates every alias, computes per-alias warnings
(`signature_missing`, `plain_text_only`, `empty_after_strip`,
`primary_missing_display_name`), and exits non-zero when any signature
is missing or plain-text-only.

### Pull a signature out of an existing email → `signature-extract.sh`

```bash
bash claude-skills/skills/google-workspace/scripts/signature-extract.sh --alias me@x.com
bash claude-skills/skills/google-workspace/scripts/signature-extract.sh --message-id 18b... --preview
```

Looks at the 5 most recent sent messages from the alias, decodes the
text/html part, and isolates the `<div class="gmail_signature">…</div>`
block. Falls back to RFC-3676 `-- ` separator when the wrapper is
absent. Use `--raw` to dump the whole HTML body for manual inspection.

### Write a signature → `signature-set.sh`

```bash
# From a recent sent email:
bash claude-skills/skills/google-workspace/scripts/signature-set.sh \
  --alias me@x.com --from-latest-sent

# Inline:
bash claude-skills/skills/google-workspace/scripts/signature-set.sh \
  --alias me@x.com --html '<p><strong>Jane</strong></p>'

# From a file:
bash claude-skills/skills/google-workspace/scripts/signature-set.sh \
  --alias me@x.com --html-file ./signature.html

# Pipe extract → set (copy from one alias to another):
bash signature-extract.sh --alias me@old.com \
  | bash signature-set.sh --alias me@new.com --html-stdin
```

Always shows a text-only preview and asks for confirmation. `--dry-run`
prints the JSON body without calling Google. `--yes` skips the prompt
for scripted use.

### Why "send one email from Gmail web first" is sometimes required

`signature-extract.sh` relies on the `<div class="gmail_signature">`
wrapper that the **Gmail web composer / mobile app** auto-injects.
Messages sent via the API (including `gog gmail send`) don't carry
that wrapper unless the caller already appended it. If the user has
never composed an email from a given alias in Gmail web, extract has
nothing to read and falls back to the `-- ` heuristic — which can be
brittle. The reliable workflow is:

1. User composes & sends one email from the alias in Gmail web.
2. `signature-audit.sh` confirms the signature is now visible on the
   alias.
3. If the alias is missing the wrapper but Gmail web shows it correctly,
   the signature is registered on the alias's settings already (no fix
   needed) — re-run audit to confirm.

## Compose Gmail-ready HTML from markdown (`email-from-md.sh`)

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

# Pipe straight into a Gmail draft
bash claude-skills/skills/google-workspace/scripts/email-from-md.sh \
    --markdown ./memo.md --from me@example.com \
  | gog gmail drafts create \
      --to alice@example.com \
      --from me@example.com \
      --subject "Q2 recap" \
      --body-html-file -
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
3. Calls `gog api call gmail v1 users.settings.sendAs.list` to fetch the HTML
   signature for `--from`; appends it after the body. Skipped when
   `--no-signature` or `gog` is unavailable.

**Manual workaround** (if you need a one-liner without the script):

```bash
FROM="me@example.com"
SIG=$(gog api call gmail v1 users.settings.sendAs.list --params '{"userId":"me"}' --json \
  | jq -r ".sendAs[] | select(.sendAsEmail == \"$FROM\") | .signature")
pandoc -f markdown -t html --wrap=none body.md \
  | sed -E \
    -e 's|<table>|<table style="border-collapse:collapse;border:1px solid #ccc;margin:12px 0;font-family:Arial,sans-serif;font-size:13px;">|g' \
    -e 's|<th>|<th style="background:#f4f4f4;border:1px solid #ccc;padding:8px 10px;text-align:left;font-weight:600;">|g' \
    -e 's|<td>|<td style="border:1px solid #ccc;padding:8px 10px;vertical-align:top;">|g' \
  > /tmp/body.html
echo "$SIG" >> /tmp/body.html
gog gmail drafts create --to "$TO" --from "$FROM" --subject "$SUBJECT" \
  --body-html-file /tmp/body.html
```

**Direct compose (no markdown source).** When you build the HTML body
yourself instead of from a `.md` file, add the signature explicitly so
drafts/sent mail match Gmail web (skip on a `--no-signature` intent — see
SKILL.md "Agent-friendly conventions"). `gog gmail send` / `drafts create`
can append it themselves:

```bash
# Signature of the active send-as (or --signature-from <alias>)
gog gmail drafts create --to alice@x.com --subject 'Ping' \
  --body-html '<p>Hi Alice!</p>' --signature
```

Or fetch and append it by hand when you need control over placement:

```bash
SIG=$(gog api call gmail v1 users.settings.sendAs.list --params '{"userId":"me"}' --json \
  | jq -r '.sendAs[] | select(.isDefault==true) | .signature // empty')
BODY='<p>Hi Alice!</p>'
[ -n "$SIG" ] && BODY="${BODY}<br><br>${SIG}"
gog gmail drafts create --to alice@x.com --subject 'Ping' --body-html "$BODY"
```

## Cheap patterns

```bash
# Unread count
gog gmail messages search 'is:unread' --count --json --select totalMatchesAtLeast

# Archive a message (remove INBOX), or everything matching a query
gog gmail archive MSG_ID
gog gmail archive --query 'label:newsletters older_than:30d' --max 100

# Mark read / unread
gog gmail mark-read MSG_ID
gog gmail unread MSG_ID

# Trash (recoverable)
gog gmail trash MSG_ID

# Permanent delete (needs the broad https://mail.google.com/ scope)
gog gmail batch delete MSG_ID
```

Always prefer `trash`; use `batch delete` only on explicit user request.
