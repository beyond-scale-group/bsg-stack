#!/usr/bin/env bash
# signature-set.sh — write/update the HTML signature on a Gmail sendAs alias.
#
# This is the **only mutating** signature script in the kit. It calls
# `gws gmail users settings sendAs patch` for the targeted alias and
# updates the `signature` field. Optionally also sets `displayName` and
# `replyToAddress`.
#
# Usage:
#   # Apply the latest sent-mail signature for THIS alias to the alias itself
#   bash signature-set.sh --alias me@bsg-holding.fr --from-latest-sent
#
#   # Copy the signature from one alias to another (e.g. unify branding)
#   bash signature-set.sh --alias me@new.com \
#     --from-latest-sent --source-alias me@old.com
#
#   # From a file
#   bash signature-set.sh --alias me@x.com --html-file ./signature.html
#
#   # Inline HTML (for short signatures)
#   bash signature-set.sh --alias me@x.com \
#     --html '<p><strong>Jane Doe</strong><br>CEO · <a href="https://x.com">x.com</a></p>'
#
#   # Read HTML from stdin (useful for piping from extract.sh)
#   bash signature-extract.sh --alias me@old.com \
#     | bash signature-set.sh --alias me@new.com --html-stdin
#
#   # Also set the display name on the same call
#   bash signature-set.sh --alias me@x.com --html-file sig.html \
#     --display-name "Jane Doe"
#
# Flags:
#   --alias EMAIL         (required) sendAs alias to update
#   --html STRING         inline HTML
#   --html-file FILE      load HTML from file
#   --html-stdin          read HTML from stdin
#   --from-latest-sent    auto-extract from the most recent sent message
#   --source-alias EMAIL  alias to extract FROM (default: --alias value)
#   --display-name NAME   also patch displayName
#   --reply-to EMAIL      also patch replyToAddress
#   --dry-run             print the patch body, do nothing
#   --yes                 skip confirmation prompt
#
# Exit codes:
#   0  signature updated (or dry-run rendered)
#   1  user declined / no source signature found
#   2  preflight failure (gws/jq missing, auth invalid, bad flag)
#
# Part of the BSG google-workspace skill.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ---------- defaults ----------
ALIAS=""
HTML=""
HTML_FILE=""
HTML_STDIN=0
FROM_LATEST_SENT=0
SOURCE_ALIAS=""
DISPLAY_NAME=""
REPLY_TO=""
DRY_RUN=0
YES=0

usage() { sed -n '2,50p' "$0" | sed 's/^# \{0,1\}//'; exit 0; }

# ---------- parse args ----------
while [[ $# -gt 0 ]]; do
  case "$1" in
    --alias)            ALIAS="$2"; shift 2 ;;
    --html)             HTML="$2"; shift 2 ;;
    --html-file)        HTML_FILE="$2"; shift 2 ;;
    --html-stdin)       HTML_STDIN=1; shift ;;
    --from-latest-sent) FROM_LATEST_SENT=1; shift ;;
    --source-alias)     SOURCE_ALIAS="$2"; shift 2 ;;
    --display-name)     DISPLAY_NAME="$2"; shift 2 ;;
    --reply-to)         REPLY_TO="$2"; shift 2 ;;
    --dry-run)          DRY_RUN=1; shift ;;
    --yes|-y)           YES=1; shift ;;
    -h|--help)          usage ;;
    *) echo "error: unknown flag $1" >&2; exit 2 ;;
  esac
done

# ---------- preflight ----------
[[ -n "$ALIAS" ]] || { echo "error: --alias EMAIL is required" >&2; exit 2; }
command -v gws >/dev/null || { echo "error: gws not installed" >&2; exit 2; }
command -v jq  >/dev/null || { echo "error: jq not installed (brew install jq)" >&2; exit 2; }

