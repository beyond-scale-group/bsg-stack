#!/usr/bin/env bash
# email-from-md.sh — convert markdown to a Gmail-ready HTML draft
#
# Usage:
#   email-from-md.sh --markdown FILE [--from ALIAS] [--no-signature]
#
# Outputs Gmail-ready HTML on stdout:
#   - Tables get inline CSS (border-collapse, borders, padding)
#   - Blockquotes get left-border styling
#   - Sender signature appended via Gmail sendAs API unless --no-signature
#
# Pipe the output into gws +send --body "$(email-from-md.sh ...)" --html
# or use the wrapper: gws gmail +email-from-md --markdown FILE ...
#
# Requirements: pandoc, gws (google-workspace-cli) for signature fetch
#
# Part of the BSG google-workspace skill.
# Issue: beyond-scale-group/bsg-stack#365

set -euo pipefail

# ---------- defaults ----------
MARKDOWN_FILE=""
FROM_ALIAS=""
NO_SIGNATURE=false

# ---------- parse args ----------
while [[ $# -gt 0 ]]; do
  case "$1" in
    --markdown)
      MARKDOWN_FILE="$2"
      shift 2
      ;;
    --from)
      FROM_ALIAS="$2"
      shift 2
      ;;
    --no-signature)
      NO_SIGNATURE=true
      shift
      ;;
    -h|--help)
      grep '^#' "$0" | grep -v '^#!/' | sed 's/^# //' | sed 's/^#//'
      exit 0
      ;;
    *)
      echo "error: unknown flag $1" >&2
      exit 1
      ;;
  esac
done

# ---------- validation ----------
if [[ -z "$MARKDOWN_FILE" ]]; then
  echo "error: --markdown FILE is required" >&2
  exit 1
fi

if [[ ! -f "$MARKDOWN_FILE" ]]; then
  echo "error: file not found: $MARKDOWN_FILE" >&2
  exit 1
fi

if ! command -v pandoc &>/dev/null; then
  echo "error: pandoc is required (brew install pandoc)" >&2
  exit 1
fi

# ---------- convert markdown to HTML ----------
RAW_HTML=$(pandoc -f markdown -t html --wrap=none "$MARKDOWN_FILE")

# ---------- inline CSS on tables ----------
# Table container: collapse borders, readable font
STYLED_HTML=$(printf '%s' "$RAW_HTML" | sed \
  -e 's|<table>|<table style="border-collapse:collapse;border:1px solid #ccc;margin:12px 0;font-family:Arial,sans-serif;font-size:13px;">|g' \
  -e 's|<th>|<th style="background:#f4f4f4;border:1px solid #ccc;padding:8px 10px;text-align:left;font-weight:600;">|g' \
  -e 's|<th \([^>]*\)>|<th \1 style="background:#f4f4f4;border:1px solid #ccc;padding:8px 10px;text-align:left;font-weight:600;">|g' \
  -e 's|<td>|<td style="border:1px solid #ccc;padding:8px 10px;vertical-align:top;">|g' \
  -e 's|<td \([^>]*\)>|<td \1 style="border:1px solid #ccc;padding:8px 10px;vertical-align:top;">|g' \
)

# ---------- inline CSS on blockquotes ----------
STYLED_HTML=$(printf '%s' "$STYLED_HTML" | sed \
  -e 's|<blockquote>|<blockquote style="border-left:3px solid #ccc;padding:6px 12px;margin:12px 0;color:#444;background:#fafafa;">|g' \
)

# ---------- fetch and append signature ----------
if [[ "$NO_SIGNATURE" == false ]]; then
  SIG=""
  if command -v gws &>/dev/null && [[ -n "$FROM_ALIAS" ]]; then
    # Fetch signature for the --from alias via Gmail sendAs API
    SIG=$(gws gmail users settings sendAs list \
      --params "{\"userId\":\"me\"}" 2>/dev/null \
      | jq -r ".sendAs[] | select(.sendAsEmail == \"$FROM_ALIAS\") | .signature // empty" \
      2>/dev/null || true)
  elif command -v gws &>/dev/null && [[ -z "$FROM_ALIAS" ]]; then
    # No --from alias: try the default/primary sendAs entry
    SIG=$(gws gmail users settings sendAs list \
      --params '{"userId":"me"}' 2>/dev/null \
      | jq -r '.sendAs[] | select(.isDefault == true) | .signature // empty' \
      2>/dev/null || true)
  fi

  if [[ -n "$SIG" ]]; then
    STYLED_HTML="${STYLED_HTML}
<div class=\"gmail_signature\" style=\"margin-top:16px;border-top:1px solid #eee;padding-top:8px;\">${SIG}</div>"
  fi
fi

# ---------- emit ----------
printf '%s\n' "$STYLED_HTML"
