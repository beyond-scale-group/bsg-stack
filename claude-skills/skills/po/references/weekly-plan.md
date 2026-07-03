# Weekly task plan + Google Calendar daily blocks

Use this when the user has a `po/reports/<date>-weekly-plan-s<NN>.md` ready and
wants to **wire it into the week**: 5 calendar blocks (one per working day)
and/or batch-assign GitHub issues. Driven by `scripts/weekly-plan.sh`.

## Why it exists

`/po` is great at producing the markdown weekly plan, but every Monday the
PO still has to:

1. Decide manually which day = which task
2. Create 5 Google Calendar events by hand
3. Remember to put the repo name in every event title (this was forgotten
   on the first real run on `bsg-lbo` — all 5 events had to be patched)
4. Re-assign GitHub issues to the right milestone / owner

`weekly-plan.sh` collapses all four into one command.

## What it does

1. **Reads the snapshot** (`collect.sh` or `--snapshot`) and emits a JSON
   per-day breakdown for Mon→Fri.
2. **With `--calendar`**: creates (or patches, if same-prefix event exists)
   one Google Calendar event per working day via `gws calendar +insert`.
3. **With `--assign --user <login>`**: dry-runs the `gh issue edit
   --add-assignee` calls; `--yes` actually mutates.

## Invocation

```bash
# Just inspect the plan:
bash claude-skills/skills/po/scripts/weekly-plan.sh

# Pin the start day and slot, push to calendar:
bash claude-skills/skills/po/scripts/weekly-plan.sh \
  --calendar --start MON --slot 08:30-08:45

# Reuse a snapshot collected earlier:
bash claude-skills/skills/po/scripts/weekly-plan.sh \
  --snapshot /tmp/snap.json --start 2026-06-01

# Assign all cited issues to g-dumas (dry-run first!):
bash claude-skills/skills/po/scripts/weekly-plan.sh --assign --user g-dumas
bash claude-skills/skills/po/scripts/weekly-plan.sh --assign --user g-dumas --yes
```

## Flags

| Flag             | Default                                  | Notes                                          |
| ---------------- | ---------------------------------------- | ---------------------------------------------- |
| `--snapshot`     | _auto_ (`collect.sh`)                    | Path to a pre-collected snapshot.              |
| `--start`        | next Monday                              | `YYYY-MM-DD` or `MON`/`TUE`/...                |
| `--slot`         | `08:30-08:45`                            | `HH:MM-HH:MM`. Same slot every day.            |
| `--timezone`     | `Europe/Paris`                           | IANA tz.                                       |
| `--report`       | `po/reports/<today>-weekly-plan-s<NN>.md`| Cited inside the event description.            |
| `--calendar`     | off                                      | Push events.                                   |
| `--calendar-id`  | `primary`                                | Target calendar id.                            |
| `--assign`       | off                                      | Dry-run by default; add `--yes` to mutate.     |
| `--user`         | _required with --assign_                 | GitHub login to add as assignee.               |
| `--yes`          | off                                      | Required to actually mutate with `--assign`.   |

## Per-day heuristic

Issues are bucketed from their labels + state, then round-robin-assigned to a
narrow set of target days:

| Bucket             | Detected when…                                            | Target days |
| ------------------ | --------------------------------------------------------- | ----------- |
| `A_blocker`        | label in `{P0, blocker, urgent, go}`                      | Mon, Tue    |
| `B_in_progress`    | has assignee OR label in `{in-progress, wip}`             | Tue, Wed    |
| `C_outreach`       | label in `{outreach, cedant, cédant}`                     | Wed, Thu    |
| `D_sprint`         | label in `{P1, epic, sprint}`                             | Wed, Thu    |
| `Z_other`          | none of the above                                         | Mon→Thu     |
| PR review batch    | OPEN, non-draft, `reviewDecision != APPROVED`             | Fri         |

The day's `theme` is derived from the dominant bucket. Friday is reserved
for PR reviews regardless.

If your team uses different label conventions, edit the constant tables at
the top of the python block in `scripts/weekly-plan.sh`. No external
configuration file by design — labels rarely change.

## Output shape

```json
{
  "weekIso": "2026-W23",
  "repo": "beyond-scale-group/bsg-lbo",
  "repoShort": "bsg-lbo",
  "repoUrl": "https://github.com/beyond-scale-group/bsg-lbo",
  "reportPath": "po/reports/2026-06-01-weekly-plan-s23.md",
  "days": [
    {
      "date": "2026-06-01",
      "label": "Lun 1/6",
      "priority": "P0",
      "theme": "Débloquer P0 / urgences",
      "tasks": [
        {
          "issue": 181,
          "title": "Avocat LOI bloqué",
          "url": "https://github.com/.../issues/181",
          "action": "débloquer",
          "kind": "issue"
        }
      ]
    }
  ]
}
```

## Event format (mandatory)

Calendar events created by `--calendar` **always** include:

- **Title**: `[<repo-short>] PO Daily — <day> : <theme>` (e.g.
  `[bsg-lbo] PO Daily — Lun 1/6 : Débloquer P0 / urgences`)
- **Description** starts with the repo URL and the report reference:

  ```
  Repo: https://github.com/<owner>/<repo>
  Réf: po/reports/<today>-weekly-plan-s<NN>.md

  Tâches:
  - #181 — Avocat LOI bloqué (débloquer)
  - #132 — Envoyer LOI DIPOLE (débloquer)
  ```

The `[<repo-short>]` prefix is **non-negotiable** — multi-repo POs need to
see the project context at a glance in their calendar. This was the
real-world friction that motivated this script: the first manual run forgot
the repo prefix and all 5 events had to be patched the next morning.

## Idempotency

Before inserting, the script asks `gws calendar events list` for events
between `00:00` and `23:59` on the target date, filters by
`summary | startswith("[<repo-short>] PO Daily — <day>")`, and:

- **Match found** → `gws calendar events patch` (updates summary +
  description + start + end).
- **No match** → `gws calendar +insert`.

So re-running the same command on the same week is safe.

## `--assign` semantics

- Iterates over unique `issue` numbers in the plan.
- Skips an issue if `--user` is already in its assignees (no churn).
- **Dry-run by default**: prints the `gh issue edit` command it _would_ run
  to stderr.
- Add `--yes` to actually call `gh issue edit --add-assignee`.

> ⚠️ Milestone assignment is not yet implemented — `weekly-plan.sh` adds
> assignees only. The per-task milestone is preserved in the JSON output
> for callers that want to handle it themselves. If you need a one-shot
> milestone fix, drive it from the JSON:
>
> ```bash
> bash scripts/weekly-plan.sh | jq -r '.days[].tasks[].issue' \
>   | xargs -I{} gh issue edit {} --milestone 'Sprint 23'
> ```

## When to fall back to manual

- The plan calls for tasks that aren't open issues yet (just bullets in the
  markdown) — the script can't see them. Open issues first, then re-run.
- You want a custom slot per day (e.g. 08h30 Monday, 14h00 Friday). The
  script uses a single slot. Patch the events manually after.
- Cross-repo plans — out of scope, one repo per invocation.
