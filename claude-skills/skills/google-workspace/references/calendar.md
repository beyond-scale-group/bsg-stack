# Calendar

Prefer the first-class `gog calendar` commands (`events`, `search`, `create`,
`update`, `delete`, `freebusy`, `respond`). Use `gog api call calendar v3 ...`
for ACLs, secondary-calendar management beyond create/delete, and anything
the flags do not expose; `gog calendar raw <calendarId> <eventId>` gives a
lossless event dump.

Global flags: `--json` / `--plain`, `--results-only`, `--select`,
`--account <email|alias>` (or `GOG_ACCOUNT`), `--dry-run`, `--no-input`,
`--force`, `--readonly`. Exit codes: 0 ok, 2 usage, 3 empty results
(`--fail-empty`), 4 auth_required, 5 not_found, 6 permission_denied,
7 rate_limited, 8 retryable, 10 config.

## Time format (critical)

Events use **RFC 3339** with timezone offset:

```
2026-04-17T10:00:00+02:00     Paris
2026-04-17T09:00:00-07:00     Los Angeles
2026-04-17T08:00:00Z          UTC
```

Never omit the offset on `--from` / `--to` for timed events (`gog calendar
events` also accepts a bare date or `now`, `today`, `tomorrow`, `monday`).
For all-day events, pass `--all-day` with date-only values
(`--from 2026-04-17 --to 2026-04-18`); in raw API bodies use `date` instead
of `dateTime`: `{"date": "2026-04-17"}`. `--timezone Europe/Paris` sets the
IANA zone metadata on both ends (or `--start-timezone` / `--end-timezone`).

## Calendar identifiers

- `primary` — the authenticated user's main calendar
- `email@domain.com` — direct email as calendar ID
- `groupid@group.calendar.google.com` — shared/group calendars

Most `gog calendar` commands take the calendar ID as a positional argument
(`create`, `update`, `delete`, `respond`, `acl`); `events` defaults to
`primary`. List them:

```bash
gog calendar calendars --max 50
```

## List / search events

```bash
# Upcoming events on primary (next 10). Recurring events are expanded
# into individual occurrences.
gog calendar events primary --from now --max 10 --json

# Today / tomorrow / this week / next 3 days
gog calendar events --today
gog calendar events --week
gog calendar events --days 3 --timezone Europe/Paris

# A date window
gog calendar events primary --from 2026-04-01T00:00:00Z --to 2026-05-01T00:00:00Z --all-pages

# Every calendar at once, chronological
gog calendar events --all --today --sort start

# Text search
gog calendar events primary --query review --from 2026-04-01T00:00:00Z
gog calendar search review --from 2026-04-01T00:00:00Z --calendar primary --max 25
```

`gog calendar events` expands recurring events into occurrences for you, so
the raw `singleEvents=true` / `orderBy=startTime` parameters are only needed
when calling `gog api call calendar v3 events.list` directly. Add
`--fail-empty` when a script needs to detect "no events" (exit code 3).

## Create an event (with Meet link)

```bash
gog calendar create primary \
  --summary "Product sync" \
  --description "Weekly product review" \
  --from 2026-04-17T10:00:00+02:00 \
  --to   2026-04-17T11:00:00+02:00 \
  --timezone Europe/Paris \
  --attendees alice@x.com,bob@x.com \
  --with-meet \
  --send-updates all
```

`--send-updates` values: `all` · `externalOnly` · `none` (default `none`,
so attendees are **not** notified unless you ask). Attendee modifiers:
`bob@x.com;optional`, `room@x.com;resource`, `alice@x.com;comment=TEXT`.
Other useful flags: `--location`, `--reminder popup:30m`, `--no-reminders`,
`--visibility`, `--transparency busy|free`, `--event-color 1-11`,
`--guests-can-modify`. Preview with `--dry-run`.

Special event types exist as shortcuts: `gog calendar focus-time`,
`out-of-office`, and `working-location` (each needs `--from` / `--to`).

## Recurring events

Use [RRULE (RFC 5545)](https://icalendar.org/iCalendar-RFC-5545/3-8-5-3-recurrence-rule.html)
strings with `--rrule` (repeatable):

```bash
gog calendar create primary --summary "Standup" \
  --from 2026-04-20T09:30:00+02:00 --to 2026-04-20T09:45:00+02:00 \
  --rrule 'RRULE:FREQ=WEEKLY;BYDAY=MO,WE,FR;UNTIL=20260630T000000Z'
```

In a raw API body the same rules go in a `recurrence` array:

```json
"recurrence": ["RRULE:FREQ=WEEKLY;BYDAY=MO,WE,FR;UNTIL=20260630T000000Z"]
```

Common patterns:

```
RRULE:FREQ=DAILY;COUNT=10
RRULE:FREQ=WEEKLY;BYDAY=MO
RRULE:FREQ=MONTHLY;BYMONTHDAY=1
RRULE:FREQ=MONTHLY;BYDAY=1MO            first Monday of each month
RRULE:FREQ=YEARLY;BYMONTH=12;BYMONTHDAY=25
```

## Update / move / delete

```bash
# Change specific fields (only the flags you pass are modified)
gog calendar update primary EVENT_ID --summary "Updated title" --send-updates all

# Change time
gog calendar update primary EVENT_ID \
  --from 2026-04-17T14:00:00+02:00 --to 2026-04-17T15:00:00+02:00

# Add an attendee without replacing the list (--attendees replaces all)
gog calendar update primary EVENT_ID --add-attendee carol@x.com

# Recurring events: single | future | all (default all)
gog calendar update primary EVENT_ID --scope single \
  --original-start 2026-04-24T10:00:00+02:00 --summary "One-off title"

# Move to another calendar
gog calendar move primary EVENT_ID other@group.calendar.google.com

# Delete
gog calendar delete primary EVENT_ID --send-updates all
```

## Free/busy query

```bash
gog calendar freebusy alice@x.com,bob@x.com \
  --from 2026-04-17T08:00:00+02:00 \
  --to   2026-04-17T20:00:00+02:00 --json
```

Returns per-user busy blocks only — no event details. Also useful:
`gog calendar conflicts --today` (busy-time overlaps across your calendars).

## Respond to an invite

```bash
gog calendar respond primary EVENT_ID --status accepted --comment "See you there"
```

`--status`: `accepted` · `declined` · `tentative` · `needsAction`.

## Share a calendar (ACL)

`gog calendar acl <calendarId>` only lists. Adding or removing rules goes
through the Discovery escape hatch:

```bash
# List
gog calendar acl primary

# Add reader (write: needs --allow-write --force)
gog api call calendar v3 acl.insert --allow-write --force \
  --params '{"calendarId":"primary"}' \
  --body '{"scope":{"type":"user","value":"alice@x.com"},"role":"reader"}'
```

Roles: `none` · `freeBusyReader` · `reader` · `writer` · `owner`.

## Quick agenda

```bash
gog calendar events --today
gog calendar events --week
gog calendar events --days 3 --timezone Europe/Paris
```

See [workflows.md](workflows.md) for the ready-made agenda / standup flows,
and [raw-api.md](raw-api.md) for the `gog api call` conventions.
