---
name: seo-report
description: >
  Technical-SEO audit toolkit for the current GitHub repository. Parses
  HTML / JSX / Vue / Svelte templates for title, meta description,
  canonical, Open Graph, and JSON-LD tags; builds an internal link
  graph and detects orphans / broken links; checks the sitemap.xml,
  robots.txt, and target-keyword coverage against `seo/KEYWORDS.md`.
  Use when the user asks to "audit SEO", "check meta tags", "find
  orphan pages", "verify sitemap", or "check keyword coverage". No
  external API calls — everything is source-at-rest.
---

# SEO Report

The technical-SEO audit skill for the **current repository**. Shipped
as the implementation layer behind the `@seo` subagent.

## Intent routing

| If the user asks about...                                         | Read this reference                |
| ----------------------------------------------------------------- | ---------------------------------- |
| Meta tags (title, description, canonical, Open Graph)             | `references/meta.md`               |
| Internal link graph, orphan pages, broken links                   | `references/links.md`              |
| Content coverage against target keywords                          | `references/content.md`            |
| Sitemap, robots.txt, canonical URL policy                         | `references/technical.md`          |
| Structured data (schema.org / JSON-LD)                            | `references/structured-data.md`    |

For a **full audit**, run `generate-report.sh`.

## Hard rules

1. **Never invent pages or URLs.** Every finding must come from a
   script's output.
2. **Always write the final report to `seo/reports/YYYY-MM-DD-*.md`**
   — dated and version-controllable.
3. **Source-at-rest by default.** The skill analyzes templates and
   static files in this repo and makes **no** network calls — unless
   the user explicitly opts in to production verification with
   `generate-report.sh --prod [url]`, which runs a bounded set of
   read-only `curl` probes (status codes, headers, rendered HTML) and
   appends a `## Production checks` section. Never probe production
   without the explicit `--prod` flag.
4. **Respect `.seoignore`** (gitignore-style) for marketing-only
   landing pages that legitimately lack some tags.
5. **Confirm before posting** to GitHub (issue comments, labels).

## Available scripts

All scripts live in `scripts/` and emit JSON on stdout (except
`generate-report.sh`, which emits markdown). `collect.sh` is the single
template fetch; reporters transform it.

| Script                | Purpose                                                                 |
| --------------------- | ----------------------------------------------------------------------- |
| `collect.sh`          | Enumerate HTML/JSX/Vue/Svelte/Astro pages, extract title / meta description / canonical / Open Graph / JSON-LD, parse sitemap and robots, build `<a href>` adjacency list, load `seo/KEYWORDS.md`. One snapshot → `/tmp/seo-snap.json`. |
| `meta.sh`             | Per-page presence of each required tag; emits `missingTitle[]`, `missingDescription[]`, `missingCanonical[]`. |
| `links.sh`            | Orphan detector + broken-link checker based on the adjacency list from `collect.sh`. |
| `content.sh`          | Keyword coverage: for each entry in `seo/KEYWORDS.md`, find pages mentioning it in title or H1; emit `uncoveredKeywords[]` for the gaps. |
| `technical.sh`        | Sitemap presence + page-coverage diff, robots.txt presence, canonical URL consistency. |
| `prod-check.sh`       | **Opt-in** (`--prod [url]`) live verification: sitemap/robots HTTP status, absolute canonicals, JSON-LD in rendered HTML, OG image reachability, GA4/Pixel presence, pillar-page status, www↔apex redirect code. Emits a markdown section. |
| `generate-report.sh`  | Collects once, runs every reporter, composes the full markdown audit. Pass `--prod [url]` to append `prod-check.sh` output. |

## Dependencies

`collect.sh` and `prod-check.sh` source the shared path resolver
`_bsg-paths.sh`, expected at **`<repo>/claude-skills/scripts/_bsg-paths.sh`**
— three levels up from this skill's `scripts/` dir. The skill must be
installed with that sibling `scripts/` tree intact; if the file is
missing, `collect.sh` exits 1 with an explicit error rather than
crashing mid-pipeline.

**Invocation patterns:**

```bash
# Full audit
bash scripts/generate-report.sh > seo/reports/$(date +%F)-audit.md

# Full audit + live production verification (opt-in)
bash scripts/generate-report.sh --prod https://www.the-shift.ai \
  > seo/reports/$(date +%F)-audit.md

# Reuse one snapshot
bash scripts/collect.sh > /tmp/seo-snap.json
bash scripts/meta.sh      --snapshot /tmp/seo-snap.json
bash scripts/links.sh     --snapshot /tmp/seo-snap.json
bash scripts/content.sh   --snapshot /tmp/seo-snap.json
bash scripts/technical.sh --snapshot /tmp/seo-snap.json
```

## Output convention

Reports go to `seo/reports/`. Filename patterns:

```
seo/reports/2026-04-20-audit.md   # full audit
seo/reports/2026-04-20-meta.md    # meta-only
seo/reports/2026-04-20-links.md   # link-graph
```

## Tick action

Users invoke `tick` (typically via `@seo tick` from `/loop` or
`/schedule`). It is **idempotent, repo-scoped, and silent by default**
— BSG-wide convention, see [`CLAUDE.md`][claude-md].

[claude-md]: https://github.com/beyond-scale-group/bsg-stack/blob/main/CLAUDE.md

### Steps

1. Generate the full audit:

   ```bash
   mkdir -p seo/reports
   bash ~/.claude/skills/seo-report/scripts/generate-report.sh \
     > seo/reports/$(date +%F)-audit.md
   ```

2. Land via the shared helper:

   ```bash
   bash ~/.claude/scripts/open-report-pr.sh \
     seo/reports/$(date +%F)-audit.md \
     --agent seo
   ```

3. Evaluate silence-breakers. The `@seo` agent owns thresholds.

4. Reply with a one-line receipt when clean, summary + PR URL
   otherwise.

### Silence is a feature

Do **not** pad the reply with "SEO looks good" narrative. One-line
receipts only. Remediation (writing meta tags, fixing links,
authoring content) is **never** part of `tick`.

---

## How to improve this skill

This file is a cached copy of `claude-skills/skills/seo-report/SKILL.md` in
[beyond-scale-group/bsg-stack](https://github.com/beyond-scale-group/bsg-stack).
That repo is the single source of truth — `~/.claude/skills/seo-report/SKILL.md` is
overwritten every time the BSG install flow runs.

If the user asks you to improve, fix, or extend this skill, do **not** edit
the local file. Instead:

1. `gh repo clone beyond-scale-group/bsg-stack` (or work in an existing clone)
2. Edit `claude-skills/skills/seo-report/SKILL.md` on a feature branch
3. Open a pull request against `main`

Bug reports and ideas without a fix → open an issue on the same repo.
