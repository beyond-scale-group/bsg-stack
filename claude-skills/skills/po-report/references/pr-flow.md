# PR flow workflow

Use this when the user asks about PR health, review latency, merge
queue depth, throughput, or "why are PRs piling up".

## Steps

1. **Run `pr-flow.sh`** (consumes a collect.sh snapshot — pass
   `--snapshot <path>` or pipe, otherwise it auto-collects):

   ```bash
   bash scripts/pr-flow.sh --snapshot /tmp/snap.json
   ```

2. **Read the JSON** — six top-level keys:

   | Key | Contents |
   |---|---|
   | `reviewLatencyHours` | `p50`, `p90`, `max`, `sampleSize` — time from PR open → first review, across merged PRs. |
   | `openPrs` | `total`, `drafts`, `awaitingReview`, `failingChecks`, `withMergeConflicts`, `ageBuckets` (`le1d`/`le7d`/`le30d`/`gt30d`), `oldest`. |
   | `reviewerLoad` | Top 5 reviewers with the most pending reviews. |
   | `mergeQueue` | `depth` + per-entry `{number, title, mergeStateStatus}` for PRs that are BLOCKED or UNSTABLE. |
   | `throughput` | `mergedLast30d`, `mergedPerWeek`. |

3. **Surface the top signals** in the chat reply:
   - If `reviewLatencyHours.p90 > 72` → "reviews are slow, p90 is 3+ days"
   - If `openPrs.ageBuckets.gt30d > 0` → "N PRs older than a month, triage needed"
   - If `openPrs.failingChecks > openPrs.total / 2` → "majority of open PRs have failing checks"
   - If `mergeQueue.depth > 0` → list blocked/unstable PRs

4. **Never auto-act.** Don't request reviews, dismiss reviews, or add
   reviewers without explicit user confirmation.

---

## How to improve this skill

This file is a cached copy of `claude-skills/skills/po-report/references/pr-flow.md` in
[beyond-scale-group/bsg-stack](https://github.com/beyond-scale-group/bsg-stack).
That repo is the single source of truth — `~/.claude/skills/po-report/references/pr-flow.md` is
overwritten every time the BSG install flow runs.

If the user asks you to improve, fix, or extend this skill, do **not** edit
the local file. Instead:

1. `gh repo clone beyond-scale-group/bsg-stack` (or work in an existing clone)
2. Edit `claude-skills/skills/po-report/references/pr-flow.md` on a feature branch
3. Open a pull request against `main`

Bug reports and ideas without a fix → open an issue on the same repo.
