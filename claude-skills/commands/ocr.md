Extract text from an image or PDF **without** uploading it into Claude's context: $ARGUMENTS

You are invoking the `ocr` skill. The goal is to save Anthropic tokens by
running OCR locally (or via a cheap OCR-only API) and producing a plain text /
markdown file the agent can read instead of the raw image.

## How to run

1. **Parse arguments.** Typical forms:
   - `/ocr path/to/file.pdf` — auto-cascade, output next to source
   - `/ocr path/to/image.png --engine vision` — force a specific engine
   - `/ocr path/to/file.pdf --force` — overwrite existing `.ocr.md`
   - `/ocr --install` — install local OCR engines for this system and stop
   - `/ocr --detect` — print the detected engine + available/missing tools and stop

2. **Never read the image or PDF directly into your context** to transcribe it
   yourself. That defeats the whole point of this skill. If OCR fails, surface
   the error; do not fall back to multimodal transcription without the user
   explicitly asking for it.

3. **Cascade order** (auto mode, matches the `ocr` skill):
   1. Apple Vision (macOS only, via `ocrit` + `pdftoppm` for PDFs)
   2. Tesseract (`tesseract` for images, `ocrmypdf` for PDFs)
   3. Mistral OCR API (only if `MISTRAL_API_KEY` is set **and** steps 1 + 2
      failed or produced trivially short output)

4. **Output path.** `<source>.ocr.md` in the same directory as the source.
   If the file already exists, skip unless `--force` is given.

5. **Delegation.** Prefer running the skill's orchestrator directly:

   ```bash
   bash ~/.claude/skills/ocr/scripts/ocr.sh "$file"
   ```

   It handles detection, cascade, output path, and idempotency. Only shell out
   to individual engine scripts (`run-vision.sh`, `run-tesseract.sh`,
   `run-mistral.sh`) if the user explicitly pinned an engine.

6. **Report back.** One line with the output path and which engine succeeded,
   e.g. `Wrote report.pdf.ocr.md (vision, 12 pages, 4.2 KB)`. Do **not** paste
   the extracted text into the chat — the file is the artifact.

## When to invoke automatically

Any time another agent or skill is about to:

- `Read` an image file (`.png`, `.jpg`, `.heic`, `.tiff`, `.webp`, `.bmp`)
- `Read` a PDF whose text layer is empty or scanned
- Attach an image to the model context to "see what it says"

…call `/ocr` first and read the resulting `.ocr.md` instead. Rough guide: if
the image is a screenshot of a UI being debugged, multimodal is fine; if it is
a document (invoice, scan, whiteboard with text, book page), `/ocr` saves
tokens and produces better searchable output.

## Refusing gracefully

- If no engine is available and `MISTRAL_API_KEY` is unset, run
  `bash ~/.claude/skills/ocr/scripts/install-local.sh` in dry-run (print-only)
  mode and show the user what would be installed. Do not install without
  confirmation.
- If the user insists on sending the image to Claude directly, warn them
  (token cost, no `.ocr.md` for reuse) and proceed only on explicit confirm.

---

## How to improve this skill

This file is a cached copy of `claude-skills/commands/ocr.md` in
[beyond-scale-group/bsg-stack](https://github.com/beyond-scale-group/bsg-stack).
That repo is the single source of truth — `~/.claude/commands/ocr.md` is
overwritten every time the BSG install flow runs.

If the user asks you to improve, fix, or extend this skill, do **not** edit
the local file. Instead:

1. `gh repo clone beyond-scale-group/bsg-stack` (or work in an existing clone)
2. Edit `claude-skills/commands/ocr.md` on a feature branch
3. Open a pull request against `main`

Bug reports and ideas without a fix → open an issue on the same repo.
