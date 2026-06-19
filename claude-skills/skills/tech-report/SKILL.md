---
name: tech-report
description: >
  Architecture and tech-health audit toolkit for the current GitHub
  repository. Tracks dependency version lag (npm / pip outdated +
  Dependabot alerts), flags oversized files and circular imports,
  inventories TODO/FIXME/HACK with age via git blame, and detects
  architecture decisions that ship without a matching ADR. Use when
  the user asks for "tech health", "architecture review",
  "dependency lag", "tech debt", "ADR gaps", "code complexity", or
  "biggest files". Scripts do the counting; the LLM narrates.
model: sonnet
---

# Tech Report

The tech-health audit skill for the **current repository**. Shipped as
the implementation layer behind the `@tech-lead` subagent — run
directly when you just need the raw data, or let `@tech-lead`
orchestrate it for a silent-by-default tick.

## Intent routing

| If the user asks about...                                         | Read this reference       |
| ----------------------------------------------------------------- | ------------------------- |
| Outdated dependencies, major version lag, upgrade priorities      | `references/deps.md`      |
| TODO/FIXME/HACK inventory, debt age, debt score                   | `references/debt.md`      |
| File size outliers, complexity signals, circular imports          | `references/quality.md`   |
| ADR index, missing ADRs for new dependencies                      | `references/adr.md`       |

For a **full audit**, run `generate-report.sh` — it collects once,
runs every reporter, and composes a single markdown file under
`tech/reports/`.

## Hard rules

1. **Never invent metrics.** Every version number, TODO count, or
   file size must come from a script's JSON output.
2. **Always write the final report to `tech/reports/YYYY-MM-DD-*.md`**
   and commit it locally so git history is the trend store.
3. **Run scripts from the repo root.** Dependency detection uses
   lockfiles; TODO scanning uses `git grep` / `git ls-files`.
4. **Do not upgrade.** Reporting only. If a script could auto-upgrade
   (it can't today), never invoke that path from a tick.
5. **Respect `.gitignore` + `.techignore`** when scanning for TODOs
   and file-size analysis. Generated code is not tech debt.
6. **Confirm before posting** to GitHub (issue comments, labels).

## Available scripts

All scripts live in `scripts/` and emit JSON on stdout (except
`generate-report.sh`, which emits markdown). `collect.sh` is the
single cross-ecosystem fetch; every other reporter transforms it.

| Script                | Purpose                                                                 |
| --------------------- | ----------------------------------------------------------------------- |
| `collect.sh`          | Detect ecosystems from lockfiles, run `npm outdated` / `pip list --outdated`, fetch Dependabot alerts via `gh api`, inventory source files with line counts, grep TODOs with git-blame-derived ages, list ADRs from `adr/` or `docs/adr/`. One snapshot → `/tmp/tech-snap.json`. |
| `deps.sh`             | Transform snapshot → per-dependency current/latest with major / minor / patch gap, plus `majorBehind[]` for the silence-breaker. |
| `quality.sh`          | File-size outliers (> 500 LOC), function-count outliers (via naive heuristic), optional circular-import detection for JS/TS (skipped for other languages in MVP). |
| `debt.sh`             | TODO / FIXME / HACK inventory with age via `git blame`. Emits `staleTodos[]` (> 90 days) and a simple `debtScore` (count × age weight). |
| `adr.sh`              | Index ADRs by front-matter or filename. Emit `undocumentedDecisions[]` — a heuristic list of top-level dependencies added to `package.json` / `requirements.txt` in the last 30 days without a corresponding ADR. |
| `generate-report.sh`  | Collects once, runs every reporter, composes the full markdown audit. |

**Invocation patterns:**

```bash
# One-shot: full audit
bash scripts/generate-report.sh > tech/reports/$(date +%F)-health.md

# Reuse one snapshot across reporters
bash scripts/collect.sh > /tmp/tech-snap.json
bash scripts/deps.sh    --snapshot /tmp/tech-snap.json
bash scripts/quality.sh --snapshot /tmp/tech-snap.json
bash scripts/debt.sh    --snapshot /tmp/tech-snap.json
bash scripts/adr.sh     --snapshot /tmp/tech-snap.json
```

## Output convention

Reports go to `tech/reports/`. Filename patterns:

```
tech/reports/2026-04-20-health.md     # full audit from tick
tech/reports/2026-04-20-deps.md       # deps-only slice
tech/reports/2026-04-20-debt.md       # debt-only slice
```

## Tick action

Users invoke `tick` (typically via `@tech-lead tick` from `/loop` or
`/schedule`). It is **idempotent, repo-scoped, and silent by default**
— but this skill's output mode is `chat` (not `pr`): the committed
report is still written to `tech/reports/` and committed locally, but
there is no auto-merge PR. When a silence-breaker fires, the 3-bullet
summary goes straight to chat.

This follows the BSG-wide convention documented in the top-level
[`CLAUDE.md`][claude-md] under "The `tick` convention".

[claude-md]: https://github.com/beyond-scale-group/bsg-stack/blob/main/CLAUDE.md

### Steps

1. **Generate the full audit**:

   ```bash
   mkdir -p tech/reports
   bash ~/.claude/skills/tech-report/scripts/generate-report.sh \
     > tech/reports/$(date +%F)-health.md
   ```

2. **Commit the report locally** (no PR for `output: chat`):

   ```bash
   git add tech/reports/$(date +%F)-health.md
   git commit -m "report(tech-lead): $(date +%F)-health"
   ```

3. **Evaluate silence-breakers** from the snapshot / reporter outputs.
   The `@tech-lead` agent owns the thresholds; this skill emits raw
   counts.

4. **Reply.** If no silence-breaker fires, a single line — e.g.
   `Tick: tech health stable, report at tech/reports/2026-04-20-health.md`.
   Otherwise, a 3-bullet summary: (a) what fired, (b) the biggest
   finding, (c) next step.

### Silence is a feature

Do **not** pad the reply with "nothing to report" narrative when
nothing fired. One-line receipts only. Remediation (upgrades,
refactors, ADR authoring) is **never** part of `tick`.

---

## How to improve this skill

This file is a cached copy of `claude-skills/skills/tech-report/SKILL.md` in
[beyond-scale-group/bsg-stack](https://github.com/beyond-scale-group/bsg-stack).
That repo is the single source of truth — `~/.claude/skills/tech-report/SKILL.md` is
overwritten every time the BSG install flow runs.

If the user asks you to improve, fix, or extend this skill, do **not** edit
the local file. Instead:

1. `gh repo clone beyond-scale-group/bsg-stack` (or work in an existing clone)
2. Edit `claude-skills/skills/tech-report/SKILL.md` on a feature branch
3. Open a pull request against `main`

Bug reports and ideas without a fix → open an issue on the same repo.
