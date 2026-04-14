# Trends workflow

Use this when the user asks about velocity, burndown, scope delta,
"are we speeding up / slowing down", or any longitudinal question
that needs data across multiple reporting runs.

The trend store is git history itself: every `po-manager` run commits
a `po/history/<date>.json` snapshot, so `trends.sh` just walks the
directory and diffs first-vs-last.

## Preconditions

- At least **2** committed history files in `po/history/` — one point
  is a snapshot, two or more is a trend. Fewer than 2 → trends.sh
  emits `velocity: null` and a single-series entry; report honestly.

## Steps

1. **Run `trends.sh`** (no snapshot arg needed — reads files directly):

   ```bash
   bash scripts/trends.sh                      # default: ./po/history/
   bash scripts/trends.sh --dir path/to/dir    # custom location
   ```

2. **Read the JSON** — top-level keys:

   | Key | Contents |
   |---|---|
   | `series` | One object per history file: `date`, `openIssues`, `closedIssues`, `openPrs`, `mergedPrs`, `milestones[]`. |
   | `velocity` | `issuesClosedPerWeek`, `prsMergedPerWeek`, `samplePoints`, `spanDays`. Null if < 2 samples. |
   | `latestChange` | Deltas from the first to last snapshot: `newIssuesSinceStart`, `newPrsSinceStart`, `closedSinceStart`, `mergedSinceStart`. |

3. **Narrate with a 3-point summary**:
   - Current velocity line ("closing X issues/week, merging Y PRs/week").
   - Scope delta since the first snapshot ("N new issues opened, M closed").
   - If `velocity.samplePoints >= 4`, compare the most recent week to the
     average — "pace dropped by 30% this week" is a signal worth surfacing.

4. **Do not extrapolate to the future** unless the user explicitly asks
   for a forecast. Report what happened, not what will.

## Why git history works as the trend store

- Snapshots are committed, so `git log po/history/` IS the audit trail.
- No extra database, server, or retention policy to manage.
- `git show <sha>:po/history/<date>.json` gives a verifiable point-in-time
  state — reproducible reports at any past date.
- Branching / reverting a commit also reverts the trend, matching the
  repo's actual history.

---

## How to improve this skill

This file is a cached copy of `claude-skills/skills/po-report/references/trends.md` in
[beyond-scale-group/bsg-stack](https://github.com/beyond-scale-group/bsg-stack).
That repo is the single source of truth — `~/.claude/skills/po-report/references/trends.md` is
overwritten every time the BSG install flow runs.

If the user asks you to improve, fix, or extend this skill, do **not** edit
the local file. Instead:

1. `gh repo clone beyond-scale-group/bsg-stack` (or work in an existing clone)
2. Edit `claude-skills/skills/po-report/references/trends.md` on a feature branch
3. Open a pull request against `main`

Bug reports and ideas without a fix → open an issue on the same repo.
