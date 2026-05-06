#!/usr/bin/env bash
# email-md-send.sh — end-to-end "markdown → Gmail-ready HTML → send/draft".
#
# Wraps email-from-md.sh (markdown → styled HTML body + signature) and
# `gws gmail +send` (auth + delivery) into one ergonomic command.
#
# Usage:
#   bash email-md-send.sh \
#     --markdown ./memo.md \
#     --to alice@example.com \
#     --subject 'Q2 recap' \
#     --from me@bsg-holding.fr \
#     --draft        # save as draft (default — never sends without --send)
#
#   # Actually deliver instead of drafting:
#   bash email-md-send.sh ... --send
#
#   # Multiple recipients + cc/bcc:
#   bash email-md-send.sh ... \
#     --to 'alice@example.com,bob@example.com' \
#     --cc carol@example.com --bcc archives@example.com
#
#   # Skip the alias signature (e.g. transactional emails):
#   bash email-md-send.sh ... --no-signature
#
# Behaviour:
#   - Validates the --from alias exists on the account; warns if its
#     signature is missing (run signature-audit.sh / signature-set.sh).
#   - Renders markdown via email-from-md.sh (tables/blockquotes inlined).
#   - Defaults to --draft for safety; only delivers when --send is set.
#   - Returns the gws send/draft response on stdout.
#
# Flags:
#   --markdown FILE       (required) markdown source
#   --to EMAILS           (required) comma-separated
#   --subject STRING      (required)
#   --from EMAIL          (recommended) alias to send from + signature source
#   --cc EMAILS           comma-separated
#   --bcc EMAILS          comma-separated
#   --draft               save as draft (default)
#   --send                actually send (asks for confirmation unless --yes)
#   --yes                 skip confirmation prompt
#   --no-signature        do not append the alias signature
#   --reply-to EMAIL      add a Reply-To header (raw API path)
#
# Exit codes:
#   0  draft created or message sent
#   1  user declined / send failed
#   2  preflight failure (gws/jq/pandoc missing, auth invalid, bad flag)
#
# Part of the BSG google-workspace skill.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ---------- defaults ----------
MD_FILE=""
TO=""
SUBJECT=""
FROM=""
CC=""
BCC=""
DRAFT=1            # default to draft for safety
SEND=0
YES=0
NO_SIGNATURE=0
REPLY_TO=""

usage() { sed -n '2,49p' "$0" | sed 's/^# \{0,1\}//'; exit 0; }

# ---------- parse args ----------
while [[ $# -gt 0 ]]; do
  case "$1" in
    --markdown)     MD_FILE="$2"; shift 2 ;;
    --to)           TO="$2"; shift 2 ;;
    --subject)      SUBJECT="$2"; shift 2 ;;
    --from)         FROM="$2"; shift 2 ;;
    --cc)           CC="$2"; shift 2 ;;
    --bcc)          BCC="$2"; shift 2 ;;
    --draft)        DRAFT=1; SEND=0; shift ;;
    --send)         DRAFT=0; SEND=1; shift ;;
    --yes|-y)       YES=1; shift ;;
    --no-signature) NO_SIGNATURE=1; shift ;;
    --reply-to)     REPLY_TO="$2"; shift 2 ;;
    -h|--help)      usage ;;
    *) echo "error: unknown flag $1" >&2; exit 2 ;;
  esac
done

# ---------- preflight ----------
[[ -n "$MD_FILE" ]] || { echo "error: --markdown FILE is required" >&2; exit 2; }
[[ -f "$MD_FILE" ]] || { echo "error: file not found: $MD_FILE" >&2; exit 2; }
[[ -n "$TO" ]]      || { echo "error: --to EMAILS is required" >&2; exit 2; }
[[ -n "$SUBJECT" ]] || { echo "error: --subject STRING is required" >&2; exit 2; }

command -v gws    >/dev/null || { echo "error: gws not installed" >&2; exit 2; }
command -v jq     >/dev/null || { echo "error: jq not installed (brew install jq)" >&2; exit 2; }
command -v pandoc >/dev/null || { echo "error: pandoc not installed (brew install pandoc)" >&2; exit 2; }

if ! gws auth status 2>/dev/null | jq -e '.token_valid == true' >/dev/null; then
  echo "error: gws auth invalid — run scripts/auth-login.sh" >&2
  exit 2
fi

# ---------- alias / signature sanity check ----------
if [[ -n "$FROM" ]]; then
  ALIASES=$(gws gmail users settings sendAs list --params '{"userId":"me"}' 2>/dev/null) || ALIASES='{"sendAs":[]}'
  ALIAS_INFO=$(printf '%s' "$ALIASES" | jq --arg a "$FROM" '.sendAs[] | select(.sendAsEmail == $a) // empty')
  if [[ -z "$ALIAS_INFO" ]]; then
    echo "warning: --from $FROM is not a configured sendAs alias on this account." >&2
    echo "         (it will likely fall back to the primary login)" >&2
    echo "hint:    bash $SCRIPT_DIR/signature-audit.sh   # to see your aliases" >&2
  else
    SIG_LEN=$(printf '%s' "$ALIAS_INFO" | jq -r '.signature // "" | length')
    if [[ "$SIG_LEN" -eq 0 && "$NO_SIGNATURE" -eq 0 ]]; then
      echo "warning: alias $FROM has no signature configured (audit shows 0 bytes)." >&2
      echo "         the body will be sent without a signature." >&2
      echo "hint:    bash $SCRIPT_DIR/signature-set.sh --alias $FROM --from-latest-sent" >&2
    fi
  fi
