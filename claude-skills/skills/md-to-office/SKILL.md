---
name: md-to-office
description: >
  Convert a markdown file into a brand-aligned Office document (DOCX or PPTX)
  using Office templates that live inside the current repo at brand/templates/.
  Wraps pandoc for DOCX and python-pptx for PPTX; ships no binaries of
  its own — each consuming repo owns its brand assets. Auto-detects target
  format from gamma frontmatter. Use when the user asks to "turn this md
  into a Word doc", "export as PowerPoint", "convert to slides", "génère un
  Word à partir de ce .md", or "convert the report to docx".
version: 0.2.0
output: chat
auto-implements: []
never-auto-implements: []
custom-doc: .bsg/DESIGN.md
init: >
  Scans CSS custom properties, Tailwind config, design tokens, and logo
  files to generate DESIGN.md following the Google Stitch spec, and
  derives branded Office templates. Opens as PR for human review.
---

# md-to-office Skill

Convert markdown into a branded Office artifact. The skill's whole
reason to exist is **per-repo brand fidelity with zero central state**:
every consuming repo keeps its own Office templates at
`brand/templates/`, and the skill picks them up automatically at
runtime.

## Hard rules

1. **Templates live in the target repo, never in this skill.** The
   catalog ships pure rendering logic. A repo without `brand/` still
   gets a working (unbranded) output — that is a success, not an error.
2. **Deterministic pipeline.** Rendering is pandoc (DOCX) + python-pptx
   (PPTX). No LLM call during rendering. Claude orchestrates, never draws.
3. **Write next to the source.** `report.md` → `report.docx` (or
   `deck.md` → `deck.pptx`) in the same directory, mirroring the
   `/ocr` convention.
4. **Idempotent.** If the output exists and is newer than the source,
   skip unless `--force` is given.
5. **Scripts do the work.** This SKILL.md narrates; `scripts/`
   contains the actual logic. Do not re-implement rendering in-chat.

## Where templates live

Every consuming repo is expected (but not required) to carry:

```
<target-repo>/
└── brand/
    └── templates/
        ├── reference.docx    # pandoc reference-doc, used for DOCX output
        ├── template.pptx     # PowerPoint master + layouts, used for PPTX output
        └── template.xlsx     # (PR #4) Excel styles + table sample
```

## Template resolution

`resolve-template.sh <target>` walks this chain and stops at the first
hit:

| Priority | Location | Use case |
|---|---|---|
| 1 | `--template <path>` (CLI flag) | Explicit override |
| 2 | `$BSG_BRAND_TEMPLATES/<target>.{docx,pptx,xlsx}` | Tests, CI |
| 3 | `./brand/templates/<target>.{docx,pptx,xlsx}` | Canonical convention |
| 4 | `./brand/templates/reference.docx` (legacy pandoc alias) | Back-compat |
| 5 | (none) | Fall back to unbranded rendering + `⚠️` warning |

Level 5 is a non-error. The skill must succeed in a fresh repo.

## Available scripts

All scripts live in `scripts/`. `md-to-office.sh` is the orchestrator —
prefer it over calling the renderers directly.

| Script | Purpose |
|---|---|
| `md-to-office.sh` | Orchestrator. `md-to-office.sh <file> [--target docx\|pptx] [--template <path>] [--force]`. Also accepts a directory for batch mode. |
| `resolve-template.sh` | Emits the resolved template path (or empty) for a given target. |
| `render-docx.sh` | pandoc wrapper. `render-docx.sh <input.md> <output.docx> [--template <path>]`. |
| `render-pptx.sh` | python-pptx wrapper. `render-pptx.sh <input.md> <output.pptx> [--template <path>]`. |
| `render-pptx.py` | Markdown-to-slides parser + PPTX renderer. Called by `render-pptx.sh`. |
| `init-brand.sh` | Brand bootstrap. `init-brand.sh [--force] [--tokens-only] [--dry-run]`. |
| `scan-brand.py` | Repo signal scanner → `brand/tokens.json` + optional audit. |
| `generate-templates.py` | Reads `tokens.json`, produces `reference.docx`, `template.pptx`, `template.xlsx`. |
| `install-local.sh` | Installs `pandoc` + Python deps via brew/pip. `--dry-run` to print-only. |

