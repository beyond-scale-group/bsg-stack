#!/usr/bin/env python3
"""Minimal YAML profile parser for onboard-laptop.

Reads a profile YAML and emits a flat, shell-friendly listing on stdout
so the bash and PowerShell drivers can consume it without depending on
`yq` or any third-party YAML library.

Output format — one record per line, tab-separated:

    SECTION\tVALUE[\tEXTRA]

Sections emitted:

    brew              <pkg>
    brew_cask         <pkg>
    winget            <pkg-id>
    winget_apps       <pkg-id>
    npm_global        <pkg>
    pip_global        <pkg>
    mas               <id>\t<name>
    post_install      <command verbatim>
    accounts          <name>\t<url>\t<notes-or-empty>
    security          <token>
    meta              name\t<profile-name>
    meta              description\t<profile-description>

Unknown top-level keys are emitted as:

    warn              unknown key: <key>

Designed to be vendored — no third-party deps, stdlib only.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path


def _strip_comment(line: str) -> str:
    out: list[str] = []
    in_single = False
    in_double = False
    for ch in line:
        if ch == "'" and not in_double:
            in_single = not in_single
        elif ch == '"' and not in_single:
            in_double = not in_double
        elif ch == "#" and not in_single and not in_double:
            break
        out.append(ch)
    return "".join(out).rstrip()


def _unquote(value: str) -> str:
    value = value.strip()
    if len(value) >= 2 and value[0] == value[-1] and value[0] in {"'", '"'}:
        return value[1:-1]
    return value


_INLINE_DICT_RE = re.compile(r"^\{(.*)\}$")


def _parse_inline_dict(value: str) -> dict[str, str]:
    """Parse '{ k: v, k2: "v2" }'. No nesting, no escapes."""
    inner = _INLINE_DICT_RE.match(value.strip())
    if not inner:
        return {}
    payload = inner.group(1)
    pairs: dict[str, str] = {}
    cur: list[str] = []
    depth = 0
    in_single = False
    in_double = False
    parts: list[str] = []
    for ch in payload:
        if ch == "'" and not in_double:
            in_single = not in_single
        elif ch == '"' and not in_single:
            in_double = not in_double
        elif ch in "[{":
            depth += 1
        elif ch in "]}":
            depth -= 1
        if ch == "," and depth == 0 and not in_single and not in_double:
            parts.append("".join(cur))
            cur = []
            continue
        cur.append(ch)
    if cur:
        parts.append("".join(cur))
    for part in parts:
        if ":" not in part:
            continue
        key, _, val = part.partition(":")
        pairs[key.strip()] = _unquote(val)
    return pairs


def _indent_of(line: str) -> int:
    return len(line) - len(line.lstrip(" "))


def parse(text: str) -> list[tuple[str, list[str]]]:
    """Return [(section, args), ...] in the order keys appear."""
    raw_lines = text.splitlines()
    # First pass: drop pure-comment / blank lines but keep line numbers stable
    # for error messages.
    lines: list[tuple[int, str]] = []
    for i, raw in enumerate(raw_lines, start=1):
        stripped = _strip_comment(raw)
        if not stripped.strip():
            continue
        lines.append((i, stripped))

    emit: list[tuple[str, list[str]]] = []
    known_scalar_keys = {"name", "description"}
    known_list_keys = {
        "brew",
        "brew_cask",
        "winget",
        "winget_apps",
        "npm_global",
        "pip_global",
        "post_install",
        "security",
    }
    known_object_list_keys = {"mas", "accounts"}
    known_keys = known_scalar_keys | known_list_keys | known_object_list_keys

    idx = 0
    while idx < len(lines):
        lineno, line = lines[idx]
        if _indent_of(line) != 0:
            idx += 1
            continue
        if ":" not in line:
            idx += 1
            continue

        key, _, rest = line.partition(":")
        key = key.strip()
        rest = rest.strip()

        if key in known_scalar_keys:
            emit.append(("meta", [key, _unquote(rest)]))
            idx += 1
            continue

        if key not in known_keys:
            emit.append(("warn", [f"unknown key: {key}"]))
            # skip its subtree
            idx += 1
            while idx < len(lines) and _indent_of(lines[idx][1]) > 0:
                idx += 1
            continue

        # List-valued keys; collect indented children
        idx += 1
        children: list[str] = []
        child_objs: list[dict[str, str]] = []
        while idx < len(lines) and _indent_of(lines[idx][1]) > 0:
            _, child = lines[idx]
            stripped = child.strip()
            if not stripped.startswith("-"):
                idx += 1
                continue
            item = stripped[1:].strip()
            if item.startswith("{"):
                child_objs.append(_parse_inline_dict(item))
            else:
                children.append(_unquote(item))
            idx += 1

        if key in known_list_keys:
            for c in children:
                emit.append((key, [c]))
        elif key == "mas":
            for obj in child_objs:
                emit.append(("mas", [obj.get("id", ""), obj.get("name", "")]))
        elif key == "accounts":
            for obj in child_objs:
                emit.append(
                    (
                        "accounts",
                        [
                            obj.get("name", ""),
                            obj.get("url", ""),
                            obj.get("notes", ""),
                        ],
                    )
                )

    return emit


def main(argv: list[str]) -> int:
    if len(argv) != 2 or argv[1] in ("-h", "--help"):
        sys.stderr.write("usage: _parse-profile.py <profile.yml>\n")
        return 2
    path = Path(argv[1])
    if not path.is_file():
        sys.stderr.write(f"error: profile not found: {path}\n")
        return 2
    try:
        records = parse(path.read_text(encoding="utf-8"))
    except Exception as exc:  # noqa: BLE001
        sys.stderr.write(f"error: failed to parse {path}: {exc}\n")
        return 2
    for section, args in records:
        sys.stdout.write("\t".join([section, *args]) + "\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
