#!/usr/bin/env bash
# Run OCR using the Mistral OCR API (mistral-ocr-latest).
#
# Usage: run-mistral.sh <source> <output.ocr.md>
#
# Requires: MISTRAL_API_KEY env var, curl, jq.
# Uploads the file to Mistral's /v1/files endpoint with purpose=ocr, fetches
# a short-lived signed URL, runs OCR, concatenates per-page markdown, and
# deletes the uploaded file. No content is persisted on Mistral's side beyond
# the call.

set -euo pipefail

src="${1:?source file required}"
out="${2:?output path required}"

: "${MISTRAL_API_KEY:?MISTRAL_API_KEY is required for the Mistral OCR engine}"

command -v curl >/dev/null || { echo "curl is required" >&2; exit 2; }
command -v jq   >/dev/null || { echo "jq is required"   >&2; exit 2; }

api="${MISTRAL_API_BASE:-https://api.mistral.ai}"
model="${MISTRAL_OCR_MODEL:-mistral-ocr-latest}"

abs_src="$(cd "$(dirname "$src")" && pwd)/$(basename "$src")"
timestamp="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

# 1. Upload file.
upload_resp="$(curl -sS --fail-with-body "$api/v1/files" \
  -H "Authorization: Bearer $MISTRAL_API_KEY" \
  -F "purpose=ocr" \
  -F "file=@${src}")"
file_id="$(printf '%s' "$upload_resp" | jq -r '.id // empty')"
[[ -n "$file_id" ]] || { echo "Upload failed: $upload_resp" >&2; exit 1; }

cleanup() {
  curl -sS -X DELETE "$api/v1/files/$file_id" \
    -H "Authorization: Bearer $MISTRAL_API_KEY" >/dev/null 2>&1 || true
}
trap cleanup EXIT

# 2. Get a short-lived signed URL for the uploaded file.
url_resp="$(curl -sS --fail-with-body "$api/v1/files/$file_id/url?expiry=1" \
  -H "Authorization: Bearer $MISTRAL_API_KEY")"
signed_url="$(printf '%s' "$url_resp" | jq -r '.url // empty')"
[[ -n "$signed_url" ]] || { echo "Failed to sign URL: $url_resp" >&2; exit 1; }

# 3. Run OCR. Use document_url for PDFs, image_url for images.
ext="$(printf '%s' "${src##*.}" | tr '[:upper:]' '[:lower:]')"
case "$ext" in
  pdf)
    doc_payload="$(jq -n --arg url "$signed_url" \
      '{type:"document_url", document_url:$url}')"
    ;;
  *)
    doc_payload="$(jq -n --arg url "$signed_url" \
      '{type:"image_url", image_url:$url}')"
    ;;
esac

body="$(jq -n \
  --arg model "$model" \
  --argjson document "$doc_payload" \
  '{model:$model, document:$document, include_image_base64:false}')"

ocr_resp="$(curl -sS --fail-with-body "$api/v1/ocr" \
  -H "Authorization: Bearer $MISTRAL_API_KEY" \
  -H "Content-Type: application/json" \
  --data "$body")"

# 4. Compose output file.
pages="$(printf '%s' "$ocr_resp" | jq -r '.pages | length // 0')"

{
  printf '# OCR: %s\n\n' "$(basename "$src")"
  printf '%s\n' "- Engine: mistral ($model)"
  printf '%s\n' "- Source: $abs_src"
  printf '%s\n' "- Run at: $timestamp"
  [[ "$pages" != "0" ]] && printf '%s\n' "- Pages: $pages"
  printf '\n---\n\n'
} > "$out"

printf '%s' "$ocr_resp" \
  | jq -r '.pages | map(.markdown // "") | join("\n\n---\n\n")' \
  >> "$out"

echo "$out"
