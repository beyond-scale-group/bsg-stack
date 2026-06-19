---
name: qa-report
description: >
  Quality-assurance audit toolkit for the current GitHub repository.
  Parses coverage reports (lcov, coverage-summary.json, .coverage,
  coverage.xml), computes regression risk from churn × coverage,
  detects flaky tests from recent CI logs, and composes a dated audit
  report. Use when the user asks to "check test coverage", "score
  regression risk", "detect flaky tests", "run a QA audit", or "show
  coverage trends". Scripts do the aggregation; the LLM narrates.
model: haiku
---

# QA Report

The QA-audit skill for the **current repository**. Shipped as the
implementation layer behind the `@qa` subagent — run directly when you
just need the raw data, or let `@qa` orchestrate it for a
silent-by-default tick.

## Intent routing

| If the user asks about...                                        | Read this reference         |
| ---------------------------------------------------------------- | --------------------------- |
| Current coverage, coverage delta, covered/uncovered files        | `references/coverage.md`    |
| Regression risk heatmap (churn × coverage)                       | `references/risk.md`        |
| Flaky test detection from recent CI logs                         | `references/flaky.md`       |
| Generating a test plan for a feature or PR                       | `references/test-plan.md`   |

For a **full audit** (coverage + risk + flaky), run
`generate-report.sh` — it collects once, runs every reporter, and
composes a single markdown file under `qa/reports/`.

## Hard rules

1. **Never invent metrics.** Every coverage %, churn count, or flake
   rate must come from a script's JSON output — not recognition or
   memory.
2. **Always write the final report to `qa/reports/YYYY-MM-DD-*.md`**
   and the raw snapshot to `qa/history/YYYY-MM-DD.json`.
3. **Run scripts from the repo root.** They auto-detect coverage
   format via common filenames.
4. **Never execute the test suite.** `npm test`, `pytest`, `sbt test`
   are off-limits. Read existing coverage artifacts only.
5. **Ignore generated files.** `coverage/`, `dist/`, `build/`, `.next/`,
   `target/`, `node_modules/` — excluded from churn analysis by
   default.
6. **Confirm before posting** to GitHub (issue comments, labels).
   Default is local-only.

## Available scripts

All scripts live in `scripts/` and emit JSON on stdout (except
`generate-report.sh`, which emits markdown). `collect.sh` is the single
cross-tool fetch; every other reporter is a pure jq transform of that
snapshot — pass it with `--snapshot <path>`, pipe it in, or let the
script auto-collect a fresh one.

| Script                | Purpose                                                                 |
| --------------------- | ----------------------------------------------------------------------- |
| `collect.sh`          | Auto-detect coverage format (lcov / JSON / Cobertura / .coverage), parse current coverage, gather `git log --numstat` churn for the last 30 days, fetch last 50 CI workflow runs via `gh run list`. One snapshot → `/tmp/qa-snap.json`. |
| `coverage.sh`         | Transform snapshot → per-file and overall line/branch coverage, plus delta against the most recent `qa/history/*.json`. |
| `risk.sh`             | Join churn × coverage to emit a ranked heatmap with `criticalFiles[]` (high churn + 0% coverage) and `highRiskFiles[]` (moderate churn + low coverage). |
| `flaky.sh`            | Parse recent CI logs for tests that failed then passed on the same commit, or passed/failed alternately across runs. Emits `flakes[]` with pass rate and first-seen date. |
| `generate-report.sh`  | Collects once, runs every reporter, composes the full markdown audit. |

**Invocation patterns:**

```bash
# One-shot: full audit (also archives snapshot)
bash scripts/generate-report.sh > qa/reports/$(date +%F)-audit.md

# Reuse one snapshot across multiple reporters
bash scripts/collect.sh > /tmp/qa-snap.json
bash scripts/coverage.sh --snapshot /tmp/qa-snap.json
bash scripts/risk.sh     --snapshot /tmp/qa-snap.json
bash scripts/flaky.sh    --snapshot /tmp/qa-snap.json

# Risk only, filtered to critical
bash scripts/risk.sh | jq '.criticalFiles'
```

## Output convention

Reports go to `qa/reports/`. Snapshots go to `qa/history/`. Filename
patterns:

```
qa/reports/2026-04-20-audit.md       # full audit from tick
qa/reports/2026-04-20-risk.md        # risk-only slice
qa/reports/2026-04-20-coverage.md    # coverage-only slice
qa/history/2026-04-20.json           # raw snapshot for trends
```

Use today's date. After writing, print the file path and a one-line
verdict — do **not** dump the full report inline.

## Tick action

Users invoke `tick` (typically via `@qa tick` from `/loop` or
`/schedule`) when they want the QA audit to run now and the result to
be archived in the repo. It is **idempotent, repo-scoped, and silent
by default**.

This `tick` follows the BSG-wide convention documented in the top-level
[`CLAUDE.md`][claude-md] under "The `tick` convention" — silent-by-default,
human-initiated (no CI cron), repo-scoped.

[claude-md]: https://github.com/beyond-scale-group/bsg-stack/blob/main/CLAUDE.md

### Steps

1. **Generate the full audit** — one invocation composes every reporter
   and archives the snapshot:

   ```bash
   mkdir -p qa/reports qa/history
   SNAP=$(mktemp)
   bash ~/.claude/skills/qa-report/scripts/collect.sh > "$SNAP"
   cp "$SNAP" qa/history/$(date +%F).json
   bash ~/.claude/skills/qa-report/scripts/generate-report.sh \
     > qa/reports/$(date +%F)-audit.md
   ```

2. **Land the report via the shared helper** — never commit to `main`
   directly:

   ```bash
   bash ~/.claude/scripts/open-report-pr.sh \
     qa/reports/$(date +%F)-audit.md \
     --agent qa
   ```

3. **Evaluate silence-breakers** by comparing today's snapshot with
   the previous entry in `qa/history/`. The `@qa` agent owns the
   thresholds; this skill emits raw deltas.

4. **Reply.** If no silence-breaker fires, a single line — e.g.
   `Tick: QA stable, report at <PR url>` — is the whole reply.
   Otherwise, summarize which signal fired (coverage delta, new flakes,
   critical file) and link the PR.

### Silence is a feature

Do **not** pad the reply with "all green" narrative or next-step
suggestions when nothing fired. One-line receipts only. The committed
report PR is the full audit trail — the chat line is just a receipt.
Writing tests, fixing flaky tests, or remediating risk is **never**
part of `tick` — the user explicitly opts into each remediation.

---

## How to improve this skill

This file is a cached copy of `claude-skills/skills/qa-report/SKILL.md` in
[beyond-scale-group/bsg-stack](https://github.com/beyond-scale-group/bsg-stack).
That repo is the single source of truth — `~/.claude/skills/qa-report/SKILL.md` is
overwritten every time the BSG install flow runs.

If the user asks you to improve, fix, or extend this skill, do **not** edit
the local file. Instead:

1. `gh repo clone beyond-scale-group/bsg-stack` (or work in an existing clone)
2. Edit `claude-skills/skills/qa-report/SKILL.md` on a feature branch
3. Open a pull request against `main`

Bug reports and ideas without a fix → open an issue on the same repo.
