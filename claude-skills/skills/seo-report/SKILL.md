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
model: haiku
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
3. **Source-at-rest by default.** No `curl`/`wget` against production
   unless the operator explicitly opts in with `generate-report.sh
   --prod`. The default audit analyzes templates and static files in
   this repo only; `--prod` adds a clearly-labelled, read-only
   `## Production checks` section (see "Production checks" below).
4. **Respect `.seoignore`** (gitignore-style) for marketing-only
   landing pages that legitimately lack some tags.
5. **Confirm before posting** to GitHub (issue comments, labels).

## Available scripts

All scripts live in `scripts/` and emit JSON on stdout (except
`generate-report.sh` and `init-keywords.sh`, which emit markdown).
`collect.sh` is the single template fetch; reporters transform it.

| Script                | Purpose                                                                 |
| --------------------- | ----------------------------------------------------------------------- |
| `collect.sh`          | Enumerate HTML/JSX/Vue/Svelte/Astro pages, extract title / meta description / canonical / Open Graph / JSON-LD, parse sitemap and robots, build `<a href>` adjacency list, load `seo/KEYWORDS.md`. One snapshot → `/tmp/seo-snap.json`. |
| `meta.sh`             | Per-page presence of each required tag; emits `missingTitle[]`, `missingDescription[]`, `missingCanonical[]`. |
| `links.sh`            | Orphan detector + broken-link checker based on the adjacency list from `collect.sh`. |
| `content.sh`          | Keyword coverage: for each entry in `seo/KEYWORDS.md`, find pages mentioning it in title or H1; emit `uncoveredKeywords[]` for the gaps. |
| `technical.sh`        | Sitemap presence + page-coverage diff, robots.txt presence, canonical URL consistency. |
| `generate-report.sh`  | Collects once, runs every reporter, composes the full markdown audit. Accepts `--prod [url]` to append production checks. |
| `prod-checks.sh`      | Opt-in. Read-only HTTP probes against the live site (sitemap/robots status, canonical absoluteness, JSON-LD types, OG image reachability, GA4/Pixel presence, pillar-page status, www-vs-apex redirect code). Emits a `## Production checks` markdown section. Always exits 0. |
| `init-keywords.sh`    | Bootstrap SEO audit target keywords by scanning repo metadata (GitHub topics, package.json keywords), README headings, and `docs/`. Emits `.bsg/KEYWORDS.md` draft to stdout for human review. Part of #237 per-agent `--init` contract. |

**Invocation patterns:**

```bash
# Full audit (source-at-rest only)
bash scripts/generate-report.sh > seo/reports/$(date +%F)-audit.md

# Full audit + production verification
bash scripts/generate-report.sh --prod https://www.the-shift.ai \
  > seo/reports/$(date +%F)-audit.md

# Bootstrap KEYWORDS.md (new repo onboarding)
bash scripts/init-keywords.sh > /tmp/keywords-draft.md
# Review the draft, then commit to .bsg/KEYWORDS.md:
# cat /tmp/keywords-draft.md > .bsg/KEYWORDS.md
# git add .bsg/KEYWORDS.md && git commit -m "feat(seo): initialize keyword targets"

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

## Runtime layout

Every collector sources the shared BSG path resolver to locate
`KEYWORDS.md` (`.bsg/KEYWORDS.md` preferred, legacy `seo/KEYWORDS.md`
fallback, per ADR-001). The resolver is **not** part of this skill
directory — it lives three levels up:

```
<skills-root>/
├── scripts/_bsg-paths.sh          ← resolver (REQUIRED)
└── skills/seo-report/scripts/collect.sh   ← sources ../../../scripts/_bsg-paths.sh
```

When the skill is installed standalone (e.g. the Donna bucket on Clever
Cloud) the resolver must be vendored alongside it at that relative
path. If it is missing, `collect.sh` now fails fast with an explicit
`ERROR: _bsg-paths.sh not found at <path>` instead of crashing
silently.

## Production checks

Source-at-rest analysis cannot validate a live deployment (missing env
vars, 404 OG image, 307-vs-301 host redirects, JSON-LD stripped at
build, analytics that never shipped). `generate-report.sh --prod`
appends a read-only `## Production checks` section.

URL resolution order: `--prod <url>` arg → `SEO_SITE_URL` →
`SITE_URL` → `site_url:` in `AUTOPILOT.yml`. If none resolve, the
section reports "skipped" rather than failing the audit.

Checks: sitemap/robots HTTP status (+ URL count, `Sitemap:` presence),
canonical absoluteness on homepage + 2 sampled internal pages, JSON-LD
`@type`s in rendered HTML, OG image reachability, GA4/Meta-Pixel
presence, pillar-page status codes, and www-vs-apex redirect (expects
301). `prod-checks.sh` always exits 0 so a flaky network never aborts
`tick`.

## Init action

The `--init` action (invoked by `@seo --init` when the BSG task router
supports it; see #237) scans the current repository for SEO seed signals
and generates a draft `.bsg/KEYWORDS.md` file ready for human review and
commitment. Run once at project startup to establish the keyword target
baseline.

**Signals scanned:**

- **GitHub repo metadata**: Description, topics (via `gh repo view`)
- **README.md**: H1/H2 headings, first 10 extracted
- **package.json**: `keywords` field if present
- **Deduped and sorted** by frequency, limited to ~25 terms

**Output:** Draft `.bsg/KEYWORDS.md` on stdout, seeded with signal
keywords and ready for editing (deduping, prioritization, hand-authoring
of domain-specific terms). Opened as PR for human review.

**Example:**

```bash
# Generate the draft
bash scripts/init-keywords.sh > /tmp/keywords-draft.md

# Review it
cat /tmp/keywords-draft.md

# Commit if happy
mkdir -p .bsg
cp /tmp/keywords-draft.md .bsg/KEYWORDS.md
git add .bsg/KEYWORDS.md
git commit -m "feat(seo): initialize keyword targets from repo signals"
```

For cross-repo init (via `--repo OWNER/NAME`), the script uses `gh`
API authentication and adapts its signals accordingly.

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
