# Regression Risk Scoring

How to rank files by regression risk using `churn × coverage` as the
primary signal.

## Definitions

- **Churn** — number of non-merge commits touching a file in the last
  30 days (via `git log --numstat --no-merges --since="30 days ago"`).
- **Coverage** — line coverage percentage from the latest coverage
  report, per file.
- **Risk score** — `churn * (1 - coverage / 100)`. Higher is worse.
  A file changed 10 times with 0% coverage scores 10; with 100%
  coverage, 0.

The score is dimensionless — use it for ranking, not absolute
judgement.

## How to run

```bash
bash scripts/risk.sh                          # fresh
bash scripts/risk.sh --snapshot /tmp/qa.json  # reuse snapshot
```

## Output schema

```json
{
  "summary": {
    "analyzedFiles": 145,
    "criticalCount": 2,
    "highCount": 5,
    "moderateCount": 14
  },
  "criticalFiles": [
    {
      "path": "src/payments/checkout.ts",
      "churn30d": 23,
      "coveragePct": 12.0,
      "score": 20.2,
      "band": "critical"
    }
  ],
  "highRiskFiles": [ { "...": "..." } ],
  "moderateFiles": [ { "...": "..." } ]
}
```

## Banding

| Band       | Condition                                                  | Meaning                                      |
| ---------- | ---------------------------------------------------------- | -------------------------------------------- |
| critical   | churn ≥ 10 AND coverage < 10%                              | Silence-breaker: test this file next         |
| high       | churn ≥ 10 AND coverage < 50%, OR churn ≥ 20               | Surface, but don't alert                     |
| moderate   | churn ≥ 5 AND coverage < 50%                               | Included for situational awareness           |
| low        | everything else                                            | Not reported individually                    |

## How to interpret

- **`criticalFiles[]` non-empty** → silence-breaker. List each file
  with a one-line recommendation (e.g. "add unit tests for the
  happy path").
- **`criticalFiles[]` grew since last snapshot** → amplify — surface
  the delta ("2 new files entered critical").
- **`criticalFiles[]` shrank** → silent. Improvement doesn't need chat
  noise.

## Common false positives

- **Lockfile-only changes.** `package-lock.json`, `Cargo.lock`, etc.
  contribute huge churn but are unit-testable elsewhere. The script
  excludes lockfiles by default.
- **Generated code.** Any path matched by `.gitignore` is already
  excluded by `git log` — but generated files committed to the repo
  (snapshot tests, auto-formatted fixtures) are not. Respect a
  `.qaignore` file if present (same format as `.gitignore`).
- **Docs churn.** `*.md` files are included by default but usually
  not risky. The agent can de-emphasize them in narrative.
