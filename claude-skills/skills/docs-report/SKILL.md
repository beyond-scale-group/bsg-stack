---
name: docs-report
description: >
  Documentation health audit toolkit for the current GitHub repository.
  Walks tracked markdown — README.md (root and subprojects),
  CHANGELOG.md, and `.bsg/` flat docs — to find broken links, dead file
  references, README commands that no longer exist in `package.json` /
  `Makefile`, and tagged releases missing from CHANGELOG. Scripts do
  the aggregation; the LLM narrates. ADRs under `.bsg/adr/` are read-only
  in this skill — they belong to `tech-report`.
model: haiku
---

# Docs Report

The documentation health skill for the **current repository**. Shipped
as the implementation layer behind the `@docs-keeper` subagent — run
directly when you just need the raw data, or let `@docs-keeper`
orchestrate it for a silent-by-default tick.

## Intent routing

| If the user asks about...                                         | Read this reference         |
| ----------------------------------------------------------------- | --------------------------- |
| Broken markdown links, dead file references                       | `references/links.md`       |
| Stale README commands (`npm run X` where X no longer exists)      | `references/commands.md`    |
| CHANGELOG gaps for tagged releases                                | `references/changelog.md`   |
| `.bsg/` cross-doc references, freshness                           | `references/bsg-docs.md`    |

For a **full audit**, run `generate-report.sh` — it collects once,
runs every reporter, and composes a single markdown file under
`docs-keeper/reports/`.

## Hard rules

1. **Never invent paths.** Every dead reference, missing tag, or stale
   command must come from a script's JSON output.
2. **Always write the final report to
   `docs-keeper/reports/YYYY-MM-DD-audit.md`** and land it via
   `claude-skills/scripts/open-report-pr.sh --agent docs-keeper`.
3. **Run scripts from the repo root.** Discovery uses `git ls-files`
   so untracked drafts are ignored.
4. **Do not rewrite prose.** Mechanical fixes only — broken link
   targets, renamed command names, append-only CHANGELOG entries. Prose
   rewrites are a human authoring task.
5. **ADRs are read-only.** `.bsg/adr/` is owned by tech-report. The
   docs-report scripts read ADR files only to detect cross-doc
   contradictions; they never edit them.
6. **Respect `.gitignore`.** Generated docs (auto-API references,
   `site/`, `_build/`) are not in scope.

## Available scripts

All scripts live in `scripts/` and emit JSON on stdout (except
`generate-report.sh`, which emits markdown). `collect.sh` is the
single discovery pass; every other reporter transforms it.

| Script                | Purpose                                                                 |
| --------------------- | ----------------------------------------------------------------------- |
| `collect.sh`          | Discover tracked markdown via `git ls-files '*.md'`, classify each as README / CHANGELOG / `.bsg/*` / other, extract inline markdown links, list git tags, parse `package.json` scripts and `Makefile` targets. Single snapshot → `/tmp/docs-snap.json`. |
| `links.sh`            | Transform snapshot → `brokenLinks[]` — every relative-path link whose target does not exist on disk. HTTP/HTTPS/mailto are out of scope. |
| `commands.sh`         | Scan README content for `npm run <X>`, `pnpm <X>`, `yarn <X>`, `make <X>` patterns. Emit `staleCommands[]` for any X not present in `packageScripts[]` / `makefileTargets[]`. |
| `changelog.sh`        | Parse CHANGELOG.md heading lines for version tags. Compare against `git tag --list`. Emit `missingTags[]`. |
| `bsg-docs.sh`         | Walk `.bsg/*.md` (excluding `.bsg/adr/`), extract path-like tokens, check each for existence. Emit `deadReferences[]` and (best-effort) `contradictions[]` when two docs reference the same path with conflicting "should" statements. |
| `generate-report.sh`  | Collects once, runs every reporter, composes the full markdown audit with a `<!-- fingerprint: ... -->` header so `tick-fingerprint.sh` can short-circuit unchanged ticks. |

**Invocation patterns:**

```bash
# One-shot: full audit
bash scripts/generate-report.sh > docs-keeper/reports/$(date +%F)-audit.md

# Reuse one snapshot across reporters
bash scripts/collect.sh > /tmp/docs-snap.json
bash scripts/links.sh    --snapshot /tmp/docs-snap.json
bash scripts/commands.sh --snapshot /tmp/docs-snap.json
bash scripts/changelog.sh --snapshot /tmp/docs-snap.json
bash scripts/bsg-docs.sh  --snapshot /tmp/docs-snap.json
```

## Output convention

Reports go to `docs-keeper/reports/`. Filename patterns:

```
docs-keeper/reports/2026-04-20-audit.md       # full audit from tick
docs-keeper/reports/2026-04-20-links.md       # links-only slice
docs-keeper/reports/2026-04-20-changelog.md   # changelog-only slice
```

## Tick action

Users invoke `tick` (typically via `@docs-keeper tick` from `/loop` or
`/schedule`). It is **idempotent, repo-scoped, and silent by default**.
The agent owns the silence-breaker thresholds; this skill emits raw
counts. See the top-level [`CLAUDE.md`][claude-md] → "The `tick`
convention" for the BSG-wide semantics.

[claude-md]: https://github.com/beyond-scale-group/bsg-stack/blob/main/CLAUDE.md

### Steps

1. **Generate the full audit:**

   ```bash
   mkdir -p docs-keeper/reports
   bash ~/.claude/skills/docs-report/scripts/generate-report.sh \
     > docs-keeper/reports/$(date +%F)-audit.md
   ```

2. **Land via the helper** (output: commit agent, but the audit
   report itself rides through `open-report-pr.sh`):

   ```bash
   PR_URL=$(bash claude-skills/scripts/open-report-pr.sh \
     docs-keeper/reports/$(date +%F)-audit.md \
     --agent docs-keeper --require-pilot)
   ```

3. **Evaluate silence-breakers** from the snapshot / reporter outputs.
   The `@docs-keeper` agent owns the thresholds; this skill emits raw
   counts.

4. **Reply.** One-line receipt with the PR URL plus the pilot outcome.

### Silence is a feature

Do **not** pad the reply with "nothing to report" narrative when
nothing fired. One-line receipts only. Prose rewriting is **never**
part of `tick`.

---

## How to improve this skill

This file is a cached copy of `claude-skills/skills/docs-report/SKILL.md` in
[beyond-scale-group/bsg-stack](https://github.com/beyond-scale-group/bsg-stack).
That repo is the single source of truth — `~/.claude/skills/docs-report/SKILL.md` is
overwritten every time the BSG install flow runs.

If the user asks you to improve, fix, or extend this skill, do **not** edit
the local file. Instead:

1. `gh repo clone beyond-scale-group/bsg-stack` (or work in an existing clone)
2. Edit `claude-skills/skills/docs-report/SKILL.md` on a feature branch
3. Open a pull request against `main`

Bug reports and ideas without a fix → open an issue on the same repo.
