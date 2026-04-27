---
name: md-to-office
description: >
  Convert a markdown file into a brand-aligned Office document (DOCX first,
  PPTX/XLSX in later PRs) using Office templates that live inside the
  current repo at brand/templates/. Wraps pandoc; ships no binaries of
  its own — each consuming repo owns its brand assets. Use when the user
  asks to "turn this md into a Word doc", "export as Word", "génère un
  Word à partir de ce .md", or "convert the report to docx".
version: 0.1.0
output: chat
auto-implements: []
never-auto-implements: []
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
2. **Deterministic pipeline.** Rendering is pandoc + (later) python-pptx
   + openpyxl. No LLM call during rendering. Claude orchestrates,
   never draws.
3. **Write next to the source.** `report.md` → `report.docx` in the
   same directory, mirroring the `/ocr` convention.
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
        ├── template.pptx     # (PR #3) PowerPoint master + layouts
        └── template.xlsx     # (PR #4) Excel styles + table sample
```

Scope of PR #1: only `reference.docx` is read. PPTX and XLSX renderers
will land in follow-up PRs per PRD-008.

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
| `md-to-office.sh` | Orchestrator. `md-to-office.sh <file> [--target docx] [--template <path>] [--force]`. |
| `resolve-template.sh` | Emits the resolved template path (or empty) for a given target. |
| `render-docx.sh` | pandoc wrapper. `render-docx.sh <input.md> <output.docx> [--template <path>]`. |
| `init-brand.sh` | Brand bootstrap. `init-brand.sh [--force] [--tokens-only] [--dry-run]`. |
| `scan-brand.py` | Repo signal scanner → `brand/tokens.json` + optional audit. |
| `generate-templates.py` | Reads `tokens.json`, produces `reference.docx`, `template.pptx`, `template.xlsx`. |
| `install-local.sh` | Installs `pandoc` via brew. `--dry-run` to print-only. |

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

## Usage

```bash
# Auto-target (DOCX by default in PR #1):
claude-skills/skills/md-to-office/scripts/md-to-office.sh report.md

# Explicit template override:
md-to-office.sh report.md --template path/to/custom.docx

# Force re-render:
md-to-office.sh report.md --force
```

## Output convention

```
report.md                 →  report.docx
/tmp/note.md              →  /tmp/note.docx
po/reports/2026-04-24.md  →  po/reports/2026-04-24.docx
```

## Dependencies

| Tool | Install |
|---|---|
| `pandoc` ≥ 3.0 | `brew install pandoc` |

Run `scripts/install-local.sh` to install on macOS.

## Limits (v0.1)

- **DOCX only.** PPTX and XLSX renderers land in later PRs per PRD-008
  §12.
- **No multi-file input.** One `.md` at a time; batch conversion is
  deferred.

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
