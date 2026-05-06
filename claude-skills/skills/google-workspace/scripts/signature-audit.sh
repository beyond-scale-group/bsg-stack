#!/usr/bin/env bash
# signature-audit.sh — read-only audit of Gmail sendAs aliases & signatures.
#
# Lists every sendAs entry on the authenticated account (primary login +
# custom "from" aliases) and reports, per alias:
#
#   - sendAsEmail / displayName / replyToAddress
#   - isPrimary / isDefault / treatAsAlias / verificationStatus
#   - signature: configured (Y/N), length, HTML-vs-plain hint, first 80 chars
#   - signature heuristic warnings (no <a>/no contact info/looks empty)
#
# Output modes:
#   --format table  (default) human-readable table with status column
#   --format json   raw merge of sendAs.list + per-alias verdict
#   --format yaml   the same merge as YAML
#
# Exit codes:
#   0   audit ran; every alias has a non-empty signature
#   1   audit ran; one or more aliases are missing a signature
#       OR carry a plain-text signature (no HTML markers)
#   2   gws / jq / auth missing — could not run the audit
#
# Pure read — never modifies any alias. Use signature-set.sh to fix gaps.
#
# Usage:
#   bash signature-audit.sh
#   bash signature-audit.sh --format json | jq '.aliases[] | select(.signature_set==false)'
#   bash signature-audit.sh --alias me@example.com    # narrow to one alias
#   bash signature-audit.sh --quiet                   # exit codes only
#
# Part of the BSG google-workspace skill.

set -uo pipefail

# ---------- defaults ----------
FORMAT="table"
QUIET=0
FILTER_ALIAS=""

usage() { sed -n '2,33p' "$0" | sed 's/^# \{0,1\}//'; exit 0; }

# ---------- parse args ----------
while [[ $# -gt 0 ]]; do
  case "$1" in
    --format)  FORMAT="$2"; shift 2 ;;
    --alias)   FILTER_ALIAS="$2"; shift 2 ;;
    --quiet)   QUIET=1; shift ;;
    -h|--help) usage ;;
    *) echo "error: unknown flag $1" >&2; exit 2 ;;
  esac
done

case "$FORMAT" in
  table|json|yaml) ;;
  *) echo "error: --format must be one of: table, json, yaml" >&2; exit 2 ;;
esac

# ---------- preflight ----------
command -v gws >/dev/null || { echo "error: gws not installed (npm install -g @googleworkspace/cli@latest)" >&2; exit 2; }
command -v jq  >/dev/null || { echo "error: jq not installed (brew install jq)" >&2; exit 2; }

if ! gws auth status 2>/dev/null | jq -e '.token_valid == true' >/dev/null; then
  echo "error: gws auth invalid — run scripts/auth-login.sh" >&2
  exit 2
fi

# ---------- fetch sendAs list ----------
RAW=$(gws gmail users settings sendAs list --params '{"userId":"me"}' 2>/dev/null) \
  || { echo "error: failed to fetch sendAs list (scope gmail.settings.basic?)" >&2; exit 2; }

# Optional filter to a single alias.
if [[ -n "$FILTER_ALIAS" ]]; then
  RAW=$(printf '%s' "$RAW" | jq --arg a "$FILTER_ALIAS" '{sendAs: [.sendAs[] | select(.sendAsEmail == $a)]}')
  if [[ "$(printf '%s' "$RAW" | jq '.sendAs | length')" == "0" ]]; then
    echo "error: alias not found: $FILTER_ALIAS" >&2
    echo "hint:  $(gws gmail users settings sendAs list --params '{\"userId\":\"me\"}' | jq -r '.sendAs[].sendAsEmail' | paste -sd, -)" >&2
    exit 2
  fi
fi

