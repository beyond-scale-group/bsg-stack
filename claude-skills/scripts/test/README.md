# Pipeline regression harness

Compressed-run test harness for the bsg-stack autopilot pipeline.
30 minutes at 60-second cadence ≈ 30 ticks ≈ ~15 days of prod at the
standard `/loop 30m /tick-all` cadence — without burning prod tokens.

Tracked in #292.

## Quick start

```bash
bash claude-skills/scripts/test/run-pipeline-test.sh \
  --repo beyond-scale-group/bsg-stack-test-harness \
  --duration 30m \
  --cadence 60s
```

The runner clones the harness repo to `/tmp/harness-clone-$EPOCH`,
resets state, seeds a fresh synthetic backlog, fires `claude -p
"/tick-all"` on a loop, then asserts invariants. Exits 0 if green.

## Files

| File | Role |
|---|---|
| `seed-test-backlog.sh` | populate the test repo with synthetic issues (60% tech, 25% qa, 15% seo) |
| `run-pipeline-test.sh` | reset + seed + loop + collect + assert |
| `assert-invariants.sh` | check invariants I1–I4 against collected logs |

## Invariants checked (v1)

| ID | Name | Catches |
|---|---|---|
| **I1** | distribution | monopoly (cf. 2026-04-30 — tech-lead opened 8/8 PRs) |
| **I2** | idempotency | duplicate report PRs (cf. `TICK_FINGERPRINT` bug, #262) |
| **I3** | lock cleanup | leaked `agent:lock:*` labels (cf. #270, #273) |
| **I4** | budget compliance | merged PR exceeds `max_loc_per_issue` / `max_files_per_issue` |

I5–I8 (issue-dedup fingerprints, phase-B reactivity, token budget,
auto-merge label race) ship in a v2 of this harness — they require a
baseline store that doesn't exist yet.

## Reset semantics

`run-pipeline-test.sh` (without `--no-reset`) does the following on
the harness repo:

1. Closes every open issue carrying `label:test-fixture`
2. Removes every open `agent:lock:*` label across all 8 agents
3. Closes every open PR (with `--delete-branch`)

State on `main` is **not** force-pushed — agents commit through
report/feature branches, never directly to main, so a clean main is
preserved across runs without intervention. If a buggy agent ever
pushes to main, reset main manually:

```bash
gh api -X PATCH repos/beyond-scale-group/bsg-stack-test-harness/git/refs/heads/main \
  -f sha="$(gh api repos/beyond-scale-group/bsg-stack/git/refs/heads/main --jq .object.sha)" \
  -F force=true
```

## Baselines

`tests/pipeline-baselines/` holds JSON snapshots of green runs on
main. Used to detect drift on quantitative invariants once I7 (token
budget) lands.

## Where this differs from regular `/tick-all`

- Runs against `bsg-stack-test-harness`, never on a productive repo.
- Resets state between runs.
- Synthetic backlog from `seed-test-backlog.sh` instead of real backlog.
- Asserts machine-readable pass/fail at the end.

## Adding a new invariant

1. Add the assertion to `assert-invariants.sh` (jq query against
   `prs.json` / `issues.json` in the log dir).
2. Document what regression it catches — link to the PR that
   introduced the fix it would have caught.
3. Run on the harness; commit the new baseline if it passes.

## Why this is allowed despite the "no CI cron" rule

`CLAUDE.md` forbids CI automation for productive agent runs (no
scheduled `/tick-all`, no `repo_dispatch` orchestrators). This
harness is a **test of the pipeline itself**, run on PRs that touch
the pipeline — closer to a unit test that needs to spawn processes.
A future workflow may gate it on `paths:` matching
`claude-skills/scripts/**`, `claude-skills/agents/**`,
`claude-skills/commands/tick-all.md`, or `.bsg-autopilot.yml`.

The exception is narrow: the harness never runs against a productive
repo. Productive ticks remain human-initiated.