# Exactly one of --html/--html-file/--html-stdin/--from-latest-sent.
SOURCES=$(( ${#HTML} > 0 ? 1 : 0 ))
[[ -n "$HTML_FILE" ]] && SOURCES=$((SOURCES + 1))
[[ "$HTML_STDIN" -eq 1 ]] && SOURCES=$((SOURCES + 1))
[[ "$FROM_LATEST_SENT" -eq 1 ]] && SOURCES=$((SOURCES + 1))

if [[ "$SOURCES" -eq 0 ]]; then
  echo "error: provide one of --html, --html-file, --html-stdin, --from-latest-sent" >&2
  exit 2
fi
if [[ "$SOURCES" -gt 1 ]]; then
  echo "error: --html / --html-file / --html-stdin / --from-latest-sent are mutually exclusive" >&2
  exit 2
fi

if ! gws auth status 2>/dev/null | jq -e '.token_valid == true' >/dev/null; then
  echo "error: gws auth invalid — run scripts/auth-login.sh" >&2
  exit 2
fi

# ---------- resolve the HTML payload ----------
if [[ -n "$HTML_FILE" ]]; then
  [[ -f "$HTML_FILE" ]] || { echo "error: file not found: $HTML_FILE" >&2; exit 2; }
  HTML=$(cat "$HTML_FILE")
elif [[ "$HTML_STDIN" -eq 1 ]]; then
  HTML=$(cat -)
elif [[ "$FROM_LATEST_SENT" -eq 1 ]]; then
  SRC="${SOURCE_ALIAS:-$ALIAS}"
  echo "info: extracting signature from latest sent message of $SRC…" >&2
  HTML=$(bash "$SCRIPT_DIR/signature-extract.sh" --alias "$SRC" 2>&1) \
    || { echo "$HTML"; echo "error: extract failed for $SRC" >&2; exit 1; }
fi

if [[ -z "$HTML" ]]; then
  echo "error: resolved HTML signature is empty" >&2
  exit 1
fi

# ---------- verify the alias exists ----------
EXISTING=$(gws gmail users settings sendAs get \
  --params "$(jq -nc --arg a "$ALIAS" '{userId:"me", sendAsEmail:$a}')" 2>/dev/null) \
  || { echo "error: alias not found on this account: $ALIAS" >&2;
       echo "hint:  bash $SCRIPT_DIR/signature-audit.sh   # to list aliases" >&2;
       exit 2; }

OLD_LEN=$(printf '%s' "$EXISTING" | jq -r '.signature // "" | length')
NEW_LEN=${#HTML}

# ---------- build the patch body ----------
BODY=$(jq -nc --arg sig "$HTML" '{signature: $sig}')
if [[ -n "$DISPLAY_NAME" ]]; then
  BODY=$(printf '%s' "$BODY" | jq --arg dn "$DISPLAY_NAME" '. + {displayName: $dn}')
fi
if [[ -n "$REPLY_TO" ]]; then
  BODY=$(printf '%s' "$BODY" | jq --arg rt "$REPLY_TO" '. + {replyToAddress: $rt}')
fi

PARAMS=$(jq -nc --arg a "$ALIAS" '{userId:"me", sendAsEmail:$a}')

# ---------- summary + confirm ----------
{
  echo "── signature-set.sh ──"
  echo "alias     : $ALIAS"
  echo "old sig   : $OLD_LEN bytes"
  echo "new sig   : $NEW_LEN bytes"
  [[ -n "$DISPLAY_NAME" ]] && echo "displayName → $DISPLAY_NAME"
  [[ -n "$REPLY_TO"     ]] && echo "replyTo     → $REPLY_TO"
  echo "preview (text-only):"
  printf '%s' "$HTML" \
    | python3 -c 'import sys, html, re; t = sys.stdin.read(); print(re.sub(r"<[^>]+>", " ", html.unescape(t)).strip())' 2>/dev/null \
    | head -c 240
  echo
  echo "── end preview ──"
} >&2

if [[ "$DRY_RUN" -eq 1 ]]; then
  echo "DRY-RUN — would call: gws gmail users settings sendAs patch --params '$PARAMS' --json '<body>'" >&2
  printf '%s\n' "$BODY"
  exit 0
fi

if [[ "$YES" -eq 0 ]]; then
  printf 'Apply this signature to %s? [y/N] ' "$ALIAS" >&2
  read -r REPLY
  case "$REPLY" in
    [yY]|[yY][eE][sS]) ;;
    *) echo "aborted." >&2; exit 1 ;;
  esac
fi

# ---------- apply the patch ----------
if RESPONSE=$(gws gmail users settings sendAs patch \
  --params "$PARAMS" --json "$BODY" 2>&1); then
  RESULT_LEN=$(printf '%s' "$RESPONSE" | jq -r '.signature // "" | length' 2>/dev/null || echo "?")
  echo "✓ signature updated for $ALIAS (server stored $RESULT_LEN bytes)"
  exit 0
else
  echo "✗ patch failed:" >&2
  echo "$RESPONSE" >&2
  exit 1
fi
