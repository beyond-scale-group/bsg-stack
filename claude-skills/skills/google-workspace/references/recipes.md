# Recipes — cross-service workflows

Multi-step patterns that chain `gog` commands. Each recipe is read-only
unless marked **⚠ mutating**. JSON key names below are best-effort: run the
first command with `--json` and check the shape before piping into `jq`.

## Find a doc by name, then share it — ⚠ mutating

```bash
# 1. Find
FID=$(gog drive search 'Q2 plan' --max 5 --json --results-only | jq -r '.[0].id')
gog drive get "$FID"            # confirm it is the right file

# 2. Share as writer (preview first)
gog drive share "$FID" --to user --email alice@x.com --role writer --notify --dry-run
gog drive share "$FID" --to user --email alice@x.com --role writer --notify
```

Confirm with user before sharing — `--notify` sends an email notification
(omit it for a silent share).

## Export a Doc as PDF and attach to an email — ⚠ mutating

```bash
# 1. Export
gog drive download DOC_ID --format pdf --out /tmp/doc.pdf

# 2. Send with the attachment (native — no RFC 2822 by hand)
gog gmail send --to alice@x.com --subject 'Doc as PDF' \
  --body-html '<p>Please find the PDF attached.</p>' \
  --attach /tmp/doc.pdf --dry-run
# on user confirm, re-run without --dry-run
```

## Inbox triage → Tasks

Find actionable unread mail and promote each to a Google Task.

```bash
gog gmail messages search 'is:unread label:important newer_than:7d' \
  --max 20 --json --results-only | jq -r '.[].id' | while read MID; do
  SUBJ=$(gog gmail get "$MID" --format metadata --headers Subject --json \
    | jq -r '[.. | objects | select(.name? == "Subject") | .value][0]')
  gog tasks add @default --title "$SUBJ" \
    --notes "https://mail.google.com/mail/u/0/#all/$MID" --dry-run
done
```

Confirm with user before batch-running — creates N tasks. Drop `--dry-run`
to execute. (`@default` = primary task list; other IDs via
`gog tasks lists list`.)

## "What's on my plate today?" — read only

```bash
echo "── Calendar (today) ──"
gog calendar events --today

echo
echo "── Inbox (unread) ──"
gog gmail search 'is:unread' --max 10

echo
echo "── Tasks ──"
gog tasks list @default --max 20
```

Add `--plain` for stable TSV, `--json` for scripting. Upstream skill
`gog-weekly-digest` covers the weekly variant.

## Meeting prep — read only

Grab the next event (attendees, description, attachments):

```bash
gog calendar events --from now --max 1 --json --results-only
```

Enhance by also fetching each attendee's recent email threads:

```bash
EVT=$(gog calendar events --from now --max 1 --json --results-only | jq '.[0]')

echo "$EVT" | jq -r '.attendees[]?.email' | while read EMAIL; do
  echo "── Recent with $EMAIL ──"
  gog gmail search "from:$EMAIL OR to:$EMAIL newer_than:14d" --max 5
done
```

Linked Drive files: `echo "$EVT" | jq -r '.attachments[]?.fileUrl'`, then
`gog drive get <fileId>`. Upstream skill: `gog-meeting-prep`.

## Append a row to a sheet from a Gmail message — ⚠ mutating

Useful for lightweight CRM / bug log / expense tracker patterns.

```bash
# 1. Pull From / Subject / Date from a message
META=$(gog gmail get MSG_ID --format metadata --headers From,Subject,Date --json)
hdr() { jq -r --arg n "$1" '[.. | objects | select(.name? == $n) | .value][0]' <<<"$META"; }
FROM=$(hdr From); SUBJ=$(hdr Subject); DATE=$(hdr Date)

# 2. Append to the tracking sheet (build the JSON with jq — no quoting bugs)
VALUES=$(jq -nc --arg d "$DATE" --arg f "$FROM" --arg s "$SUBJ" '[[$d,$f,$s]]')
gog sheets append SHEET_ID 'Sheet1!A:C' --values-json "$VALUES" --dry-run
```

Drop `--dry-run` after confirmation.

## Weekly digest into a Chat space — ⚠ mutating

```bash
# 1. Build digest
DIGEST=$( { echo "Agenda (week)"; gog calendar events --week --max 50 --plain
            echo; echo "Unread: $(gog gmail search 'is:unread' --count --max 1 --json | jq -r '.totalMatches // .totalMatchesAtLeast')"; } )

# 2. Post to a space (confirm with user first)
gog chat messages send spaces/AAAAxxxx --text "$DIGEST"
```

## Dry-run-then-execute pattern

For any mutating command, show the user the `--dry-run` output first,
confirm, then run for real. `--dry-run` is a global flag that prints the
intended action and exits 0 without changing anything.

```bash
# 1. Show what would happen
gog calendar create primary --summary 'Review' \
  --from '2026-06-17T14:00:00+02:00' --to '2026-06-17T15:00:00+02:00' \
  --attendees alice@x.com --with-meet --send-updates all --dry-run

# 2. On user confirm, drop --dry-run
gog calendar create primary --summary 'Review' \
  --from '2026-06-17T14:00:00+02:00' --to '2026-06-17T15:00:00+02:00' \
  --attendees alice@x.com --with-meet --send-updates all
```

Same for the generic path: `gog api call … --allow-write --dry-run`, then
`--allow-write --force`.

## Batch with `xargs` / built-in batching

```bash
# Archive every unread promotional email — built-in
gog gmail archive -q 'category:promotions is:unread' --max 500 --dry-run

# Or explicit IDs with xargs (batch modify takes many IDs per call)
gog gmail messages search 'category:promotions is:unread' --all --json --results-only \
  | jq -r '.[].id' \
  | xargs -n 100 gog gmail batch modify --remove INBOX,UNREAD
```

`--all` follows pagination; `--max` caps the archive count. Always confirm
with the user before mass-mutating commands, and run the first pass with
`--dry-run` (on the `xargs` form, prefix the command with `echo` to inspect).
