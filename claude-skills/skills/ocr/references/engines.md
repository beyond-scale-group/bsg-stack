# OCR engines — when to use what

The `ocr` skill cascades through three engines. This reference explains the
trade-offs so the agent can pick intelligently when the user asks for a
specific engine or when auto-mode fails.

## 1. Apple Vision (macOS only, free)

**How it's invoked**: `ocrit` binary (images) + `pdftoppm` → PNG → `ocrit`
(PDFs).

**Strengths:**
- Fastest local option on Apple Silicon — no model download, no CPU inference.
- Excellent accuracy on clean printed text, receipts, signs, handwriting.
- Produces simple plain text (no layout reconstruction, but clean).

**Weaknesses:**
- macOS only. A Linux server will never have this engine.
- Does not natively reconstruct tables, columns, or reading order for complex
  multi-column layouts.
- No language hints — it auto-detects, which can misfire on mixed scripts.

**When to pick explicitly (`--engine vision`):**
- Single-page screenshots / photos / scans of simple printed text
- Anything where "local, free, fast" beats "layout fidelity"

## 2. Tesseract (cross-platform, free)

**How it's invoked**: `tesseract` (images), `ocrmypdf` with its built-in
Tesseract backend (PDFs).

**Strengths:**
- Runs anywhere (macOS, Linux server, container).
- 100+ languages available via `tessdata` packages.
- `ocrmypdf` produces a searchable PDF + pulls text via `pdftotext -layout`,
  preserving column reading order better than Vision.

**Weaknesses:**
- Less accurate than Apple Vision on Apple Silicon for most documents.
- Sensitive to image quality — benefits from 300 DPI input; noisy scans need
  preprocessing.
- No structured output (tables, equations) without extra tooling.

**When to pick explicitly (`--engine tesseract`):**
- Running on a Linux server where `vision` is unavailable.
- Multi-language documents where you can specify `-l fra+eng` etc.
- PDFs where you want a searchable output PDF as a side effect (edit
  `run-tesseract.sh` to keep `$tmp_pdf`).

## 3. Mistral OCR API (paid, ~$0.002/page)

**How it's invoked**: uploads to `/v1/files` (purpose=ocr) → signs a short URL
→ `/v1/ocr` with `mistral-ocr-latest` → per-page markdown.

**Strengths:**
- Best-in-class layout reconstruction: tables become HTML tables, equations
  become LaTeX, reading order is correct on multi-column layouts.
- Handles scanned PDFs, photos, and complex documents end-to-end with no
  preprocessing.
- Output is structured markdown that downstream tools (and Claude) can parse
  directly.

**Weaknesses:**
- Costs money (~$2 per 1000 pages, ~$1 with batch).
- Sends the document to Mistral's servers — not suitable for confidential
  material without an enterprise agreement.
- Requires a `MISTRAL_API_KEY` (env var; see `MISTRAL_API_BASE` for Vertex /
  La Plateforme routing).

**When to pick explicitly (`--engine mistral`):**
- The document has tables, equations, or multi-column layout that local
  engines mangle.
- Accuracy matters more than cost (legal contracts, accounting documents,
  research papers).
- Running on a headless server without GPU and the document is > 10 pages
  (Mistral's API is often faster than local Tesseract for bulk PDFs).

## Never use: Claude multimodal

Uploading the raw image/PDF into Claude's context "to read it" costs tokens
proportional to image size and produces no reusable artifact. It is always
more expensive than the worst-case OCR cascade above.

The only exception is when the user **explicitly asks for visual analysis
beyond transcription** — e.g. "describe the chart in this PDF", "what's the
color scheme of this screenshot". OCR only extracts words; visual reasoning
needs the model.

## Validation heuristic

The orchestrator considers an engine "successful" if the output file has
≥ 10 non-whitespace characters. This is deliberately loose:

- A blank page or pure-image page legitimately produces little text.
- A total engine failure typically produces 0 bytes or a single error line.

If an engine repeatedly "succeeds" but produces garbage on your corpus,
lower the bar in `ocr.sh::validate()` and open an issue.
