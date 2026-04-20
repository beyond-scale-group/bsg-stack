# Content Calendar Management

## `marketing/CALENDAR.md` format

Plain markdown with checklist-style items. Each item starts with a
dash, an optional checkbox, an ISO date prefix, and a title:

```markdown
# Marketing Content Calendar

## Q2 2026
- [ ] 2026-04-15 — Blog: API v2 launch
- [ ] 2026-04-30 — Newsletter: Q2 update
- [x] 2026-03-28 — Case study: Acme Corp (completed)
- [ ] 2026-05-10 — Webinar: Security best practices

## Q3 2026
- [ ] 2026-07-01 — Blog: Mid-year roundup
```

Rules:

- Lines starting with `- [ ] <date> — <title>` are scheduled.
- Lines starting with `- [x]` are completed and excluded from the
  overdue list.
- Dates must be ISO `YYYY-MM-DD`. Relative dates like "next week"
  are out of scope for the MVP.
- H2 section headers are narrative; they don't affect parsing.

If the file doesn't exist, `calendar.sh` returns
`{"calendarFound": false}` and the reporter renders a bootstrap
suggestion on the first tick.

## How to run

```bash
bash scripts/calendar.sh                          # fresh
bash scripts/calendar.sh --snapshot /tmp/*.json   # reuse snapshot
```

## Output schema

```json
{
  "calendarFound": true,
  "summary": {
    "total": 10,
    "completed": 3,
    "overdue": 1,
    "today": 0,
    "upcoming": 6
  },
  "overdueItems": [
    { "date": "2026-04-15", "title": "Blog: API v2 launch", "daysLate": 5 }
  ],
  "todayItems": [],
  "upcomingItems": [
    { "date": "2026-04-30", "title": "Newsletter: Q2 update", "daysUntil": 10 }
  ]
}
```

## How to interpret

- **`overdueItems[]` non-empty** → silence-breaker. Every item
  past its date that hasn't been checked off.
- **`calendarFound: false`** → surface once (first tick) with a
  suggestion to create a starter file. After that, silent.
- **`today` + `upcoming`** counts → narrative, not alert.

## Pitfalls

- **Forgot to check off** — the most common cause of a false
  overdue. The agent surfaces it; the human decides whether to
  check off or reschedule.
- **Timezone edges** — dates are interpreted as end-of-day local
  time. An item dated today is not overdue.

## What NOT to do

- Don't auto-edit the calendar file. Bootstrap only, and only on
  explicit user confirmation.
- Don't suggest content topics — that's a marketing decision, not
  the agent's.
