# Coverage Analysis

How to parse, compare, and report on test coverage.

## Supported formats

`collect.sh` auto-detects the coverage report from these filenames
(first match wins):

| File                             | Format                              |
| -------------------------------- | ----------------------------------- |
| `coverage/lcov.info`             | lcov (Istanbul, Jest, nyc)          |
| `coverage/coverage-summary.json` | Istanbul JSON summary               |
| `coverage/coverage-final.json`   | Istanbul per-file JSON              |
| `coverage.xml`                   | Cobertura / JaCoCo XML              |
| `.coverage`                      | Python `coverage.py` SQLite         |
| `coverage.out`                   | Go `go test -coverprofile`          |
| `target/scala-*/scoverage.xml`   | Scala scoverage                     |

If none of these files exist, `collect.sh` sets `coverageFound: false`
and the reporter returns the schema below with zeros — the agent
surfaces a one-shot "no coverage report found" silence-breaker on the
first tick after a repo is adopted.

## How to run

```bash
bash scripts/coverage.sh                          # fresh
bash scripts/coverage.sh --snapshot /tmp/qa.json  # reuse snapshot
```

## Output schema

```json
{
  "found": true,
  "format": "lcov",
  "current": {
    "line":   { "covered": 2841, "total": 3930, "pct": 72.3 },
    "branch": { "covered": 1112, "total": 1914, "pct": 58.1 },
    "files":  { "total": 145, "zeroCoverage": 12 }
  },
  "previous": {
    "line":   { "pct": 74.1 },
    "branch": { "pct": 59.0 },
    "files":  { "zeroCoverage": 10 },
    "date":   "2026-04-13"
  },
  "delta": {
    "line": -1.8,
    "branch": -0.9,
    "zeroCoverage": 2
  },
  "perFile": [
    { "path": "src/payments/checkout.ts", "linePct": 12.0, "branchPct": 8.0 }
  ]
}
```

## How to interpret

- **`delta.line < -5`** → silence-breaker. Reply with the offending PR
  range (commits between previous and current snapshot dates).
- **`current.files.zeroCoverage` increased and any of the new zero-
  coverage files have non-trivial churn** → combine with `risk.sh`
  output; do not fire a silence-breaker on coverage alone for this
  case.
- **`found: false`** → surface once per repo (first tick), then silent.
- **`previous: null`** → no prior snapshot in `qa/history/`; delta is
  undefined. Don't invent a baseline.

## Common pitfalls

- **Generated files inflating coverage.** Excluded by default via
  `.gitignore` + a static generated-path list (`dist/`, `build/`,
  `.next/`, `coverage/`).
- **Monorepo packages with separate reports.** `collect.sh` picks the
  first match at the repo root; to audit a sub-package, run from that
  package's directory.
- **Branch coverage not reported by the format.** Cobertura always
  provides it; lcov may or may not — reflect `null` rather than
  guessing.
