#!/usr/bin/env python3
"""
Scan the current repo for brand signals and emit a brand/tokens.json
(JSON to stdout; info to stderr).

Resolution priority per signal type:

  name:    brand/NARRATIVE.md H1 > package.json > pyproject.toml >
           stack.yaml > README.md H1 > git remote name
  primary: brand/tokens.json (existing partial) >
           CSS custom properties > tailwind.config.* >
           design-token JSON files > default #1a1a2e
  font:    CSS font-family > default "Helvetica Neue"
"""

from __future__ import annotations

import json
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path.cwd()

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _first_re(text: str, patterns: list[str], flags: int = re.IGNORECASE) -> str | None:
    for p in patterns:
        m = re.search(p, text, flags)
        if m:
            return m.group(1).strip()
    return None


def _normalize_hex(raw: str) -> str:
    """Return '#rrggbb' from any 3- or 6-char hex string (with or without #)."""
    h = raw.strip().lstrip("#")
    if len(h) == 3:
        h = "".join(c * 2 for c in h)
    return f"#{h.lower()}" if len(h) == 6 else f"#{h}"


def _iter_files(*globs: str, skip_dirs: tuple[str, ...] = (".git", "node_modules", ".venv", "__pycache__")):
    for pattern in globs:
        for path in ROOT.rglob(pattern):
            if any(d in path.parts for d in skip_dirs):
                continue
            if path.is_file():
                yield path


# ---------------------------------------------------------------------------
# Name detection
# ---------------------------------------------------------------------------

def _scan_name() -> str:
    # 1. brand/NARRATIVE.md first H1
    narrative = ROOT / "brand" / "NARRATIVE.md"
    if narrative.exists():
        m = re.search(r"^#\s+(.+)$", narrative.read_text(errors="replace"), re.MULTILINE)
        if m:
            return m.group(1).strip()

    # 2. package.json
    pkg = ROOT / "package.json"
    if pkg.exists():
        try:
            data = json.loads(pkg.read_text())
            if "name" in data and data["name"]:
                return data["name"]
        except Exception:
            pass

    # 3. pyproject.toml
    pyp = ROOT / "pyproject.toml"
    if pyp.exists():
        text = pyp.read_text(errors="replace")
        # Try tomllib (Python ≥3.11) first, then regex.
        try:
            import tomllib  # type: ignore
            data = tomllib.loads(text)
            name = (
                data.get("project", {}).get("name")
                or data.get("tool", {}).get("poetry", {}).get("name")
            )
            if name:
                return name
        except (ImportError, Exception):
            m = re.search(r'^name\s*=\s*"([^"]+)"', text, re.MULTILINE)
            if m:
                return m.group(1)

    # 4. stack.yaml
    stack = ROOT / "stack.yaml"
    if stack.exists():
        m = re.search(r"^name\s*:\s*(.+)$", stack.read_text(errors="replace"), re.MULTILINE)
        if m:
            return m.group(1).strip()

    # 5. README.md first H1
    readme = ROOT / "README.md"
    if readme.exists():
        m = re.search(r"^#\s+(.+)$", readme.read_text(errors="replace"), re.MULTILINE)
        if m:
            return m.group(1).strip()

    # 6. Git remote repo name
    try:
        remote = subprocess.check_output(
            ["git", "remote", "get-url", "origin"],
            text=True,
            stderr=subprocess.DEVNULL,
        ).strip()
        name = re.sub(r"\.git$", "", re.split(r"[/:]", remote)[-1])
        if name:
            return name
    except Exception:
        pass

    return "project"


# ---------------------------------------------------------------------------
# Primary colour detection
# ---------------------------------------------------------------------------

_HEX_RE = r"#([0-9a-fA-F]{6}|[0-9a-fA-F]{3})"

