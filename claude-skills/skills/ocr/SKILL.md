---
name: ocr
description: >
  Extract text from images (PNG, JPG, HEIC, TIFF, WebP, BMP) and PDFs without
  sending the file into Claude's multimodal context. Cascades through local
  engines first (Apple Vision on macOS, then Tesseract/OCRmyPDF) and only falls
  back to the Mistral OCR API if MISTRAL_API_KEY is set and local engines
  failed. Writes output to <source>.ocr.md next to the source file. Use when
  the user asks to "OCR this", "extract text from <image|pdf>", "read the
  scan", "transcribe <file>", or when another agent is about to upload a
  document screenshot or scanned PDF into the model context. The point is to
  save Anthropic tokens — never use multimodal transcription as the default.
version: 0.1.0
---

# OCR Skill

Extract text from images and PDFs cheaply and deterministically. The skill's
whole reason to exist is **token economy**: send Claude the extracted text,
never the raw image, unless the user explicitly asks for multimodal analysis.

## Hard rules

1. **Never read an image/PDF into the agent's context to "OCR it with the
   model".** That costs tokens and produces no reusable artifact. Call the
   orchestrator script and read the resulting `.ocr.md` file instead.
2. **Always write to `<source>.ocr.md` in the same directory as the source.**
   This keeps the artifact discoverable and cacheable. If the file already
   exists, treat it as a cache hit unless `--force` is given.
3. **Cascade, don't skip.** Auto mode tries engines in order. If a cheap local
   engine works, never call the paid API.
4. **Zero telemetry.** The Mistral API call deletes its uploaded file after
   extraction. No content is persisted outside the local repo.
5. **Scripts do the work.** This SKILL.md narrates; the `scripts/` directory
   contains the actual logic. Do not re-implement OCR in-chat.

## Cascade

| Priority | Engine         | Prereqs                                    | Cost per page |
| -------- | -------------- | ------------------------------------------ | ------------- |
| 1        | Apple Vision   | macOS + `ocrit` (images) + `pdftoppm` (pdf) | $0           |
| 2        | Tesseract      | `tesseract` (images) + `ocrmypdf` (pdf)    | $0            |
| 3        | Mistral OCR    | `MISTRAL_API_KEY` env var                  | ~$0.002       |
| — (refused) | Claude multimodal | —                                      | tokens $$     |

Auto mode (`--engine auto`, the default):

1. Try engine #1. If the output file exists and has ≥ 10 non-whitespace
   characters per page, stop.
2. Otherwise try engine #2.
3. Otherwise, if `MISTRAL_API_KEY` is set, try engine #3.
4. Otherwise fail with a helpful install hint.

The user can pin an engine with `--engine vision|tesseract|mistral`. In that
case no cascade — the skill either succeeds with that engine or fails.

## Available scripts

All scripts live in `scripts/`. `ocr.sh` is the orchestrator — prefer it over
calling the engine scripts directly.

| Script              | Purpose                                                          |
| ------------------- | ---------------------------------------------------------------- |
| `ocr.sh`            | Orchestrator. `ocr.sh <file> [--engine X] [--force]`. Handles detection, cascade, idempotency, and output path. |
| `detect-engine.sh`  | Emits JSON describing OS, detected primary engine, available tools, and missing tools. |
| `install-local.sh`  | Installs local engines for the current OS (`ocrit`, `tesseract`, `ocrmypdf`, `poppler`). `--dry-run` to print-only. |
| `run-vision.sh`     | Apple Vision via `ocrit` (+ `pdftoppm` for PDFs). macOS only.    |
| `run-tesseract.sh`  | Tesseract (+ `ocrmypdf` for PDFs). Cross-platform.               |
| `run-mistral.sh`    | Mistral OCR API wrapper. Uploads, runs OCR, deletes the upload.  |

## Output convention

```
invoice.pdf          →  invoice.pdf.ocr.md
screenshot.png       →  screenshot.png.ocr.md
/tmp/scan.jpg        →  /tmp/scan.jpg.ocr.md
```

The `.ocr.md` suffix (rather than replacing the extension) preserves the
original filename so agents can reason about the source type.

Content layout in the output file:

```markdown
# OCR: <source basename>

- Engine: <vision|tesseract|mistral>
- Source: <absolute path>
- Run at: <ISO timestamp>
- Pages: <N>  (PDFs only)

---

<extracted markdown, page-separated with --- for PDFs>
```

## Intent routing

| User says…                                                  | Do…                                                     |
| ----------------------------------------------------------- | ------------------------------------------------------- |
| "OCR this", "extract text from X", "read the scan"          | `bash scripts/ocr.sh <path>`                            |
| "Use Mistral", "accuracy matters"                           | `bash scripts/ocr.sh <path> --engine mistral`           |
| "Install the OCR tools"                                     | `bash scripts/install-local.sh`                         |
| "What OCR engine would you use?", "check my system"         | `bash scripts/detect-engine.sh \| jq`                   |
| "OCR this folder of scans"                                  | Loop over files, calling `ocr.sh` once per file         |

For an unknown file type, consult `references/engines.md` first.

## When to invoke from another agent

Before uploading an image/PDF into Claude's multimodal context, check:

- Is it a document (invoice, scan, book page, whiteboard with text)? → Call
  `/ocr` and read the `.ocr.md`.
- Is it a UI screenshot being debugged? → Multimodal is fine; OCR loses
  layout.
- Is it a chart/diagram? → Multimodal; OCR only captures legend text.

The rule of thumb: **if the content is mostly words, OCR it first**.

---

## How to improve this skill

This file is a cached copy of `claude-skills/skills/ocr/SKILL.md` in
[beyond-scale-group/bsg-stack](https://github.com/beyond-scale-group/bsg-stack).
That repo is the single source of truth — `~/.claude/skills/ocr/SKILL.md` is
overwritten every time the BSG install flow runs.

If the user asks you to improve, fix, or extend this skill, do **not** edit
the local file. Instead:

1. `gh repo clone beyond-scale-group/bsg-stack` (or work in an existing clone)
2. Edit `claude-skills/skills/ocr/SKILL.md` on a feature branch
3. Open a pull request against `main`

Bug reports and ideas without a fix → open an issue on the same repo.
