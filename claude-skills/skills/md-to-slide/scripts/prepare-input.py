#!/usr/bin/env python3
"""
Prepare a markdown file for Marp conversion without mutating the source.

Writes a copy to the given output path, ensuring the YAML front matter
carries the Marp directives the deck needs:

  - marp: true        (added if missing)
  - paginate: true    (added if missing)
  - footer: <text>    (added if --footer given and no footer already set)

Existing front matter keys are never overwritten — the author's own
directives always win.

Usage:
    python3 prepare-input.py <input.md> <output.md> [--footer TEXT]
"""
import re
import sys
from pathlib import Path

_FRONTMATTER_RE = re.compile(r"\A---\s*\n(.*?)\n---\s*\n", re.DOTALL)


def main() -> int:
    args = sys.argv[1:]
    footer = ""
    if "--footer" in args:
        i = args.index("--footer")
        footer = args[i + 1]
        del args[i : i + 2]

    if len(args) != 2:
        print(__doc__, file=sys.stderr)
        return 1

    src, dst = Path(args[0]), Path(args[1])
    text = src.read_text(encoding="utf-8")

    m = _FRONTMATTER_RE.match(text)
    existing = m.group(1) if m else ""
    body = text[m.end():] if m else text

    def has_key(key: str) -> bool:
        return re.search(rf"^{key}\s*:", existing, re.MULTILINE) is not None

    additions = []
    if not has_key("marp"):
        additions.append("marp: true")
    if not has_key("paginate"):
        additions.append("paginate: true")
    if footer and not has_key("footer"):
        additions.append(f'footer: "{footer}"')

    frontmatter = "\n".join(filter(None, [existing.strip(), *additions]))
    dst.write_text(f"---\n{frontmatter}\n---\n\n{body}", encoding="utf-8")
    return 0


if __name__ == "__main__":
    sys.exit(main())
