# Stale issues workflow

Use this when the user asks about stale issues, abandoned work, or issues
without recent activity.

## Steps

1. **Run the stale detector** with the desired threshold (default 14 days):

   ```bash
   bash .claude/skills/po-report/scripts/stale-issues.sh 14
   # or for a stricter threshold
   bash .claude/skills/po-report/scripts/stale-issues.sh 30
   ```

   Output is JSON: `[{number, title, assignees, labels, updatedAt, daysStale, url}, ...]`.

2. **Bucket the results**:
   - **Critical**: `priority:high` or `bug` label, stale > 14d
   - **Assigned but stale**: has assignee, stale > N days
   - **Orphaned**: no assignee, any age beyond threshold

3. **Write the report** to `.claude/reports/$(date +%F)-stale.md`.

4. **In chat**, surface:
   - Total count per bucket
   - Top 3 critical (by `daysStale` descending)
   - Suggest next actions: ping assignees, close as `not planned`, re-triage

## Do NOT

- Do NOT close or comment on stale issues automatically. The user decides.
- Do NOT consider an issue stale just by `createdAt` — use `updatedAt` which
  reflects the last comment, label change, or assignment.
