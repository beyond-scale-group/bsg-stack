# Recipes — cross-service workflows

Multi-step patterns that chain `gws` commands. Each recipe is read-only
unless marked **⚠ mutating**.

## Find a doc by name, then share it — ⚠ mutating

```bash
# 1. Find
FID=$(gws drive files list --params '{
  "q":"name contains '\''Q2 plan'\''",
  "fields":"files(id,name)",
  "pageSize":5
}' | jq -r '.files[0].id')

# 2. Share as writer
gws drive permissions create \
  --params "{\"fileId\":\"$FID\",\"sendNotificationEmail\":true}" \
  --json '{"role":"writer","type":"user","emailAddress":"alice@x.com"}'
```

Confirm with user before sharing — sends email notification.

## Export a Doc as PDF and attach to an email — ⚠ mutating

Requires the raw Gmail attachment flow (see references/gmail.md).

```bash
# 1. Export
gws drive files export \
  --params '{"fileId":"DOC_ID","mimeType":"application/pdf"}' \
  --output /tmp/doc.pdf

# 2. Build RFC 2822 with attachment → base64-url-encode → send
# (see references/gmail.md "Send with attachment (raw path)")
```

## Inbox triage → Tasks

Find actionable unread mail and promote each to a Google Task.

```bash
# 1. Unread messages with important label
gws gmail users messages list --params '{
  "userId":"me",
  "q":"is:unread label:important newer_than:7d",
  "maxResults":20
}' --format json | jq -r '.messages[].id' | while read MID; do
  # 2. Promote each to a task
  gws workflow +email-to-task --message-id "$MID"
done
```

Confirm with user before batch-running — creates N tasks.

## "What's on my plate today?" — read only

```bash
gws workflow +standup-report --format table
```

Or, a richer custom version:

```bash
echo "── Calendar (today) ──"
gws calendar +agenda --today --format table

echo
echo "── Inbox (unread) ──"
gws gmail +triage --max 10 --format table

echo
echo "── Tasks ──"
gws tasks tasks list --params '{"tasklist":"@default","showCompleted":false,"maxResults":20}' \
  --format table
```

## Meeting prep — read only

```bash
gws workflow +meeting-prep --format table
```

Grabs next event, attendees, description, linked docs.

Enhance by also fetching each attendee's recent email threads:

```bash
EVT=$(gws calendar events list --params '{
  "calendarId":"primary",
  "timeMin":"'"$(gws time now --format json 2>/dev/null | jq -r '.iso' || date -u +%FT%TZ)"'",
  "maxResults":1,"singleEvents":true,"orderBy":"startTime"
}' | jq '.items[0]')

echo "$EVT" | jq -r '.attendees[]?.email' | while read EMAIL; do
  echo "── Recent with $EMAIL ──"
  gws gmail +triage --query "from:$EMAIL OR to:$EMAIL newer_than:14d" --max 5 --format table
done
```

## Append a row to a sheet from a Gmail message — ⚠ mutating

Useful for lightweight CRM / bug log / expense tracker patterns.

```bash
# 1. Pull subject + from from a message
META=$(gws gmail users messages get \
  --params '{"userId":"me","id":"MSG_ID","format":"metadata","metadataHeaders":["From","Subject","Date"]}')

FROM=$(echo "$META" | jq -r '.payload.headers[] | select(.name=="From") | .value')
SUBJ=$(echo "$META" | jq -r '.payload.headers[] | select(.name=="Subject") | .value')
DATE=$(echo "$META" | jq -r '.payload.headers[] | select(.name=="Date") | .value')

# 2. Append to tracking sheet
gws sheets +append --spreadsheet SHEET_ID \
  --json-values "[[\"$DATE\",\"$FROM\",\"$SUBJ\"]]"
```

## Weekly digest into a Chat space — ⚠ mutating

```bash
# 1. Build digest
DIGEST=$(gws workflow +weekly-digest --format table)

# 2. Post to a space (confirm with user first)
gws chat +send --space spaces/AAAAxxxx --text "$DIGEST"
```

## Dry-run-then-execute pattern

For any mutating command, show the user the `--dry-run` output first,
confirm, then run for real:

```bash
# 1. Show what would happen
gws calendar events insert \
  --params '{"calendarId":"primary","conferenceDataVersion":1,"sendUpdates":"all"}' \
  --json "$PAYLOAD" \
  --dry-run

# 2. On user confirm, drop --dry-run
gws calendar events insert \
  --params '{"calendarId":"primary","conferenceDataVersion":1,"sendUpdates":"all"}' \
  --json "$PAYLOAD"
```

## Batch with `xargs` + `--page-all`

```bash
# Archive every unread promotional email
gws gmail users messages list \
  --params '{"userId":"me","q":"category:promotions is:unread","maxResults":100}' \
  --page-all --page-limit 10 \
  | jq -r '.messages[].id' \
  | xargs -I {} gws gmail users messages modify \
      --params '{"userId":"me","id":"{}"}' \
      --json '{"removeLabelIds":["INBOX","UNREAD"]}'
```

Always confirm with the user before mass-mutating commands.
