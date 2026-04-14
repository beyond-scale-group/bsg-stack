# Milestone progress workflow

Use this when the user asks about milestone progress, sprint health, or
burndown for a specific milestone.

## Steps

1. **List milestones with progress**:

   ```bash
   bash .claude/skills/po-report/scripts/milestone-progress.sh
   ```

   This outputs JSON with: `title`, `state`, `due_on`, `open_issues`,
   `closed_issues`, `percent_complete`, `url`.

2. **If the user named a specific milestone**, filter the JSON to that one
   and fetch its issues for detail:

   ```bash
   gh issue list --milestone "<TITLE>" --state all \
     --json number,title,state,assignees,labels,updatedAt --limit 200
   ```

3. **Build a milestone report** at `po/reports/$(date +%F)-milestone-<slug>.md`
   containing:
   - Header: title, due date, % complete, days remaining
   - Burndown table: open vs closed by label
   - Open issues grouped by assignee (unassigned first)
   - Risk flags: stale > 14d, no assignee, blocked label

4. **Reply to the user** with the file path + a 3-line summary.

## Risk flags to compute

| Flag           | Condition                                                  |
| -------------- | ---------------------------------------------------------- |
| At risk        | `percent_complete < 50` AND `due_on` within 7 days         |
| Overdue        | `due_on < today` AND `state == open`                       |
| Understaffed   | `open_issues > 5` AND > 50% unassigned                     |
| Stalled        | No issue closed in the last 7 days                         |

## Note on dates

Always parse dates with `date -d` or `gdate -d` (BSD date on macOS does not
support `-d`). Prefer `python3 -c 'from datetime import...'` for portability.
