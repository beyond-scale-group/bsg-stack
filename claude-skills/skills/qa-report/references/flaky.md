# Flaky Test Detection

How to detect tests that fail intermittently from recent CI logs.

## Detection signal

A test is **flaky** when it exhibits one of:

1. **Passed-then-failed on the same commit SHA** across different
   workflow runs (e.g. re-runs after a retry).
2. **Alternating pass/fail pattern** across the last N runs on a given
   test ID, independent of commit. Threshold: pass rate between 0.2
   and 0.8 over at least 5 runs.

Scope is the last **14 days** by default, capped at 50 workflow runs
to keep API calls bounded.

## How to run

```bash
bash scripts/flaky.sh                          # fresh
bash scripts/flaky.sh --snapshot /tmp/qa.json  # reuse snapshot
```

## Output schema

```json
{
  "summary": {
    "windowDays": 14,
    "runsAnalyzed": 50,
    "flakeCount": 3,
    "newFlakes": 1
  },
  "flakes": [
    {
      "test": "tests/webhook/retry_spec.py::test_exponential_backoff",
      "passRate": 0.6,
      "runs": 10,
      "firstSeen": "2026-04-14",
      "lastFailedRun": "https://github.com/owner/repo/actions/runs/401"
    }
  ],
  "newFlakes": [
    { "test": "...", "firstSeen": "2026-04-20" }
  ]
}
```

`newFlakes[]` is the set of flakes whose `firstSeen` equals today's
date. The agent uses this for the silence-breaker: a flake that has
been known for a week does not re-alert.

## How to interpret

- **`newFlakes[]` non-empty** → silence-breaker. Link each to its
  last failing run.
- **`flakes[]` grew but `newFlakes[]` is empty** → existing flakes
  got worse; don't alert but surface in the report.
- **`summary.runsAnalyzed < 5`** → not enough signal. Note in the
  report; no silence-breaker.

## What NOT to do

- **Don't auto-retry failing tests.** Out of scope for the agent.
- **Don't recommend skipping a flaky test** as a first-line fix. Even
  as a comment, this encourages bad habits.
- **Don't surface tests that failed consistently** — those are bugs,
  not flakes. Consistent failures belong in the `risk.sh` output
  (low pass rate, high churn).

## CI source

The script consumes `gh run list --json ...` + `gh run view --log-failed`
for the last 50 workflow runs on the default branch. If the repo uses
a non-standard CI provider, flake detection returns
`{"applicable": false, "reason": "..."}` — the agent skips the section
rather than fabricating data.
