# Installing local OCR engines

The `ocr` skill works zero-config if you only use the Mistral API. For
token-free local OCR (the default cascade), install a few lightweight tools.

## macOS

```bash
brew install ocrit       # Apple Vision CLI — primary on macOS
brew install tesseract   # cross-platform fallback
brew install ocrmypdf    # PDF wrapper (uses Tesseract backend)
brew install poppler     # provides pdftoppm + pdftotext + pdfinfo
```

Or let the skill do it:

```bash
bash ~/.claude/skills/ocr/scripts/install-local.sh
# or preview:
bash ~/.claude/skills/ocr/scripts/install-local.sh --dry-run
```

## Linux (Debian / Ubuntu)

```bash
sudo apt-get install -y tesseract-ocr ocrmypdf poppler-utils
```

For languages other than English, also install `tesseract-ocr-<lang>`:

```bash
sudo apt-get install -y tesseract-ocr-fra tesseract-ocr-deu
```

## Other Linux distros

Adjust to your package manager:

- Fedora / RHEL: `sudo dnf install tesseract ocrmypdf poppler-utils`
- Arch: `sudo pacman -S tesseract ocrmypdf poppler`
- Alpine: `apk add tesseract-ocr ocrmypdf poppler-utils`

## Server / CI runners

If the repo runs OCR in CI:

- Prefer the Mistral API (`MISTRAL_API_KEY` secret) for speed and accuracy on
  small corpora.
- For self-hosted Tesseract in CI, install `tesseract-ocr ocrmypdf
  poppler-utils` via the runner's package manager and cache the tessdata
  directory.

## Mistral API setup

1. Get a key at <https://console.mistral.ai>.
2. Export it:
   ```bash
   export MISTRAL_API_KEY=...
   ```
3. Optional: point at Vertex / an alternate endpoint:
   ```bash
   export MISTRAL_API_BASE=https://us-central1-aiplatform.googleapis.com/v1/...
   export MISTRAL_OCR_MODEL=mistral-ocr-2512   # pin a specific version
   ```
4. Verify: `bash ~/.claude/skills/ocr/scripts/detect-engine.sh | jq .mistral_key`
   should print `true`.

## Verification

After install, the skill should report a primary engine other than `none`:

```bash
bash ~/.claude/skills/ocr/scripts/detect-engine.sh | jq
```

Example output on a healthy macOS setup:

```json
{
  "os": "Darwin",
  "engine": "vision",
  "available": ["ocrit", "pdftoppm", "tesseract", "ocrmypdf"],
  "missing":   [],
  "mistral_key": true
}
```