# ---------- per-alias verdict ----------
# For each entry compute a small status object that the formatters share.
VERDICT=$(printf '%s' "$RAW" | jq '
  .sendAs |= map(
    . as $a |
    ($a.signature // "")             as $sig |
    ($sig | length)                  as $len |
    ($sig | test("<[a-zA-Z]"))       as $has_html |
    ($sig | test("href="))           as $has_link |
    ($sig | gsub("<[^>]*>"; "") | gsub("&nbsp;"; " ") | sub("^[[:space:]]+"; "") | sub("[[:space:]]+$"; ""))
                                     as $plain |
    ($plain | length)                as $plain_len |
    {
      sendAsEmail:        $a.sendAsEmail,
      displayName:        ($a.displayName // ""),
      replyToAddress:     ($a.replyToAddress // ""),
      isPrimary:          ($a.isPrimary // false),
      isDefault:          ($a.isDefault // false),
      treatAsAlias:       ($a.treatAsAlias // false),
      verificationStatus: ($a.verificationStatus // ""),
      signature:          $sig,
      signature_set:      ($len > 0),
      signature_length:   $len,
      signature_is_html:  $has_html,
      signature_has_link: $has_link,
      signature_preview:  ($plain[0:80]),
      warnings: (
        ([] +
          (if $len == 0          then ["signature_missing"]      else [] end) +
          (if $len > 0 and ($has_html | not) then ["plain_text_only"] else [] end) +
          (if $len > 0 and $plain_len < 5  then ["empty_after_strip"] else [] end) +
          (if $a.isPrimary and ($a.displayName // "" | length) == 0 then ["primary_missing_display_name"] else [] end)
        )
      )
    }
  )
')

# ---------- compute exit code from verdicts ----------
MISSING_COUNT=$(printf '%s' "$VERDICT" | jq '[.sendAs[] | select(.signature_set == false)] | length')
PLAIN_COUNT=$(printf '%s' "$VERDICT"   | jq '[.sendAs[] | select(.signature_set == true and .signature_is_html == false)] | length')
TOTAL=$(printf '%s' "$VERDICT"          | jq '.sendAs | length')

EXIT_CODE=0
[[ "$MISSING_COUNT" -gt 0 || "$PLAIN_COUNT" -gt 0 ]] && EXIT_CODE=1

# ---------- emit ----------
if [[ "$QUIET" -eq 1 ]]; then
  exit "$EXIT_CODE"
fi

case "$FORMAT" in
  json)
    printf '%s\n' "$VERDICT" | jq '{
      total_aliases: (.sendAs | length),
      missing_signature_count: ([.sendAs[] | select(.signature_set == false)] | length),
      plain_text_signature_count: ([.sendAs[] | select(.signature_set == true and .signature_is_html == false)] | length),
      aliases: (.sendAs | map(del(.signature)) )
    }'
    ;;
  yaml)
    if command -v yq >/dev/null 2>&1; then
      printf '%s\n' "$VERDICT" | jq '.sendAs | map(del(.signature))' | yq -P -
    else
      # Fall back to JSON with a notice if yq isn't installed.
      printf '# yq not installed — falling back to JSON\n' >&2
      printf '%s\n' "$VERDICT" | jq '.sendAs | map(del(.signature))'
    fi
    ;;
  table)
    # Width-padded, ANSI-color-free table that fits in a terminal.
    printf '\nGmail sendAs audit — %d alias(es)\n' "$TOTAL"
    printf '%s\n' "----------------------------------------------------------------------"
    printf '%-32s %-7s %-7s %-7s %-9s %s\n' \
      "ALIAS" "PRIMARY" "DEFAULT" "HTML" "VERIFIED" "STATUS"
    printf '%s\n' "----------------------------------------------------------------------"
    printf '%s' "$VERDICT" | jq -r '.sendAs[] |
      [
        .sendAsEmail,
        (if .isPrimary then "yes" else "—" end),
        (if .isDefault then "yes" else "—" end),
        (if .signature_set then (if .signature_is_html then "yes" else "plain" end) else "—" end),
        (if .verificationStatus == "" then "n/a" else .verificationStatus end),
        (
          if (.warnings | length) == 0 then "ok"
          else (.warnings | join(","))
          end
        )
      ] | @tsv' \
    | while IFS=$'\t' read -r email primary default html verified status; do
        printf '%-32s %-7s %-7s %-7s %-9s %s\n' \
          "$email" "$primary" "$default" "$html" "$verified" "$status"
      done

    # Per-alias details.
    echo
    printf '%s' "$VERDICT" | jq -r '.sendAs[] |
      "── \(.sendAsEmail) ──",
      "  displayName       : \(.displayName // "(unset)")",
      "  replyToAddress    : \(.replyToAddress // "(unset)")",
      "  signature length  : \(.signature_length) chars",
      "  signature is HTML : \(.signature_is_html)",
      "  signature has link: \(.signature_has_link)",
      "  preview           : \(.signature_preview // "(empty)")",
      ""'

    # Summary footer.
    printf '%s\n' "----------------------------------------------------------------------"
    if [[ "$EXIT_CODE" -eq 0 ]]; then
      printf '✓ all %d alias(es) have an HTML signature\n' "$TOTAL"
    else
      [[ "$MISSING_COUNT" -gt 0 ]] && printf '⚠ %d alias(es) missing a signature\n' "$MISSING_COUNT"
      [[ "$PLAIN_COUNT"   -gt 0 ]] && printf '⚠ %d alias(es) have a plain-text signature (no HTML)\n' "$PLAIN_COUNT"
      printf '\nFix with:\n'
      printf '  bash scripts/signature-extract.sh --alias <ALIAS>   # pull HTML from a recent sent email\n'
      printf '  bash scripts/signature-set.sh     --alias <ALIAS> --from-latest-sent\n'
      printf '  bash scripts/signature-set.sh     --alias <ALIAS> --html-file ./sig.html\n'
    fi
    ;;
esac

exit "$EXIT_CODE"
