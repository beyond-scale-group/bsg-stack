# Calendar

Prefer `+insert` and `+agenda` for common tasks. Raw API for recurrence,
Meet conferencing, free/busy queries, ACLs, secondary calendars.

## Time format (critical)

Events use **RFC 3339** with timezone offset:

```
2026-04-17T10:00:00+02:00     Paris
2026-04-17T09:00:00-07:00     Los Angeles
2026-04-17T08:00:00Z          UTC
```

Never omit the offset. For all-day events, use `date` instead of `dateTime`:
`{"date": "2026-04-17"}`.

## Calendar identifiers

- `primary` — the authenticated user's main calendar
- `email@domain.com` — direct email as calendar ID
- `groupid@group.calendar.google.com` — shared/group calendars

List them:

```bash
gws calendar calendarList list --params '{"maxResults":50}' --format table
```

## List / search events

```bash
# Upcoming events on primary (next 10)
gws calendar events list --params '{
  "calendarId":"primary",
  "timeMin":"2026-04-16T00:00:00Z",
  "singleEvents":true,
  "orderBy":"startTime",
  "maxResults":10
}'

# Text search
gws calendar events list --params '{
  "calendarId":"primary",
  "q":"review",
  "timeMin":"2026-04-01T00:00:00Z",
  "singleEvents":true,
  "orderBy":"startTime"
}'
```

Always set `"singleEvents": true` when listing — otherwise recurring events
appear only as their series definition, not as individual occurrences.

## Create an event (raw, with Meet link)

```bash
gws calendar events insert --params '{"calendarId":"primary","conferenceDataVersion":1,"sendUpdates":"all"}' \
  --json '{
    "summary":"Product sync",
    "description":"Weekly product review",
    "start":{"dateTime":"2026-04-17T10:00:00+02:00","timeZone":"Europe/Paris"},
    "end":  {"dateTime":"2026-04-17T11:00:00+02:00","timeZone":"Europe/Paris"},
    "attendees":[{"email":"alice@x.com"},{"email":"bob@x.com"}],
    "conferenceData":{
      "createRequest":{"requestId":"req-abc123","conferenceSolutionKey":{"type":"hangoutsMeet"}}
    }
  }'
```

`sendUpdates` values: `all` · `externalOnly` · `none`.

## Recurring events

Use [RRULE (RFC 5545)](https://icalendar.org/iCalendar-RFC-5545/3-8-5-3-recurrence-rule.html)
strings in a `recurrence` array:

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
# Patch specific fields
gws calendar events patch --params '{"calendarId":"primary","eventId":"EVENT_ID","sendUpdates":"all"}' \
  --json '{"summary":"Updated title"}'

# Change time
gws calendar events patch --params '{"calendarId":"primary","eventId":"EVENT_ID"}' \
  --json '{"start":{"dateTime":"..."},"end":{"dateTime":"..."}}'

# Delete
gws calendar events delete --params '{"calendarId":"primary","eventId":"EVENT_ID","sendUpdates":"all"}'
```

## Free/busy query

```bash
gws calendar freebusy query --json '{
  "timeMin":"2026-04-17T08:00:00+02:00",
  "timeMax":"2026-04-17T20:00:00+02:00",
  "items":[{"id":"alice@x.com"},{"id":"bob@x.com"}]
}'
```

Returns per-user busy blocks only — no event details.

## Respond to an invite

```bash
gws calendar events patch --params '{"calendarId":"primary","eventId":"EVENT_ID","sendUpdates":"externalOnly"}' \
  --json '{"attendees":[{"email":"me@x.com","responseStatus":"accepted"}]}'
```

`responseStatus`: `accepted` · `declined` · `tentative` · `needsAction`.

## Share a calendar (ACL)

```bash
# List
gws calendar acl list --params '{"calendarId":"primary"}'

# Add reader
gws calendar acl insert --params '{"calendarId":"primary"}' \
  --json '{"scope":{"type":"user","value":"alice@x.com"},"role":"reader"}'
```

Roles: `none` · `freeBusyReader` · `reader` · `writer` · `owner`.

## Quick agenda via helper

```bash
gws calendar +agenda --today --format table
gws calendar +agenda --week
gws calendar +agenda --days 3 --timezone Europe/Paris
```
