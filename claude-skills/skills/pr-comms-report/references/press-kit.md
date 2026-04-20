# Press Kit Management

## Expected structure

```
comms/
├── press-kit/
│   ├── boilerplate.md      # Short / medium / long company description
│   ├── fact-sheet.md       # Key facts, numbers, differentiators
│   ├── leadership.md       # Founder and exec bios + approved quotes
│   ├── milestones.md       # Company timeline
│   ├── faq.md              # Journalist-facing FAQ
│   └── contact.md          # Press contact name + email
└── ANNOUNCED.md            # Log of communicated events (controls unannounced[])
```

The directory structure is optional but recommended. If a file isn't
present, the corresponding section of each press-release draft
renders a placeholder pointing to the missing file.

## Freshness rules

| File                  | Stale after         |
| --------------------- | ------------------- |
| `boilerplate.md`      | 180 days            |
| `fact-sheet.md`       | 90 days             |
| `leadership.md`       | 180 days            |
| `milestones.md`       | 90 days             |
| `faq.md`              | 180 days            |
| `contact.md`          | 365 days            |
| Any other .md in kit  | 90 days (default)   |

The default threshold for a silence-breaker is **90 days** regardless
of file; the stricter per-file ceiling above is used by the
reporter's narrative but doesn't change the breaker.

## How to run

```bash
bash scripts/press-kit.sh                          # fresh
bash scripts/press-kit.sh --snapshot /tmp/*.json   # reuse snapshot
```

## Output schema

```json
{
  "present": true,
  "directory": "comms/press-kit/",
  "assets": [
    { "file": "boilerplate.md", "lastUpdated": "2026-03-01", "ageDays": 50, "stale": false }
  ],
  "staleAssets": [
    { "file": "fact-sheet.md", "lastUpdated": "2025-12-15", "ageDays": 127 }
  ],
  "missingRecommended": ["leadership.md", "faq.md"]
}
```

## How to interpret

- **`staleAssets[]` non-empty** → silence-breaker. Each entry is an
  asset whose last git-tracked mtime exceeds the 90-day threshold.
- **`missingRecommended[]` non-empty** → surface in the report
  narrative; it's a gap, not an alert.
- **`present: false`** → the press kit directory doesn't exist at
  all. On the first tick, the agent suggests bootstrapping. After
  that, silent.

## What NOT to do

- Don't auto-edit press-kit files. They require human authorship.
- Don't publish press-kit content in drafts without the kit actually
  existing — placeholders are fine; fabricated content is not.
- Don't treat press-kit mtime as "when we last announced this" — it
  only tells us when the file changed. `ANNOUNCED.md` is the
  authoritative announced-status source when present.
