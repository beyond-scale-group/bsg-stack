# PRD-008: md-to-office Skill

**Status:** Draft
**Author:** Guillaume Badin
**Date:** 2026-04-24
**Priority:** P3 — Phase 5

---

## 1. Problem Statement

Every BSG-scoped repo produces markdown artifacts — PO reports, security
audits, press releases, campaign briefs, technical notes. When these need
to leave the repo (board deck, partner deliverable, client-facing Word
doc, financial model), someone manually copies the markdown into Word,
PowerPoint, or Excel and re-applies the team's brand by hand. The result
is slow, inconsistent, and detached from the source of truth: the brand
lives in a shared drive somewhere, the markdown lives in git, and the two
drift.

Anthropic ships official `document-skills` (docx/pptx/xlsx/pdf) in
[`anthropics/skills`](https://github.com/anthropics/skills), but they are
brand-agnostic and do not know about BSG's per-repo brand conventions.
Each repo has its own brand (colors, logo, typography, footer, legal),
and that brand must flow automatically into every generated artifact.

## 2. Goal

Provide a BSG-catalogued Claude Code skill that converts a markdown file
(or directory) into a **brand-aligned** DOCX / PPTX / XLSX, by picking up
Office templates that live **inside the target repo** under a canonical
path (`brand/templates/`). The skill ships zero binaries — it only
provides the rendering pipeline and the discovery convention.

## 3. Non-Goals

- **No hosted brand registry.** Each repo owns its templates; no central
  download server, no BSG-wide default deck.
- **No LLM rendering at runtime.** All conversion is deterministic
  (pandoc + python-pptx + openpyxl). The LLM orchestrates, never draws.
- **No PDF generation.** Covered by the official Anthropic `pdf` skill
  and by out-of-band pipelines like `./pdf` scripts in bsg-lbo-dipole.
- **No two-way sync.** DOCX/PPTX/XLSX → markdown is out of scope; use the
  official Anthropic skills for that direction.
- **No automatic commit of artifacts.** Generated binaries are placed
  next to the source markdown; committing them is the user's choice.
- **No brand authoring.** The skill consumes templates; it does not
  create or validate them. A `--init` helper scaffolds placeholder
  templates so a repo can start from scratch, but the actual brand work
  is manual (Word / PowerPoint / Excel).

## 4. User Stories

| # | As a… | I want to… | So that… |
|---|-------|-----------|----------|
| P1 | PO | Run `md-to-office.sh po/reports/2026-04-24-status.md` | I hand the board a branded .docx in 2 seconds |
| P2 | Comms lead | Convert a press-release markdown to DOCX with our logo | Journalists get a document, not a .md link |
| P3 | Tech lead | Turn an ADR into PPTX with layouts | I can present it in a design review |
| P4 | Marketing | Export a campaign brief as Excel | The media team can fill costs per channel |
| P5 | Any dev | Run the skill in a repo with no `brand/templates/` | I get an unbranded output with a clear warning, not an error |
| P6 | New repo owner | Run `md-to-office.sh --init` | I get placeholder templates to customize |

## 5. Skill Design

### 5.1 Frontmatter

```yaml
---
name: md-to-office
description: >
  Convert a markdown file into a brand-aligned Office document (DOCX /
  PPTX / XLSX) using Office templates that live inside the current repo
  at brand/templates/. Wraps pandoc + python-pptx + openpyxl; ships no
  binaries of its own. Use when the user asks to "turn this md into a
  Word doc", "make a deck from this markdown", "export as Excel", or
  "génère un rapport Word / PowerPoint / Excel à partir de ce .md".
version: 0.1.0
output: chat
auto-implements: []
never-auto-implements: []
---
```

`output: chat` — the skill produces a binary artifact next to the source
markdown, not a markdown report that would land in a report PR.

### 5.2 Routing Table

| User intent | Action |
|---|---|
| "convert to Word", "turn md into docx", "génère un Word" | `md-to-office.sh <file> --target docx` |
| "make a deck", "export to PowerPoint", "crée une présentation" | `md-to-office.sh <file> --target pptx` |
| "export as Excel", "turn the tables into xlsx" | `md-to-office.sh <file> --target xlsx` |
| (no target specified) | `md-to-office.sh <file>` → auto-detect (see §5.5) |
| "bootstrap templates", "init brand templates" | `md-to-office.sh --init` |

### 5.3 Template Discovery

`resolve-template.sh <target>` walks the following chain and stops at the
first hit:

| Priority | Location | Use case |
|---|---|---|
| 1 | `--template <path>` CLI flag | Explicit override |
| 2 | `$BSG_BRAND_TEMPLATES/<target>.{docx,pptx,xlsx}` | Tests, CI |
| 3 | `./brand/templates/<target>.{docx,pptx,xlsx}` | Canonical per-repo convention |
| 4 | `./brand/templates/reference.docx` (legacy pandoc alias) | Back-compat |
| 5 | (none) | Fall back to unbranded rendering + `⚠️` warning |

Level 5 is a **successful non-branded rendering**, not an error: the
skill must work in a fresh repo that has no `brand/` directory.

### 5.4 Rendering Pipeline

| Target | Engine | Notes |
|---|---|---|
| DOCX | `pandoc --reference-doc=<template>.docx` | Styles injected via pandoc reference-doc. |
| PPTX | `python-pptx` + markdown section splitter | Walk H1/H2/`---`; map each chunk to a layout (`title`, `section`, `content`, `two-column`) picked from the template's Slide Master. |
| XLSX | `openpyxl` + markdown-table extractor | One worksheet per markdown table; row/column styles copied from the template's sample sheet. |

Deterministic at each step — no LLM call during rendering.

### 5.5 Target Auto-Detection

When `--target` is absent:

1. If the markdown frontmatter contains `target: docx|pptx|xlsx` → use it.
2. Else if the markdown has ≥ 3 `---` slide separators OR ≥ 3 repeated
   H2 sections → `pptx`.
3. Else if ≥ 50% of the non-heading content lines are inside
   markdown tables → `xlsx`.
4. Else → `docx` (the safe default).

### 5.6 Output Convention

```
report.md       →  report.docx
deck.md         →  deck.pptx
data.md         →  data.xlsx
/tmp/note.md    →  /tmp/note.docx
```

Idempotent: if the output exists and `mtime(output) > mtime(input)`,
skip unless `--force`. Mirrors the `/ocr` skill's cache semantics.

### 5.7 `--init` Bootstrap

`md-to-office.sh --init` in a target repo:

1. Creates `brand/templates/` if missing.
2. Writes three placeholder binaries generated on the fly from the
   engine defaults (pandoc default reference, a blank pptx, a blank
   xlsx with a single styled table).
3. Prints next steps:

   > Placeholders created in `brand/templates/`. Open each, apply your
   > team's brand (colors, logo, typography, footer, layouts for pptx),
   > then commit.

No BSG-default brand is injected — each repo starts from a neutral
baseline.

## 6. Directory Layout (shipped by this skill)

```
claude-skills/skills/md-to-office/
├── SKILL.md
├── scripts/
│   ├── md-to-office.sh         # orchestrator (the only entry point)
│   ├── resolve-template.sh     # template discovery per §5.3
│   ├── detect-target.sh        # auto-detection per §5.5
│   ├── render-docx.sh          # pandoc wrapper
│   ├── render-pptx.sh          # python-pptx renderer
│   ├── render-xlsx.sh          # openpyxl renderer
│   ├── init-templates.sh       # --init placeholders
│   └── install-local.sh        # installs pandoc + python deps
└── references/
    └── markdown-conventions.md # how to structure a .md for best render
```

Zero binaries. Zero brand assets. The skill is a pure rendering
pipeline.

## 7. Dependencies

| Tool | Install | Role |
|---|---|---|
| `pandoc` ≥ 3.0 | `brew install pandoc` | DOCX renderer |
| `python-pptx` | `pip install python-pptx` | PPTX renderer |
| `openpyxl` | `pip install openpyxl` | XLSX renderer |

`install-local.sh` installs the lot. No virtualenv is imposed, matching
the `ocr` skill's convention.

## 8. Target-Repo Convention

Each consuming repo is expected (but not required) to carry:

```
<target-repo>/
└── brand/
    ├── NARRATIVE.md              # voice guidelines — already a BSG convention
    ├── tokens.json               # optional: runtime color/typography overrides
    └── templates/
        ├── reference.docx        # Word reference-doc (pandoc)
        ├── template.pptx         # PowerPoint master + layouts
        └── template.xlsx         # Excel styles + table sample
```

The `brand/` directory already exists in `bsg-stack`; `templates/` is
the new sub-convention introduced by this PRD. `tokens.json` is
optional and only read by the PPTX / XLSX renderers for runtime color
overrides (used to keep one source of truth when the same repo ships
to multiple white-labels).

## 9. Silence-Breakers

Not applicable — this is a user-invoked conversion skill, not a `tick`
agent. No background runs, no PR output.

## 10. Interaction with Official Anthropic Skills

This skill is a **thin BSG wrapper** on top of Anthropic's
`document-skills` plugin. When the plugin is installed locally
(`/plugin install document-skills@anthropic-agent-skills`), advanced
features (tracked changes, formula evaluation) remain accessible
directly through that plugin — this skill does not duplicate them. The
value-add is:

1. Per-repo template discovery (`brand/templates/`).
2. Deterministic markdown-first entry point (`md-to-office.sh`).
3. Catalogued BSG convention (listed in `INSTALL.md`).

If the official plugin is absent, this skill still works via the
standalone `pandoc` / `python-pptx` / `openpyxl` dependencies.

## 11. Testing

Add to `claude-skills/tests/`:

- `test_md_to_office_frontmatter` — SKILL.md passes `test_skills.py`
  (covered automatically once frontmatter is valid).
- `test_resolve_template` — exercises the 5-level priority chain using
  a fixture repo with and without `brand/templates/`.
- `test_fallback_unbranded` — conversion succeeds in a repo with no
  `brand/`; output files exist and carry valid ZIP magic (`PK`).
- `test_render_smoke` — converts `fixtures/sample.md` to all three
  formats and verifies non-empty binary output.

No visual / rendering-fidelity tests — explicitly out of scope.

## 12. Delivery Plan

| # | Scope | PR strategy |
|---|---|---|
| 1 | Scaffold skill + SKILL.md + `md-to-office.sh` + DOCX renderer (pandoc, unbranded fallback only) | Structural — `needs-human-review` |
| 2 | `resolve-template.sh` + doc of `brand/templates/` convention | Auto-merge |
| 3 | `render-pptx.sh` (section splitter + layout mapping) | Auto-merge |
| 4 | `render-xlsx.sh` (markdown-table extractor) | Auto-merge |
| 5 | `--init` bootstrap + `INSTALL.md` catalogue entry + tests | Auto-merge |

Each PR is independently shippable. PR 1 is usable on its own (DOCX
only, unbranded); subsequent PRs add targets and the brand path.

## 13. Open Questions

1. **`brand/tokens.json` schema** — do we align it with an existing
   spec (Design Tokens Community Group, Tailwind theme) or invent a
   minimal BSG one? Default proposal: minimal (`{ colors: {...},
   fonts: {...} }`) v0.1, migrate later if adoption spreads.
2. **PPTX layout intelligence** — v0.1 deterministic (1 H2 = 1
   `content` slide). v0.2 could detect images/two-column patterns
   and switch layouts. Defer to a follow-up PRD.
3. **Template validation** — should `--init` refuse to overwrite
   existing templates, or prompt? Default proposal: refuse (fail-safe),
   require `--force` to overwrite.
4. **Multi-language docs** — PO reports are bilingual FR/EN in some
   repos. Does the renderer need locale-aware number/date formatting?
   Proposal: no for v0.1 — pandoc and openpyxl inherit the system
   locale.

## 14. Success Metrics

- A BSG repo with a `brand/templates/` directory can produce a branded
  DOCX from any `*.md` in one command with zero manual layout work.
- A BSG repo **without** a `brand/` directory can still produce a
  usable (unbranded) Office artifact without errors.
- `claude-skills/tests/test_skills.py` passes with the new skill
  declared.
- Adoption: ≥ 2 agents in the BSG catalogue (e.g. `po`, `pr-comms`)
  document in their own SKILL.md how to chain `md-to-office` after
  generating their markdown report — without taking a hard dependency.

---

**Next action:** scaffold PR #1 per §12.
