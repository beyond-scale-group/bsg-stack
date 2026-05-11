#!/usr/bin/env bash
# parse-plan.sh — parse PLAN.md into JSON plan items with bindings.
#
# Reads PLAN.md (default: resolved via `_bsg-paths.sh` → `.bsg/PLAN.md`
# with `po/PLAN.md` legacy fallback per ADR-001; override with
# `--plan <path>`) and emits a JSON array. Each object describes one
# bullet that carries at least one binding tag. See
# `references/plan-schema.md` for the grammar.
#
# Default output (backward-compatible):
#
#   [{"raw": "...", "bindings": {...}, ...}, ...]
#
# With `--typed`, output is an object that distinguishes three states:
#
#   {"status": "ok",          "items": [ ... ]}
#   {"status": "missing",     "items": [], "reason": "..."}
#   {"status": "unparseable", "items": [], "reason": "..."}
#
# `missing`     — PLAN.md does not exist
# `unparseable` — PLAN.md exists but contains zero bullets with binding tags
#                 (format drift — was masquerading as "planFound: false" per #128)
# `ok`          — at least one bound plan item parsed
#
# If PLAN.md is missing in default mode, emits an empty array "[]" —
# NOT an error — so legacy downstream adherence can still run.
set -euo pipefail

PLAN_PATH=""
TYPED=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --plan)  PLAN_PATH="$2"; shift 2 ;;
    --typed) TYPED=1; shift ;;
    *) echo "parse-plan.sh: unknown arg: $1" >&2; exit 2 ;;
  esac
done

if [[ -z "$PLAN_PATH" ]]; then
  # Source the shared resolver so the default tracks ADR-001 (`.bsg/`
  # preferred, legacy fallback) without every caller having to know.
  # shellcheck source=../../../scripts/_bsg-paths.sh disable=SC1091
  source "$(dirname "$0")/../../../scripts/_bsg-paths.sh"
  PLAN_PATH="$PWD/$(bsg_doc_path plan)"
fi

if [[ ! -f "$PLAN_PATH" ]]; then
  if [[ $TYPED -eq 1 ]]; then
    jq -n --arg path "$PLAN_PATH" '{
      status: "missing",
      items: [],
      reason: ($path + " does not exist")
    }'
  else
    echo '[]'
  fi
  exit 0
fi

# We do the parse in python3 — the tag grammar involves nested brackets
# and multiple bindings per bullet, which gets fiddly in pure bash.
python3 - "$PLAN_PATH" "$TYPED" <<'PY'
import json
import re
import sys
from pathlib import Path

path = Path(sys.argv[1])
typed = sys.argv[2] == "1"
text = path.read_text()

# One tag: [kind:value]. Kinds we recognise; everything else is preserved
# as a free-form tag under `tags`.
TAG_RE = re.compile(r"\[([a-zA-Z0-9_#:.\- /]+)\]")
# `#<num>` shorthand, treated as epic binding.
ISSUE_SHORTHAND_RE = re.compile(r"^#\d+$")

def classify(tag: str) -> tuple[str, str]:
    if ":" in tag:
        kind, _, value = tag.partition(":")
        return kind, value
    if ISSUE_SHORTHAND_RE.fullmatch(tag):
        return "epic", tag
    return "tag", tag

items = []
current_section: str | None = None

for lineno, raw_line in enumerate(text.splitlines(), start=1):
    stripped = raw_line.strip()

    # Track section headings (H2) so each item remembers where it came from.
    if stripped.startswith("## "):
        current_section = stripped[3:].strip()
        continue

    # Only bullets are candidates. Support `-`, `*`, and numbered bullets.
    if not re.match(r"^\s*([-*]|\d+\.)\s+", raw_line):
        continue

    tags_found = TAG_RE.findall(raw_line)
    if not tags_found:
        continue

    bindings = {"milestones": [], "epics": [], "labels": []}
    tags: list[str] = []

    # Strip the leading bullet marker + a single leading space.
    body = re.sub(r"^\s*([-*]|\d+\.)\s+", "", raw_line)
    # Remove tag brackets from the prose copy so `raw` reads cleanly.
    body_no_tags = TAG_RE.sub("", body).strip()

    for tag in tags_found:
        kind, value = classify(tag)
        if kind == "milestone":
            bindings["milestones"].append(value)
        elif kind == "epic":
            v = value.lstrip("#")
            try:
                bindings["epics"].append(int(v))
            except ValueError:
                # Not a plain number — keep it in tags so the writer sees it,
                # but don't create a broken binding.
                tags.append(tag)
        elif kind == "label":
            bindings["labels"].append(value)
        else:
            tags.append(tag)

    items.append(
        {
            "raw": body_no_tags,
            "section": current_section,
            "bindings": bindings,
            "tags": tags,
            "line": lineno,
        }
    )

if typed:
    if not items:
        out = {
            "status": "unparseable",
            "items": [],
            "reason": (
                f"{path} exists but contains zero bullets with recognised "
                "binding tags. See references/plan-schema.md for the grammar."
            ),
        }
    else:
        out = {"status": "ok", "items": items}
    json.dump(out, sys.stdout, indent=2)
else:
    json.dump(items, sys.stdout, indent=2)
sys.stdout.write("\n")
PY
