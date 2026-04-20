---
name: pr-comms-report
description: >
  PR / communications toolkit for the current GitHub repository.
  Classifies releases, milestones, and contributor events by
  newsworthiness; drafts press-release stubs for unannounced major
  events; audits `comms/press-kit/` freshness; tracks `comms/ANNOUNCED.md`
  to avoid re-drafting. Use when the user asks to "find newsworthy
  events", "draft a press release", "check press-kit freshness", or
  "plan the announcement schedule". No external API calls.
---

# PR / Comms Report

The communications audit skill for the **current repository**.
Shipped as the implementation layer behind the `@pr-comms` subagent.

## Intent routing

| If the user asks about...                                        | Read this reference              |
| ---------------------------------------------------------------- | -------------------------------- |
| Press release structure, drafting conventions                    | `references/press-release.md`    |
| Press kit files, freshness audit, boilerplate                    | `references/press-kit.md`        |
| Event classification (major / minor / patch / milestone / etc.)  | `references/events.md`           |
| Communication plan / scheduling across events                    | `references/plan.md`             |

For a **full audit** run `generate-report.sh`.

## Hard rules

1. **Never invent releases, quotes, or customer stories.** Every
   output comes from either a script's output or explicit
   placeholder text for human completion.
2. **Always write the final report to `comms/reports/YYYY-MM-DD-*.md`.**
3. **Run scripts from the repo root.** `gh` auto-detects.
4. **Never draft a security-incident response.** The events reporter
   flags security advisories; crisis messaging is a human judgement
   call.
5. **Respect `comms/ANNOUNCED.md`** — a release with an entry there
   is not unannounced. If the file doesn't exist, fall back to
   press-kit commit history as a "has-been-announced" proxy.
6. **Confirm before posting** to GitHub (issue comments, labels).

## Available scripts

| Script                | Purpose                                                                 |
| --------------------- | ----------------------------------------------------------------------- |
| `collect.sh`          | List releases (`gh release list`), closed milestones, security advisories (`gh api /repos/.../security-advisories`), press-kit inventory (mtime + git log), `comms/ANNOUNCED.md` entries, contributor counts via `git shortlog`. One snapshot → `/tmp/comms-snap.json`. |
| `events.sh`           | Classify events by newsworthiness: unannounced major/minor releases, unannounced milestone closures, security advisories, community milestones (100th / 500th / 1000th contributor or PR). |
| `press-kit.sh`        | Per-file age audit of `comms/press-kit/`; `staleAssets[]` for anything > 90 days old. |
| `draft.sh`            | Plan mode by default; with `--write`, materialize press-release stubs under `comms/press-releases/` for each unannounced major/minor release. |
| `generate-report.sh`  | Collects once, runs every reporter, composes the full markdown audit. |

**Invocation patterns:**

```bash
# Full audit
bash scripts/generate-report.sh > comms/reports/$(date +%F)-events.md

# Reuse one snapshot
bash scripts/collect.sh > /tmp/comms-snap.json
bash scripts/events.sh    --snapshot /tmp/comms-snap.json
bash scripts/press-kit.sh --snapshot /tmp/comms-snap.json
bash scripts/draft.sh     --snapshot /tmp/comms-snap.json

# Actually write the draft stubs
bash scripts/draft.sh --snapshot /tmp/comms-snap.json --write
```

## Output convention

Reports go to `comms/reports/`. Press-release drafts go to
`comms/press-releases/`:

```
comms/reports/2026-04-20-events.md
comms/press-releases/2026-04-20-v2.4.0-webhook-retry.md
```

Private repos get a "CONFIDENTIAL — review before publishing" header
in every draft.

## Tick action

Users invoke `tick` (via `@pr-comms tick` from `/loop` or
`/schedule`). It is **idempotent, repo-scoped, silent by default** —
BSG convention, see [`CLAUDE.md`][claude-md].

[claude-md]: https://github.com/beyond-scale-group/bsg-stack/blob/main/CLAUDE.md

### Steps

1. Generate the full audit:

   ```bash
   mkdir -p comms/reports comms/press-releases
   bash ~/.claude/skills/pr-comms-report/scripts/generate-report.sh \
     > comms/reports/$(date +%F)-events.md
   ```

2. Land the report:

   ```bash
   bash ~/.claude/scripts/open-report-pr.sh \
     comms/reports/$(date +%F)-events.md \
     --agent pr-comms
   ```

3. Evaluate silence-breakers. Agent owns thresholds.

4. Reply with a one-line receipt when clean, a summary + PR URL when
   something fires.

### Silence is a feature

Do **not** pad the reply with "no newsworthy events" narrative. The
committed report is the audit trail. Publishing press releases,
updating the press kit, and contacting media are **never** part of
`tick`.

---

## How to improve this skill

This file is a cached copy of `claude-skills/skills/pr-comms-report/SKILL.md` in
[beyond-scale-group/bsg-stack](https://github.com/beyond-scale-group/bsg-stack).
That repo is the single source of truth — `~/.claude/skills/pr-comms-report/SKILL.md` is
overwritten every time the BSG install flow runs.

If the user asks you to improve, fix, or extend this skill, do **not** edit
the local file. Instead:

1. `gh repo clone beyond-scale-group/bsg-stack` (or work in an existing clone)
2. Edit `claude-skills/skills/pr-comms-report/SKILL.md` on a feature branch
3. Open a pull request against `main`

Bug reports and ideas without a fix → open an issue on the same repo.
