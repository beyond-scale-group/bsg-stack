---
name: md-to-slide
description: >
  Convert a markdown file into branded slides — HTML and PowerPoint (.pptx) —
  using Marp (marp-cli). The Marp theme CSS is generated automatically from
  the brand tokens in .bsg/DESIGN.md (colours, font, company name) with a
  neutral professional fallback when absent; the company name becomes the
  slide footer. Runs fully local (npx marp-cli, no external API) — unlike
  gamma-presentation which calls the Gamma API. Use when the user asks to
  "generate slides", "convert markdown to slides", "export as PowerPoint
  slides", "HTML slides", "make a slide deck", "Marp", "/md-to-slide",
  "génère des slides", or "convertis ce md en présentation".
version: 1.0.0
output: chat
auto-implements: []
never-auto-implements: []
custom-doc: .bsg/DESIGN.md
init: >
  Generates brand/templates/marp-theme.css from .bsg/DESIGN.md brand tokens
  (colour table, primary font, company name). Regenerated automatically
  whenever DESIGN.md is newer than the cached theme.
model: haiku
---

# md-to-slide

Converts markdown → branded **HTML + PowerPoint slides** via
[Marp](https://marp.app), themed from `.bsg/DESIGN.md`.

## Usage

```bash
# Both HTML and PPTX (the default):
bash .claude/skills/md-to-slide/scripts/md-to-slide.sh <file.md>
# One format only:
bash .claude/skills/md-to-slide/scripts/md-to-slide.sh <file.md> --html
bash .claude/skills/md-to-slide/scripts/md-to-slide.sh <file.md> --pptx
# Also export a PDF:
bash .claude/skills/md-to-slide/scripts/md-to-slide.sh <file.md> --pdf
# Editable-text PPTX (experimental Marp feature, needs LibreOffice):
bash .claude/skills/md-to-slide/scripts/md-to-slide.sh <file.md> --pptx --editable
# Regenerate the theme after editing .bsg/DESIGN.md:
bash .claude/skills/md-to-slide/scripts/md-to-slide.sh <file.md> --force-theme
# Bring your own theme / drop the company footer:
bash .claude/skills/md-to-slide/scripts/md-to-slide.sh <file.md> --theme my.css --no-footer
```

Outputs (`.html`, `.pptx`, `.pdf`) are written next to the source file.

## Pipeline

| Step | Script | What it does |
|------|--------|--------------|
| 1 | `generate-theme.py` | Parses `.bsg/DESIGN.md`, generates `brand/templates/marp-theme.css` (skipped when present and up to date; auto-regenerated when DESIGN.md is newer) |
| 2 | `prepare-input.py` | Copies the source to a temp file, ensuring `marp: true`, `paginate: true`, and `footer: <company>` front matter — never mutates the source, never overwrites author directives |
| 3 | marp-cli | Converts to `.html` / `.pptx` / `.pdf` with `--theme` + `--allow-local-files` (local `marp` binary if installed, else `npx -y @marp-team/marp-cli@latest`) |

## Writing the deck

**Before writing or editing slide markdown, read
[references/marp-syntax.md](references/marp-syntax.md)** — slide separators,
front-matter and per-slide directives, image/background syntax, presenter
notes, and content-density rules (Marp clips overflow; slides must be
written slide-sized).

The generated theme ships two slide classes:

- `<!-- _class: lead -->` — cover slide (branded gradient, centered)
- `<!-- _class: divider -->` — section break

## .bsg/DESIGN.md schema

Same token schema as `md-to-word` — one DESIGN.md drives both documents and
slides. The skill is fully generic: parsing is schema-tolerant (any
``| `token` | `#rrggbb` |`` table row is picked up wherever it appears in
the document), every token is optional with a neutral professional default,
and the theme is regenerated automatically whenever DESIGN.md is newer than
the cached CSS — so per-repo DESIGN.md changes flow into the slides with no
skill edits. Path resolution follows ADR-001 (`.bsg/DESIGN.md`, no legacy
path); set `$BSG_DESIGN_MD` to point at a relocated design doc.

| Token | Default | Used for |
|---|---|---|
| `accent` | `#2563eb` | H2, links, table headers, blockquote bar, lead gradient |
| `accent-dark` | `#1e3a8a` | H1, strong, lead gradient |
| `accent-violet` | `#7c3aed` | inline code |
| `foreground` | `#0f172a` | body text, H3 |
| `muted` | `#64748b` | header/footer, page numbers, blockquotes |
| `border` | `#e2e8f0` | table borders, code-block borders |
| `surface` | `#f1f5f9` | even table rows, code background, divider slides |
| `card` | `#ffffff` | slide background |

Font: first `**FontName**` near "principal/primary/main". Company name:
first H1 of DESIGN.md (becomes the default slide footer).

## Dependencies

- `node` + `npx` (`brew install node`) — marp-cli is fetched on demand;
  or install it once: `npm install -g @marp-team/marp-cli`
- A Chromium-family browser (Chrome, Edge) or Firefox — required for
  `.pptx` / `.pdf` export only (HTML needs no browser). Marp auto-detects;
  override with `CHROME_PATH` if needed.
- LibreOffice Impress — only for `--editable` PPTX export

---

## How to improve this skill

This file is a cached copy of `claude-skills/skills/md-to-slide/SKILL.md` in
[beyond-scale-group/bsg-stack](https://github.com/beyond-scale-group/bsg-stack).
That repo is the single source of truth — `~/.claude/skills/md-to-slide/SKILL.md`
is overwritten every time the BSG install flow runs.

If the user asks you to improve, fix, or extend this skill, do **not** edit
the local file. Instead:

1. `gh repo clone beyond-scale-group/bsg-stack` (or work in an existing clone)
2. Edit `claude-skills/skills/md-to-slide/SKILL.md` on a feature branch
3. Open a pull request against `main`

Bug reports and ideas without a fix → open an issue on the same repo.
