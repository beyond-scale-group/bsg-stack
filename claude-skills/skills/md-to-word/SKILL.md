---
name: md-to-word
description: >
  Convert a markdown file into a branded Word document (.docx). Reads all
  brand tokens (colours, font, company name, logo) from .bsg/DESIGN.md in
  the repo root — falls back to a neutral professional palette when absent.
  Pipeline: generate brand/templates/reference.docx (python-docx + pandoc
  default styles), convert via pandoc with French auto-TOC and vertical-gap
  separators (Lua filter), post-process full-width tables with branded header
  rows and alternating row colours. Inserts the project logo (or company name)
  before the TOC. Works in any BSG repo that has a .bsg/DESIGN.md.
  Use when the user asks to "export this markdown to Word", "generate a .docx",
  "créer un Word à partir de ce .md", "/md-to-word", or "convert this to a
  Word document".
version: 1.0.0
output: chat
auto-implements: []
never-auto-implements: []
custom-doc: .bsg/DESIGN.md
init: >
  Scans CSS custom properties, Tailwind config, design tokens, and logo
  files to generate DESIGN.md following the Google Stitch spec, then
  derives branded Word templates. Opens as PR for human review.
---

# md-to-word

Converts markdown → branded `.docx` driven by `.bsg/DESIGN.md`.

## Usage

```bash
bash .claude/skills/md-to-word/scripts/md-to-word.sh <file.md>
# Regenerate brand/templates/reference.docx from current .bsg/DESIGN.md:
bash .claude/skills/md-to-word/scripts/md-to-word.sh <file.md> --force-template
```

Output `.docx` is written next to the source file.

## Pipeline

| Step | Script | What it does |
|------|--------|--------------|
| 1 | `generate-template.py` | Parses `.bsg/DESIGN.md`, generates `brand/templates/reference.docx` (python-docx) |
| 2 | pandoc | Converts markdown → docx with `--toc`, `--lua-filter pagebreak.lua`, title metadata |
| 3 | `post-process.py` | Full-width autofit tables, branded header rows, alternating rows, cell padding, logo before TOC |

## Document title

Add `title:` (and `subtitle:`) to your YAML front matter:

```yaml
---
title: "Mon Document"
subtitle: "Sous-titre · Date"
---
```

If absent, the skill extracts the first `# ` heading automatically.

## .bsg/DESIGN.md schema

The skill reads these tokens from your repo's `.bsg/DESIGN.md`. All are optional
— defaults shown below are used when a token is absent.

### Colour tokens (Markdown table format)

```markdown
| `accent`        | `#2563eb` | H2 headings, table headers             |
| `accent-dark`   | `#1e3a8a` | H1 / Title, header text fallback        |
| `accent-light`  | `#3b82f6` | secondary accents                       |
| `accent-violet` | `#7c3aed` | inline code                             |
| `foreground`    | `#0f172a` | body text, H3, table body               |
| `muted`         | `#64748b` | header/footer, subtitles, captions      |
| `border`        | `#e2e8f0` | table borders, row separators           |
| `surface`       | `#f1f5f9` | even table rows                         |
| `card`          | `#ffffff` | odd table rows                          |
```

### Font (detected from first `**FontName**` + "principal/primary/main")

```markdown
Police principale : **Calibri** (Inter non embarquée dans Word ; Calibri est la plus proche).
```

### Company name (extracted from first H1 of DESIGN.md)

```markdown
# Design System — Acme Corp
```
→ `company = "Design System — Acme Corp"` (used as text fallback when no logo found)

## Logo discovery order

1. `vitrine/public/the-shift_dot_ai_petit.png`
2. `vitrine/public/logo-*.png` / `vitrine/public/*logo*.png`
3. `public/logo*.png` / `public/*logo*.png`
4. `brand/assets/logo.png`
5. `assets/logo.png`
6. **No logo found** → company name shown at 18pt bold (placeholder)

## Tabula-inspired spacing (applied to all documents)

| Style     | Size  | Before | After | Line height |
|-----------|-------|--------|-------|-------------|
| Title     | 26 pt | 0      | 20 pt | —           |
| Heading 1 | 22 pt | 28 pt  | 12 pt | —           |
| Heading 2 | 16 pt | 20 pt  | 10 pt | —           |
| Heading 3 | 13 pt | 16 pt  | 6 pt  | —           |
| Normal    | 11 pt | 0      | 10 pt | ×1.3        |

Margins: 2.5 cm all sides.

## Dependencies

- `python3` + `python-docx` (auto-installed if missing)
- `pandoc` (`brew install pandoc`)

---

## How to improve this skill

This file is a cached copy of `claude-skills/skills/md-to-word/SKILL.md` in
[beyond-scale-group/bsg-stack](https://github.com/beyond-scale-group/bsg-stack).
That repo is the single source of truth — `~/.claude/skills/md-to-word/SKILL.md`
is overwritten every time the BSG install flow runs.

If the user asks you to improve, fix, or extend this skill, do **not** edit
the local file. Instead:

1. `gh repo clone beyond-scale-group/bsg-stack` (or work in an existing clone)
2. Edit `claude-skills/skills/md-to-word/SKILL.md` on a feature branch
3. Open a pull request against `main`

Bug reports and ideas without a fix → open an issue on the same repo.