## Brand initialization (`--init`)

`--init` mines the repo for brand signals and synthesizes them into
branded Office templates. Signals detected:

| Signal | Where it looks |
|---|---|
| **Colors** | CSS custom properties, `tailwind.config.*`, design-token JSON |
| **Typography** | CSS `--font-*` variables, `@font-face`, Google Fonts imports |
| **Logo** | `public/`, `brand/`, `images/`, `assets/` — files with "logo" in name |
| **Voice & identity** | `brand/NARRATIVE.md`, `DESIGN.md`, `*identity*.md` |
| **Existing templates** | `.docx`, `.pptx`, `.xlsx` already in the repo |

```bash
md-to-office.sh --init                    # scan repo, generate templates
md-to-office.sh --init --dry-run          # show what would be extracted
md-to-office.sh --init --force            # overwrite existing templates
md-to-office.sh --init --tokens-only      # scan only, skip template gen
```

Output:

```
brand/tokens.json                   ← extracted tokens (name, colors, fonts, logos, …)
brand/templates/brand-audit.md      ← what was found and what was chosen
brand/templates/reference.docx      ← pandoc reference-doc with brand styles
brand/templates/template.pptx       ← PowerPoint with brand theme
brand/templates/template.xlsx       ← Excel with brand-coloured header
```

## Auto-detection from frontmatter

When `--target` is omitted, the orchestrator reads YAML frontmatter to
pick the output format:

```yaml
---
gamma:
  format: presentation   # → PPTX
---
```

```yaml
---
gamma:
  format: document       # → DOCX
---
```

```yaml
---
target: pptx             # → PPTX (also works)
---
```

If no frontmatter or no recognized field, defaults to DOCX.

## Usage

```bash
# Auto-detect from frontmatter (presentation → PPTX, document → DOCX):
md-to-office.sh deck.md           # PPTX if gamma.format = presentation
md-to-office.sh report.md         # DOCX (default)

# Explicit target:
md-to-office.sh deck.md --target pptx
md-to-office.sh report.md --target docx

# Explicit template override:
md-to-office.sh report.md --template path/to/custom.docx

# Force re-render:
md-to-office.sh report.md --force

# Batch mode (converts every .md in directory, auto-detecting each):
md-to-office.sh content/funding/
```

## PPTX slide conventions

- `# Title` → title slide (layout 0)
- `## Section` → content slide with title
- `### Sub` → subheading within current slide
- `---` → explicit slide break
- Bullet lists → bulleted text frame with nesting
- GFM pipe tables → PPTX table shape
- `![alt](path)` → embedded picture
- `**bold**` / `*italic*` → inline formatting
- Fenced code blocks → monospace text

## Output convention

```
report.md                 →  report.docx      (default / gamma.format: document)
deck.md                   →  deck.pptx        (gamma.format: presentation)
/tmp/note.md              →  /tmp/note.docx
po/reports/2026-04-24.md  →  po/reports/2026-04-24.docx
```

## Dependencies

| Tool | Install |
|---|---|
| `pandoc` ≥ 3.0 | `brew install pandoc` |
| `python-pptx` | `pip3 install python-pptx` |

Run `scripts/install-local.sh` to install all dependencies on macOS.

## Limits (v0.2)

- **XLSX not yet implemented.** The XLSX renderer lands in a future PR
  per PRD-008 §12.
- **Batch mode is flat.** Directory conversion only processes `.md`
  files at the top level, not recursively.

---

## How to improve this skill

This file is a cached copy of `claude-skills/skills/md-to-office/SKILL.md` in
[beyond-scale-group/bsg-stack](https://github.com/beyond-scale-group/bsg-stack).
That repo is the single source of truth — `~/.claude/skills/md-to-office/SKILL.md`
is overwritten every time the BSG install flow runs.

If the user asks you to improve, fix, or extend this skill, do **not** edit
the local file. Instead:

1. `gh repo clone beyond-scale-group/bsg-stack` (or work in an existing clone)
2. Edit `claude-skills/skills/md-to-office/SKILL.md` on a feature branch
3. Open a pull request against `main`

Bug reports and ideas without a fix → open an issue on the same repo.
