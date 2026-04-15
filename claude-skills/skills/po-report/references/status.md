# Status report workflow

Use this when the user asks for an overall project status, health check, or
"où en est le projet".

## Steps

1. **Run all aggregation scripts** in parallel (single message, multiple Bash
   tool calls):

   ```bash
   bash .claude/skills/po-report/scripts/status.sh
   bash .claude/skills/po-report/scripts/milestone-progress.sh
   bash .claude/skills/po-report/scripts/stale-issues.sh 14
   ```

2. **Compose the report** by piping the three JSON blobs into
   `generate-report.sh`, which produces a single markdown document:

   ```bash
   bash .claude/skills/po-report/scripts/generate-report.sh > po/reports/$(date +%F)-status.md
   ```

3. **Read back the file** with the Read tool and extract the executive summary
   for the chat response. Do not paste the whole report.

4. **Reply to the user** with:
   - Path to the file (`po/reports/YYYY-MM-DD-status.md`)
   - 3 bullet points: what's healthy, what's at risk, what needs a decision
   - Offer next actions (drill into a milestone, work a specific ticket, etc.)

## What to highlight in the executive summary

- Milestones < 50% complete with imminent dates
- Issues stale > 30 days (especially if assigned)
- PR queue depth and oldest open PR
- Unassigned high-priority labels (`bug`, `priority:high`, etc.)

## What NOT to do

- Do NOT post the report as a GitHub comment unless the user explicitly asks
- Do NOT delete or modify older reports in `po/reports/` — they're history
- Do NOT speculate about reasons for delays; report facts, the user provides context
