---
name: marketing-report
description: >
  Marketing audit toolkit for the current GitHub repository. Parses
  marketing/CALENDAR.md for scheduled items, enumerates recent releases
  and milestones via `gh`, scans landing pages and docs for marketing
  claims, and diffs shipped features against marketed features. Use
  when the user asks to "check marketing alignment", "audit content
  calendar", "generate campaign brief from milestone", or "find
  unmarketed releases". Scripts do the aggregation; the LLM narrates.
model: haiku
---

# Marketing Report

The marketing-audit skill for the **current repository**. Shipped as
the implementation layer behind the `@marketing` subagent.

## Intent routing

| If the user asks about...                                       | Read this reference          |
| --------------------------------------------------------------- | ---------------------------- |
| Content calendar, overdue items, upcoming posts                 | `references/calendar.md`     |
| Feature-marketing alignment (shipped vs marketed)               | `references/alignment.md`    |
| Auto-generated campaign briefs from milestones / releases       | `references/brief.md`        |
| Landing-page / README messaging audit                           | `references/messaging.md`    |

For a **full audit** run `generate-report.sh`.

## Hard rules

1. **Never invent releases, versions, or calendar items.** Every
   finding must come from a script's output.
2. **Always write the final report to `marketing/reports/YYYY-MM-DD-*.md`.**
3. **Run scripts from the repo root.** `gh` auto-detects the repo.
4. **CMS-hosted copy is out of scope.** The skill only sees source
   files in this repo (READMEs, docs/, landing templates). If the
   production site uses an external CMS, document that limitation
   in the report narrative.
5. **Bootstrap, don't overwrite.** If `marketing/CALENDAR.md` is
   missing, the first tick suggests a template — the user decides
   whether to commit it.
6. **Confirm before posting** to GitHub.

## Available scripts

All scripts live in `scripts/` and emit JSON on stdout (except
`generate-report.sh`, markdown). `collect.sh` is the single fetch;
reporters transform it.

| Script                | Purpose                                                                 |
| --------------------- | ----------------------------------------------------------------------- |
| `collect.sh`          | Parse `marketing/CALENDAR.md`, list recent releases (`gh release list`), list milestones (`gh api /repos/.../milestones`), glob landing pages and docs, scan README for feature claims. One snapshot → `/tmp/mkt-snap.json`. |
| `calendar.sh`         | Classify calendar items by status: overdue / today / upcoming / past-completed. |
| `alignment.sh`        | Join the release list × marketing-content scan, emit `unmarketed[]` (shipped without content) and `unshipped[]` (claimed on a landing page without a release). |
| `brief.sh`            | Auto-generate campaign brief stubs for unmarketed releases; detect stale briefs already on disk under `marketing/briefs/`. |
| `generate-report.sh`  | Collects once, runs every reporter, composes the full markdown audit. |

**Invocation patterns:**

```bash
# Full audit
bash scripts/generate-report.sh > marketing/reports/$(date +%F)-audit.md

# Reuse one snapshot
bash scripts/collect.sh > /tmp/mkt-snap.json
bash scripts/calendar.sh  --snapshot /tmp/mkt-snap.json
bash scripts/alignment.sh --snapshot /tmp/mkt-snap.json
bash scripts/brief.sh     --snapshot /tmp/mkt-snap.json
```

## Output convention

Reports go to `marketing/reports/`. Auto-generated briefs land under
`marketing/briefs/`:

```
marketing/reports/2026-04-20-audit.md
marketing/briefs/2026-04-20-v2.4.0-webhook-retry.md
```

## Tick action

Users invoke `tick` (typically via `@marketing tick` from `/loop` or
`/schedule`). It is **idempotent, repo-scoped, silent by default**
— BSG convention, see [`CLAUDE.md`][claude-md].

[claude-md]: https://github.com/beyond-scale-group/bsg-stack/blob/main/CLAUDE.md

### Steps

1. Generate the full audit:

   ```bash
   mkdir -p marketing/reports marketing/briefs
   bash ~/.claude/skills/marketing-report/scripts/generate-report.sh \
     > marketing/reports/$(date +%F)-audit.md
   ```

2. Land the report:

   ```bash
   bash ~/.claude/scripts/open-report-pr.sh \
     marketing/reports/$(date +%F)-audit.md \
     --agent marketing
   ```

3. Evaluate silence-breakers. Agent owns thresholds.

4. Reply with one-line receipt on clean, summary + PR URL otherwise.

### Silence is a feature

Do **not** pad the reply with "all aligned" narrative. Remediation
(writing copy, designing campaigns, launching ads) is **never**
part of `tick`.

---

## How to improve this skill

This file is a cached copy of `claude-skills/skills/marketing-report/SKILL.md` in
[beyond-scale-group/bsg-stack](https://github.com/beyond-scale-group/bsg-stack).
That repo is the single source of truth — `~/.claude/skills/marketing-report/SKILL.md` is
overwritten every time the BSG install flow runs.

If the user asks you to improve, fix, or extend this skill, do **not** edit
the local file. Instead:

1. `gh repo clone beyond-scale-group/bsg-stack` (or work in an existing clone)
2. Edit `claude-skills/skills/marketing-report/SKILL.md` on a feature branch
3. Open a pull request against `main`

Bug reports and ideas without a fix → open an issue on the same repo.