fi

# ---------- render markdown to HTML (delegate to email-from-md.sh) ----------
EMD_ARGS=(--markdown "$MD_FILE")
[[ -n "$FROM" ]]            && EMD_ARGS+=(--from "$FROM")
[[ "$NO_SIGNATURE" -eq 1 ]] && EMD_ARGS+=(--no-signature)

BODY=$(bash "$SCRIPT_DIR/email-from-md.sh" "${EMD_ARGS[@]}") \
  || { echo "error: email-from-md.sh failed to render the markdown" >&2; exit 1; }

[[ -n "$BODY" ]] || { echo "error: rendered HTML body is empty" >&2; exit 1; }

# ---------- summary + confirmation (only on --send) ----------
ACTION_LABEL="DRAFT"
[[ "$SEND" -eq 1 ]] && ACTION_LABEL="SEND"

{
  echo "── email-md-send.sh ──"
  echo "action     : $ACTION_LABEL"
  echo "from       : ${FROM:-(account default)}"
  echo "to         : $TO"
  [[ -n "$CC"       ]] && echo "cc         : $CC"
  [[ -n "$BCC"      ]] && echo "bcc        : $BCC"
  [[ -n "$REPLY_TO" ]] && echo "reply-to   : $REPLY_TO"
  echo "subject    : $SUBJECT"
  echo "body bytes : ${#BODY}"
  echo "── end summary ──"
} >&2

if [[ "$SEND" -eq 1 && "$YES" -eq 0 ]]; then
  printf 'SEND this email for real to %s? [y/N] ' "$TO" >&2
  read -r REPLY
  case "$REPLY" in
    [yY]|[yY][eE][sS]) ;;
    *) echo "aborted — falling back to draft." >&2; SEND=0; DRAFT=1 ;;
  esac
fi

# ---------- choose path: +send (helper) or raw send (when --reply-to is set) ----------
if [[ -n "$REPLY_TO" ]]; then
  # +send doesn't expose Reply-To; build a RFC 2822 message and POST raw.
  TMPMSG=$(mktemp -t email-md-send.XXXXXX)
  trap 'rm -f "$TMPMSG"' EXIT
  {
    [[ -n "$FROM" ]] && printf 'From: %s\r\n' "$FROM"
    printf 'To: %s\r\n' "$TO"
    [[ -n "$CC"  ]] && printf 'Cc: %s\r\n' "$CC"
    [[ -n "$BCC" ]] && printf 'Bcc: %s\r\n' "$BCC"
    printf 'Reply-To: %s\r\n' "$REPLY_TO"
    printf 'Subject: %s\r\n' "$SUBJECT"
    printf 'MIME-Version: 1.0\r\n'
    printf 'Content-Type: text/html; charset=UTF-8\r\n'
    printf '\r\n'
    printf '%s\r\n' "$BODY"
  } > "$TMPMSG"

  RAW=$(base64 < "$TMPMSG" | tr -d '\n' | tr '+/' '-_' | tr -d '=')

  if [[ "$DRAFT" -eq 1 ]]; then
    gws gmail users drafts create --params '{"userId":"me"}' \
      --json "$(jq -nc --arg r "$RAW" '{message: {raw: $r}}')"
  else
    gws gmail users messages send --params '{"userId":"me"}' \
      --json "$(jq -nc --arg r "$RAW" '{raw: $r}')"
  fi
  exit $?
fi

# Standard path — use the +send helper for cleaner ergonomics.
SEND_ARGS=(
  --to "$TO"
  --subject "$SUBJECT"
  --body "$BODY"
  --html
)
[[ -n "$FROM" ]] && SEND_ARGS+=(--from "$FROM")
[[ -n "$CC"   ]] && SEND_ARGS+=(--cc  "$CC")
[[ -n "$BCC"  ]] && SEND_ARGS+=(--bcc "$BCC")
[[ "$DRAFT" -eq 1 ]] && SEND_ARGS+=(--draft)

if RESPONSE=$(gws gmail +send "${SEND_ARGS[@]}" 2>&1); then
  printf '%s\n' "$RESPONSE"
  if [[ "$DRAFT" -eq 1 ]]; then
    echo "✓ draft created — open in Gmail to review and click Send" >&2
  else
    echo "✓ email sent" >&2
  fi
  exit 0
else
  echo "✗ gws gmail +send failed:" >&2
  echo "$RESPONSE" >&2
  exit 1
fi
