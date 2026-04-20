# Event Classification

How the skill decides what counts as "newsworthy."

## Categories

| Category                | Heuristic                                                                  |
| ----------------------- | -------------------------------------------------------------------------- |
| **major release**       | Semver tag with `major` bump (e.g. `v3.0.0`)                               |
| **minor release**       | Semver tag with `minor` bump (e.g. `v2.4.0`)                               |
| **patch release**       | Semver tag with `patch` bump — skipped unless security-tagged              |
| **milestone closure**   | A closed GitHub milestone with > 0 closed issues                           |
| **security advisory**   | A public advisory on the repo (`gh api /repos/.../security-advisories`)    |
| **community milestone** | 100th / 500th / 1000th contributor, 100th / 500th / 1000th PR merged       |

Pre-releases (`-rc.1`, `-beta`), drafts, and prereleases are
excluded.

## Announced vs unannounced

An event is **announced** when **any** of:

1. `comms/ANNOUNCED.md` contains a line matching its tag / milestone
   number.
2. A file under `comms/press-releases/` contains the release tag in
   its filename.

Otherwise it's unannounced. Note: this is a best-effort proxy — the
comms team can maintain `ANNOUNCED.md` explicitly for precision.

## How to run

```bash
bash scripts/events.sh                          # fresh
bash scripts/events.sh --snapshot /tmp/*.json   # reuse snapshot
```

## Output schema

```json
{
  "summary": {
    "total": 6,
    "unannouncedMajor": 1,
    "unannouncedMilestone": 1,
    "securityAdvisories": 0,
    "communityMilestones": 1,
    "patchesSkipped": 2
  },
  "unannouncedMajor": [
    { "release": "v2.4.0", "type": "minor", "publishedAt": "2026-04-18",
      "priority": "high" }
  ],
  "unannouncedMilestone": [
    { "milestone": "API v2", "closedAt": "2026-04-15" }
  ],
  "securityAdvisories": [],
  "communityMilestones": [
    { "kind": "contributors", "count": 50, "hitOn": "2026-04-12" }
  ]
}
```

## How to interpret

- **`unannouncedMajor[]` non-empty** → silence-breaker. The comms
  team likely wants a draft angle.
- **`unannouncedMilestone[]` non-empty** → silence-breaker. A
  completed milestone is usually a story beat.
- **`securityAdvisories[]` non-empty** → silence-breaker, but the
  agent does NOT draft a response. It surfaces the advisory ID and
  links to the GitHub advisory page.
- **`communityMilestones[]` at a canonical threshold** → silence-
  breaker. Getting to 100 / 500 / 1000 of anything is a nice
  marketing moment.

## Priority scoring

- **high** — unannounced major release OR milestone closure
- **medium** — unannounced minor release OR community milestone
- **low** — patches (skipped unless security-tagged)

## What NOT to do

- Don't auto-announce anything. This skill never publishes.
- Don't invent community milestone thresholds. They're hard-coded
  to 100 / 500 / 1000 intentionally — humans can notice 42 and
  47 without agent help.
- Don't treat a pre-release as unannounced — pre-releases are
  excluded from the announcement matrix.