_CSS_PATTERNS = [
    r"--(?:color-)?primary(?:-color)?\s*:\s*" + _HEX_RE,
    r"--brand-(?:primary|color)\s*:\s*" + _HEX_RE,
    r"--(?:theme-)?primary\s*:\s*" + _HEX_RE,
    r"--main-color\s*:\s*" + _HEX_RE,
]


def _scan_primary() -> str:
    # CSS / SCSS / Less files
    for f in _iter_files("*.css", "*.scss", "*.less"):
        text = f.read_text(errors="replace")
        for pat in _CSS_PATTERNS:
            m = re.search(pat, text, re.IGNORECASE)
            if m:
                return _normalize_hex(m.group(1))

    # tailwind.config.{js,ts,cjs,mjs}
    for tc in ROOT.glob("tailwind.config.*"):
        if tc.suffix not in (".js", ".ts", ".cjs", ".mjs"):
            continue
        text = tc.read_text(errors="replace")
        # theme.colors.primary: '#xxx' or "xxx"
        m = re.search(
            r"primary\s*:\s*['\"]#?([0-9a-fA-F]{3,6})['\"]", text, re.IGNORECASE
        )
        if m:
            return _normalize_hex(m.group(1))

    # Design-token / theme JSON files
    TOKEN_GLOBS = ("tokens.json", "theme.json", "colors.json", "brand.json")
    TOKEN_PATHS = [
        ["colors", "primary"],
        ["color", "primary"],
        ["primary"],
        ["brand", "primary"],
        ["brand", "colors", "primary"],
    ]
    for glob in TOKEN_GLOBS:
        for f in ROOT.glob(glob):
            try:
                data = json.loads(f.read_text())
                for path in TOKEN_PATHS:
                    val: object = data
                    for key in path:
                        if isinstance(val, dict) and key in val:
                            val = val[key]
                        else:
                            val = None
                            break
                    if isinstance(val, str) and re.match(
                        r"#?[0-9a-fA-F]{3,6}$", val.strip()
                    ):
                        return _normalize_hex(val.strip())
            except Exception:
                continue

    # Default: BSG dark navy
    return "#1a1a2e"


# ---------------------------------------------------------------------------
# Font detection
# ---------------------------------------------------------------------------

def _scan_font() -> str:
    _FONT_PATTERNS = [
        r"--font-(?:family-)?(?:primary|base|body)\s*:\s*([^;\n]{3,80})",
        r"--(?:primary-|brand-)?font(?:-family)?\s*:\s*([^;\n]{3,80})",
    ]
    for f in _iter_files("*.css", "*.scss"):
        text = f.read_text(errors="replace")
        for pat in _FONT_PATTERNS:
            m = re.search(pat, text, re.IGNORECASE)
            if m:
                # Take only the first font in a stack, strip quotes and whitespace.
                family = m.group(1).strip().split(",")[0].strip(" '\"")
                if 2 < len(family) < 60 and family not in ("inherit", "initial", "unset"):
                    return family
    return "Helvetica Neue"


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

def main() -> None:
    # Merge with existing partial tokens.json if present.
    existing: dict = {}
    tokens_path = ROOT / "brand" / "tokens.json"
    if tokens_path.exists():
        try:
            existing = json.loads(tokens_path.read_text())
            print(f"Merging with existing {tokens_path.relative_to(ROOT)}", file=sys.stderr)
        except Exception:
            pass

    name    = existing.get("name")    or _scan_name()
    primary = existing.get("colors", {}).get("primary") or _scan_primary()
    font    = existing.get("fonts",  {}).get("primary") or _scan_font()

    tokens = {
        "name":   name,
        "colors": {"primary": primary},
        "fonts":  {"primary": font},
    }

    print(json.dumps(tokens, indent=2, ensure_ascii=False))
    print(f"  name:    {name}",    file=sys.stderr)
    print(f"  primary: {primary}", file=sys.stderr)
    print(f"  font:    {font}",    file=sys.stderr)


if __name__ == "__main__":
    main()
