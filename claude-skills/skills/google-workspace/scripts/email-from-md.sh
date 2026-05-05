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
# `--no-highlight` strips pandoc's syntax-highlighting <span class="...">
# wrappers — Gmail strips the matching CSS anyway, leaving meaningless
# spans that break copy-paste from the rendered email.
RAW_HTML=$(pandoc -f markdown -t html --wrap=none --no-highlight "$MARKDOWN_FILE")

# ---------- inline CSS for Gmail rendering ----------
# Gmail strips <style> blocks — every visual rule must live on the tag
# itself. We use a Python pass for tag rewriting so we can reason about
# attribute lists instead of fighting sed regex collisions (the previous
# sed approach silently emitted duplicated `style="..."` attributes on
# <th>/<td> when the bare and attribute-bearing patterns both matched).
STYLED_HTML=$(printf '%s' "$RAW_HTML" | python3 -c '
import re, sys

html = sys.stdin.read()

# Inline-CSS rules applied to specific tags.  Each rule is the CSS string
# to be merged into the existing `style=""` attribute (or added as a
# fresh `style="..."` when none exists).  Order is purely declarative.
RULES = {
    "table":      "border-collapse:collapse;border:1px solid #ccc;margin:12px 0;font-family:Arial,sans-serif;font-size:13px;",
    "th":         "background:#f4f4f4;border:1px solid #ccc;padding:8px 10px;text-align:left;font-weight:600;",
    "td":         "border:1px solid #ccc;padding:8px 10px;vertical-align:top;",
    "blockquote": "border-left:3px solid #ccc;padding:6px 12px;margin:12px 0;color:#444;background:#fafafa;",
    "h1":         "font-family:Arial,sans-serif;font-size:24px;font-weight:600;margin:18px 0 8px 0;line-height:1.25;",
    "h2":         "font-family:Arial,sans-serif;font-size:20px;font-weight:600;margin:16px 0 8px 0;line-height:1.25;",
    "h3":         "font-family:Arial,sans-serif;font-size:16px;font-weight:600;margin:14px 0 6px 0;line-height:1.25;",
    "h4":         "font-family:Arial,sans-serif;font-size:14px;font-weight:600;margin:12px 0 6px 0;line-height:1.25;",
    "pre":        "background:#f6f8fa;border:1px solid #e1e4e8;border-radius:4px;padding:10px 12px;margin:12px 0;font-family:Menlo,Consolas,monospace;font-size:12px;line-height:1.45;overflow-x:auto;",
    "code":       "font-family:Menlo,Consolas,monospace;font-size:12px;background:#f6f8fa;padding:1px 4px;border-radius:3px;",
    "hr":         "border:none;border-top:1px solid #e1e4e8;margin:18px 0;",
    "ul":         "margin:8px 0;padding-left:24px;",
    "ol":         "margin:8px 0;padding-left:24px;",
    "li":         "margin:4px 0;",
    "img":        "max-width:100%;height:auto;border:0;",
    "dl":         "margin:8px 0;",
    "dt":         "font-weight:600;margin-top:8px;",
    "dd":         "margin:0 0 8px 16px;",
}

def merge_style(tag_match: re.Match) -> str:
    """Inject/merge `style="…"` on a single open tag."""
    tag = tag_match.group(1).lower()
    rest = tag_match.group(2)  # everything between tag name and closing >
    css = RULES.get(tag)
    if css is None:
        return tag_match.group(0)
    # If the tag already has a style attribute, merge by appending.
    style_match = re.search(r"\bstyle\s*=\s*\"([^\"]*)\"", rest, re.IGNORECASE)
    if style_match:
        existing = style_match.group(1).strip()
        sep = "" if existing.endswith(";") or not existing else ";"
        merged = existing + sep + css
        rest_new = (
            rest[: style_match.start(1)] + merged + rest[style_match.end(1):]
        )
        return f"<{tag}{rest_new}>"
    # No existing style — append one before the closing >.
    rest_stripped = rest.rstrip("/").rstrip()
    self_close = "/" if rest.rstrip().endswith("/") else ""
    space = "" if not rest_stripped else " "
    return f"<{tag}{rest_stripped}{space}style=\"{css}\"{self_close}>"

# Match each opening tag exactly once.
TAG_RE = re.compile(r"<([a-zA-Z][a-zA-Z0-9]*)((?:\s[^>]*)?)>")
sys.stdout.write(TAG_RE.sub(merge_style, html))
')

# ---------- post-render cleanup ----------
# Pandoc wraps every figure in <figure>…<figcaption>. Gmail keeps the
# wrapper but renders the caption as orphan text, which is rarely what
# the author wants. Strip the figcaption while keeping the <img>.
STYLED_HTML=$(printf '%s' "$STYLED_HTML" | sed \
  -e 's|<figcaption[^>]*>[^<]*</figcaption>||g' \
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
