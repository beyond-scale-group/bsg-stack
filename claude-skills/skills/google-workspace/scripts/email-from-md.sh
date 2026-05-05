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
# Keep pandoc's skylighting on — we inline GitHub-flavored colors per
# token class in the Python pass below so code blocks render with
# syntax color in Gmail/Outlook (they normally strip <style> blocks
# but inline styles survive).
RAW_HTML=$(pandoc -f markdown -t html --wrap=none "$MARKDOWN_FILE")

# ---------- inline CSS for Gmail rendering ----------
# Gmail strips <style> blocks — every visual rule must live on the tag
# itself. We use a Python pass for tag rewriting so we can reason about
# attribute lists instead of fighting sed regex collisions (the previous
# sed approach silently emitted duplicated `style="..."` attributes on
# <th>/<td> when the bare and attribute-bearing patterns both matched).
STYLED_HTML=$(printf '%s' "$RAW_HTML" | python3 -c '
import re, sys

html = sys.stdin.read()

# ---------------------------------------------------------------- 1. tag CSS
# Inline-CSS rules applied to specific tags. Each rule is the CSS string
# to be merged into the existing `style=""` attribute (or added as a
# fresh `style="..."` when none exists). Order is purely declarative.
RULES = {
    "table":      "border-collapse:collapse;border:1px solid #ccc;margin:12px 0;font-family:Arial,sans-serif;font-size:13px;",
    "th":         "background:#f4f4f4;border:1px solid #ccc;padding:8px 10px;text-align:left;font-weight:600;",
    "td":         "border:1px solid #ccc;padding:8px 10px;vertical-align:top;",
    "blockquote": "border-left:3px solid #ccc;padding:6px 12px;margin:12px 0;color:#444;background:#fafafa;",
    "h1":         "font-family:Arial,sans-serif;font-size:24px;font-weight:600;margin:18px 0 8px 0;line-height:1.25;",
    "h2":         "font-family:Arial,sans-serif;font-size:20px;font-weight:600;margin:16px 0 8px 0;line-height:1.25;",
    "h3":         "font-family:Arial,sans-serif;font-size:16px;font-weight:600;margin:14px 0 6px 0;line-height:1.25;",
    "h4":         "font-family:Arial,sans-serif;font-size:14px;font-weight:600;margin:12px 0 6px 0;line-height:1.25;",
    "pre":        "background:#f6f8fa;border:1px solid #e1e4e8;border-radius:4px;padding:10px 12px;margin:12px 0;font-family:Menlo,Consolas,monospace;font-size:12px;line-height:1.45;overflow-x:auto;color:#24292e;",
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

# ---------------------------------------------------------------- 2. syntax
# GitHub-flavored token colors for pandoc skylighting `<span class="…">`
# wrappers inside fenced code blocks. Pandoc emits two-letter class
# names (kw=keyword, st=string, co=comment, fu=function, …); Gmail
# strips the matching <style> block, so we map each class to an inline
# `style="color:…"` here.
SKYLIGHTING_COLORS = {
    "kw": "#d73a49",  # keyword (def, class, function …)
    "cf": "#d73a49",  # control flow (return, if, while)
    "im": "#d73a49",  # import
    "pp": "#d73a49",  # preprocessor / decorator
    "op": "#d73a49",  # operator (=, ->, +)
    "st": "#032f62",  # string literal
    "ss": "#032f62",  # special string (f-string body)
    "sc": "#005cc5",  # special char inside string (e.g. {…} in f-string)
    "vs": "#032f62",  # verbatim string
    "ch": "#005cc5",  # character literal
    "co": "#6a737d",  # comment
    "do": "#6a737d",  # documentation comment
    "an": "#6a737d",  # annotation
    "cv": "#6a737d",  # comment variable
    "fu": "#6f42c1",  # function call
    "at": "#6f42c1",  # attribute (CLI flag, decorator)
    "bu": "#005cc5",  # builtin
    "dt": "#005cc5",  # datatype
    "cn": "#005cc5",  # constant
    "dv": "#005cc5",  # decimal value
    "bn": "#005cc5",  # binary value
    "fl": "#005cc5",  # float
    "va": "#e36209",  # variable
    "ot": "#22863a",  # other token
    "er": "#cb2431",  # error
    "wa": "#b08800",  # warning
}

def merge_style_attr(rest: str, css: str) -> str:
    """Add or extend a style attribute on a tag attribute list.

    `rest` is whatever the TAG_RE captured between the tag name and the
    closing `>`. When the tag had no attributes the regex captured the
    empty string, so we must always emit a leading space before the
    new `style="…"` attribute — otherwise `<li>` becomes
    `<listyle="…">` (broken HTML, browsers ignore the style).
    """
    sm = re.search(r"\bstyle\s*=\s*\"([^\"]*)\"", rest, re.IGNORECASE)
    if sm:
        existing = sm.group(1).strip()
        sep = "" if existing.endswith(";") or not existing else ";"
        merged = existing + sep + css
        return rest[: sm.start(1)] + merged + rest[sm.end(1):]
    # No existing style attribute. Detect XHTML self-closing slash and
    # emit `[<existing-attrs>] style="…"` with a guaranteed leading
    # space so it never collides with the tag name.
    body = rest.rstrip()
    self_close = ""
    if body.endswith("/"):
        body = body[:-1].rstrip()
        self_close = " /"
    return f"{body} style=\"{css}\"{self_close}"

def style_open_tag(tag_match: re.Match) -> str:
    tag = tag_match.group(1).lower()
    rest = tag_match.group(2)
    css = RULES.get(tag)
    if css is None:
        return tag_match.group(0)
    return f"<{tag}{merge_style_attr(rest, css)}>"

# Apply tag-level CSS to every opening tag once.
TAG_RE = re.compile(r"<([a-zA-Z][a-zA-Z0-9]*)((?:\s[^>]*)?)>")
html = TAG_RE.sub(style_open_tag, html)

# ---------------------------------------------------------------- 3. spans
# Match `<span class="kw">` / `<span class="kw foo">` and inject the
# matching color. Multiple classes are tolerated; the first matching
# class wins.
def style_highlight_span(m: re.Match) -> str:
    classes = m.group(1).split()
    for cls in classes:
        color = SKYLIGHTING_COLORS.get(cls)
        if color:
            return f"<span style=\"color:{color};\">"
    return m.group(0)

html = re.sub(
    r"<span class=\"([^\"]+)\">",
    style_highlight_span,
    html,
)

# ---------------------------------------------------------------- 4. cleanup
# Strip pandoc'\''s line-number anchors inside fenced code blocks — these
# are `<a href="#cb1-2" aria-hidden="true" tabindex="-1"></a>` markers
# that are clickable "go to line N" links in pandoc HTML but completely
# inert (and visually noisy) inside an email.
html = re.sub(
    r"<a [^>]*href=\"#cb\d+-\d+\"[^>]*>\s*</a>",
    "",
    html,
)

# Replace pandoc'\''s task-list `<input type="checkbox">` markers with
# Unicode glyphs (☑ checked, ☐ unchecked). Gmail/Outlook render the
# raw <input> as a non-interactive control or strip it entirely; the
# Unicode form is consistent across every email client.
html = re.sub(
    r"<input [^>]*type=\"checkbox\"[^>]*checked[^>]*/?>",
    "<span style=\"font-family:monospace;\">☑</span>&nbsp;",
    html,
)
html = re.sub(
    r"<input [^>]*type=\"checkbox\"[^>]*/?>",
    "<span style=\"font-family:monospace;\">☐</span>&nbsp;",
    html,
)

sys.stdout.write(html)
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
