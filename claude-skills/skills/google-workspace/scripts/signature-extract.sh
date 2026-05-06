#!/usr/bin/env bash
# signature-extract.sh — pull an HTML signature out of a previously-sent
# Gmail message.
#
# Use case: the user has a beautifully formatted signature that lives only
# in their Gmail account (in:sent), but never copied the HTML into the
# sendAs settings of one of their aliases. This script reads the most
# recent sent message that matches `--alias`, locates the
# <div class="gmail_signature">…</div> block, and prints the HTML to stdout.
#
# When the explicit `gmail_signature` div is absent (older Gmail composer,
# or a message authored elsewhere), falls back to splitting on the
# RFC-3676 `-- ` separator at the bottom of the HTML body.
#
# Usage:
#   bash signature-extract.sh                                  # primary alias, latest sent
#   bash signature-extract.sh --alias me@bsg-holding.fr        # specific alias
#   bash signature-extract.sh --message-id 18b... --alias me@x.com
#   bash signature-extract.sh --alias me@x.com --raw           # full message HTML
#
# Pipes cleanly into signature-set.sh:
#   bash signature-extract.sh --alias OLD@x.com \
#     | bash signature-set.sh --alias NEW@x.com --html-stdin
#
# Exit codes:
#   0  signature extracted to stdout
#   1  no sent messages found for the alias / no signature block detected
#   2  preflight failure (gws/jq missing, auth invalid, bad flag)
#
# Part of the BSG google-workspace skill.

set -uo pipefail

# ---------- defaults ----------
ALIAS=""
MESSAGE_ID=""
RAW_OUTPUT=0
PREVIEW=0

usage() { sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'; exit 0; }

# ---------- parse args ----------
while [[ $# -gt 0 ]]; do
  case "$1" in
    --alias)      ALIAS="$2"; shift 2 ;;
    --message-id) MESSAGE_ID="$2"; shift 2 ;;
    --raw)        RAW_OUTPUT=1; shift ;;
    --preview)    PREVIEW=1; shift ;;
    -h|--help)    usage ;;
    *) echo "error: unknown flag $1" >&2; exit 2 ;;
  esac
done

# ---------- preflight ----------
command -v gws    >/dev/null || { echo "error: gws not installed" >&2; exit 2; }
command -v jq     >/dev/null || { echo "error: jq not installed (brew install jq)" >&2; exit 2; }
command -v base64 >/dev/null || { echo "error: base64 not installed" >&2; exit 2; }

if ! gws auth status 2>/dev/null | jq -e '.token_valid == true' >/dev/null; then
  echo "error: gws auth invalid — run scripts/auth-login.sh" >&2
  exit 2
fi

# Default alias = primary login.
if [[ -z "$ALIAS" ]]; then
  ALIAS=$(gws gmail users getProfile --params '{"userId":"me"}' 2>/dev/null | jq -r '.emailAddress // empty')
  [[ -n "$ALIAS" ]] || { echo "error: could not resolve primary email" >&2; exit 2; }
  echo "info: defaulting to primary alias: $ALIAS" >&2
fi

# ---------- find the source message ----------
if [[ -z "$MESSAGE_ID" ]]; then
  # Look at the 5 most recent sent messages from this alias.
  Q="in:sent from:$ALIAS"
  LIST=$(gws gmail users messages list --params "$(jq -nc --arg q "$Q" '{userId:"me", q:$q, maxResults:5}')" 2>/dev/null) \
    || { echo "error: messages.list failed" >&2; exit 1; }
  IDS=$(printf '%s' "$LIST" | jq -r '.messages[]?.id // empty')
  [[ -n "$IDS" ]] || { echo "error: no sent messages found for $ALIAS — send one and retry" >&2; exit 1; }
fi

# ---------- helper: pull text/html part from a message ----------
extract_html_part() {
  local msg_json="$1"
  # Walk every part recursively, return the first text/html body.
  printf '%s' "$msg_json" | jq -r '
    def walk: if .parts then .parts[] | walk else . end;
    [.payload | walk | select(.mimeType == "text/html")][0].body.data // empty
  '
}

# Try each candidate message until one yields an extractable signature.
try_one() {
  local mid="$1"
  local msg
  msg=$(gws gmail users messages get \
        --params "$(jq -nc --arg id "$mid" '{userId:"me", id:$id, format:"full"}')" 2>/dev/null) \
    || return 1

  local b64 html
  b64=$(extract_html_part "$msg")
  [[ -n "$b64" ]] || return 1

  # base64url → base64 (gmail uses URL-safe). Pad to a multiple of 4 with '='
  # before decoding; macOS `base64 -D` is strict about padding length.
  local padded
  padded=$(printf '%s' "$b64" | tr '_-' '/+')
  local mod=$(( ${#padded} % 4 ))
  if   [[ "$mod" -eq 2 ]]; then padded="${padded}=="
  elif [[ "$mod" -eq 3 ]]; then padded="${padded}="
  fi
  html=$(printf '%s' "$padded" | base64 -D 2>/dev/null || true)
  [[ -n "$html" ]] || return 1

  if [[ "$RAW_OUTPUT" -eq 1 ]]; then
    printf '%s' "$html"
    return 0
  fi

  # ---- heuristic 1: gmail_signature div ----
  # Capture everything between <div class="gmail_signature" …> and the matching
  # </div>. python is available on macOS by default; use it for tolerant parsing.
  local sig
  sig=$(printf '%s' "$html" | python3 -c '
import re, sys
html = sys.stdin.read()
# Match the gmail_signature wrapper. Be forgiving about attribute order.
m = re.search(
    r"(<div[^>]*class=\"[^\"]*gmail_signature[^\"]*\"[^>]*>)",
    html, re.IGNORECASE)
if not m:
    sys.exit(2)
start = m.start()
# Walk forward, balance <div>/</div> tags.
i = start
depth = 0
out_end = None
for tag in re.finditer(r"<(/?)div\b[^>]*>", html[start:], re.IGNORECASE):
    if tag.group(1) == "":
        depth += 1
    else:
        depth -= 1
        if depth == 0:
            out_end = start + tag.end()
            break
if out_end is None:
    sys.exit(2)
print(html[start:out_end], end="")
' 2>/dev/null) || sig=""

  # ---- heuristic 2: -- separator at bottom of the body ----
  if [[ -z "$sig" ]]; then
    sig=$(printf '%s' "$html" | python3 -c '
import re, sys
html = sys.stdin.read()
# Strip everything up to (and including) the **last** RFC 3676 "-- " marker.
# Look for it as raw text or wrapped in a <div>/<p>.
matches = list(re.finditer(r"(?:^|>)\s*--\s*(<br\s*/?>|<\/p>|\n)", html, re.IGNORECASE))
if not matches:
    sys.exit(2)
last = matches[-1]
print(html[last.start():], end="")
' 2>/dev/null) || sig=""
  fi

  if [[ -z "$sig" ]]; then
    return 1
  fi

  if [[ "$PREVIEW" -eq 1 ]]; then
    {
      echo "── extracted from message $mid ──"
      echo "$sig" | python3 -c 'import sys, html, re; t = sys.stdin.read(); print(re.sub(r"<[^>]+>", " ", html.unescape(t)).strip())' 2>/dev/null \
        | head -c 400
      echo
      echo "── (HTML length: ${#sig} bytes) ──"
    } >&2
  fi

  printf '%s' "$sig"
  return 0
}

if [[ -n "$MESSAGE_ID" ]]; then
  if try_one "$MESSAGE_ID"; then exit 0; fi
  echo "error: could not extract signature from message $MESSAGE_ID" >&2
  exit 1
fi

# Try each candidate in order.
while IFS= read -r mid; do
  [[ -z "$mid" ]] && continue
  if try_one "$mid"; then exit 0; fi
  echo "info: no signature in message $mid — trying next…" >&2
done <<< "$IDS"

echo "error: scanned the 5 most recent sent messages from $ALIAS — no signature block found" >&2
echo "hint:  send one email from this alias in Gmail web UI (which inlines the signature) then retry" >&2
exit 1
