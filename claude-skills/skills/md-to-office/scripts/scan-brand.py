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
  font:    CSS font-family > @font-face > Google Fonts import >
           default "Helvetica Neue"

Optional --audit <path> writes a markdown summary of all signals found.
"""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from datetime import date
from pathlib import Path

ROOT = Path.cwd()

# ---------------------------------------------------------------------------
# Audit log
# ---------------------------------------------------------------------------

_audit_log: list[tuple[str, str, str]] = []
_defaults_applied: list[str] = []


def _audit(signal: str, source: str, value: str) -> None:
    _audit_log.append((signal, source, value))


def _default_applied(signal: str) -> None:
    _defaults_applied.append(signal)


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


_SKIP_DIRS = (".git", "node_modules", ".venv", "__pycache__", "dist", "build", ".next")


def _iter_files(*globs: str, skip_dirs: tuple[str, ...] = _SKIP_DIRS):
    for pattern in globs:
        for path in ROOT.rglob(pattern):
            if any(d in path.parts for d in skip_dirs):
                continue
            if path.is_file():
                yield path


def _rel(path: Path) -> str:
    try:
        return str(path.relative_to(ROOT))
    except ValueError:
        return str(path)


# ---------------------------------------------------------------------------
# Name detection
# ---------------------------------------------------------------------------

def _scan_name() -> str:
    # NARRATIVE.md path follows ADR-001: prefer `.bsg/NARRATIVE.md`,
    # fall back to legacy `brand/NARRATIVE.md`.
    narrative = ROOT / ".bsg" / "NARRATIVE.md"
    legacy_narrative = ROOT / "brand" / "NARRATIVE.md"
    if not narrative.exists() and legacy_narrative.exists():
        narrative = legacy_narrative
    if narrative.exists():
        m = re.search(r"^#\s+(.+)$", narrative.read_text(errors="replace"), re.MULTILINE)
        if m:
            val = m.group(1).strip()
            _audit("name", f"{narrative.relative_to(ROOT)} H1", val)
            return val

    pkg = ROOT / "package.json"
    if pkg.exists():
        try:
            data = json.loads(pkg.read_text())
            if "name" in data and data["name"]:
                _audit("name", "package.json", data["name"])
                return data["name"]
        except Exception:
            pass

    pyp = ROOT / "pyproject.toml"
    if pyp.exists():
        text = pyp.read_text(errors="replace")
        try:
            import tomllib  # type: ignore
            data = tomllib.loads(text)
            name = (
                data.get("project", {}).get("name")
                or data.get("tool", {}).get("poetry", {}).get("name")
            )
            if name:
                _audit("name", "pyproject.toml", name)
                return name
        except (ImportError, Exception):
            m = re.search(r'^name\s*=\s*"([^"]+)"', text, re.MULTILINE)
            if m:
                _audit("name", "pyproject.toml", m.group(1))
                return m.group(1)

    stack = ROOT / "stack.yaml"
    if stack.exists():
        m = re.search(r"^name\s*:\s*(.+)$", stack.read_text(errors="replace"), re.MULTILINE)
        if m:
            val = m.group(1).strip()
            _audit("name", "stack.yaml", val)
            return val

    readme = ROOT / "README.md"
    if readme.exists():
        m = re.search(r"^#\s+(.+)$", readme.read_text(errors="replace"), re.MULTILINE)
        if m:
            val = m.group(1).strip()
            _audit("name", "README.md H1", val)
            return val

    try:
        remote = subprocess.check_output(
            ["git", "remote", "get-url", "origin"],
            text=True,
            stderr=subprocess.DEVNULL,
        ).strip()
        name = re.sub(r"\.git$", "", re.split(r"[/:]", remote)[-1])
        if name:
            _audit("name", "git remote", name)
            return name
    except Exception:
        pass

    _default_applied("name")
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


# Tailwind v4 uses @theme { --color-*-NNN: #hex; } instead of tailwind.config.js.
# We look for the -500 or -600 scale stop (the typical anchor/primary shade) inside
# @theme blocks. Files under apps/.../src/ are preferred over public/ demo HTML.

_THEME_BLOCK_RE = re.compile(
    r"@theme\s*\{([^}]*)\}",
    re.DOTALL | re.IGNORECASE,
)

# Prefer the mid-range scale stops as the "primary" anchor color.
_THEME_SCALE_PRIORITY = ("500", "600", "700", "400", "300", "DEFAULT")


def _priority_key(path: Path) -> int:
    """Lower value = higher priority. app source CSS wins over public/ demo HTML."""
    parts = path.parts
    if "public" in parts:
        return 2
    # apps/*/src/**  or  src/**  — real app CSS
    if "src" in parts:
        return 0
    return 1


def _scan_primary() -> str:
    # --- Step 1: Tailwind v4 @theme block detection (highest priority) --------
    css_files = sorted(
        _iter_files("*.css", "*.scss", "*.less"),
        key=_priority_key,
    )
    for f in css_files:
        text = f.read_text(errors="replace")
        for block_m in _THEME_BLOCK_RE.finditer(text):
            block = block_m.group(1)
            # Collect all --color-*-NNN: #hex lines in this block.
            color_hits: dict[str, str] = {}
            for line_m in re.finditer(
                r"--color-[a-z0-9-]+-(" + "|".join(_THEME_SCALE_PRIORITY) + r")\s*:\s*#([0-9a-fA-F]{3,6})",
                block,
                re.IGNORECASE,
            ):
                scale_stop = line_m.group(1)
                hex_val = line_m.group(2)
                if scale_stop not in color_hits:
                    color_hits[scale_stop] = hex_val
            # Pick the best scale stop in priority order.
            for stop in _THEME_SCALE_PRIORITY:
                if stop in color_hits:
                    val = _normalize_hex(color_hits[stop])
                    _audit("primary", f"Tailwind v4 @theme in {_rel(f)}", val)
                    return val

    # --- Step 2: Classic CSS custom property patterns -------------------------
    for f in css_files:
        text = f.read_text(errors="replace")
        for pat in _CSS_PATTERNS:
            m = re.search(pat, text, re.IGNORECASE)
            if m:
                val = _normalize_hex(m.group(1))
                _audit("primary", f"CSS variable in {_rel(f)}", val)
                return val

    for tc in ROOT.glob("tailwind.config.*"):
        if tc.suffix not in (".js", ".ts", ".cjs", ".mjs"):
            continue
        text = tc.read_text(errors="replace")
        m = re.search(
            r"primary\s*:\s*['\"]#?([0-9a-fA-F]{3,6})['\"]", text, re.IGNORECASE
        )
        if m:
            val = _normalize_hex(m.group(1))
            _audit("primary", f"Tailwind config {_rel(tc)}", val)
            return val

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
                        result = _normalize_hex(val.strip())
                        _audit("primary", f"design token in {_rel(f)}", result)
                        return result
            except Exception:
                continue

    _default_applied("primary")
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
                family = m.group(1).strip().split(",")[0].strip(" '\"")
                if 2 < len(family) < 60 and family not in ("inherit", "initial", "unset"):
                    _audit("font", f"CSS variable in {_rel(f)}", family)
                    return family

    for f in _iter_files("*.css", "*.scss"):
        text = f.read_text(errors="replace")
        m = re.search(r"@font-face\s*\{[^}]*font-family\s*:\s*['\"]?([^'\";\}]+)", text)
        if m:
            family = m.group(1).strip()
            if 2 < len(family) < 60:
                _audit("font", f"@font-face in {_rel(f)}", family)
                return family

    for f in _iter_files("*.css", "*.scss", "*.html"):
        text = f.read_text(errors="replace")
        m = re.search(r"fonts\.googleapis\.com/css2?\?family=([^&\"'\s)]+)", text)
        if m:
            family = m.group(1).replace("+", " ").split(":")[0]
            if family:
                _audit("font", f"Google Fonts import in {_rel(f)}", family)
                return family

    _default_applied("font")
    return "Helvetica Neue"


# ---------------------------------------------------------------------------
# Logo detection
# ---------------------------------------------------------------------------

def _scan_logos() -> list[str]:
    logo_dirs = ("public", "brand", "images", "assets", "static", "img")
    logo_exts = (".svg", ".png", ".jpg", ".jpeg", ".webp")
    results: list[str] = []

    for d in logo_dirs:
        dir_path = ROOT / d
        if not dir_path.is_dir():
            continue
        for f in dir_path.rglob("*"):
            if any(skip in f.parts for skip in _SKIP_DIRS):
                continue
            if not f.is_file():
                continue
            if f.suffix.lower() not in logo_exts:
                continue
            if "logo" in f.stem.lower():
                results.append(_rel(f))

    for ext in logo_exts:
        for f in ROOT.glob(f"*logo*{ext}"):
            if f.is_file():
                rel = _rel(f)
                if rel not in results:
                    results.append(rel)

    results.sort()
    for r in results:
        _audit("logo", r, "found")
    return results


# ---------------------------------------------------------------------------
# Identity / voice documents
# ---------------------------------------------------------------------------

def _scan_identity_docs() -> list[str]:
    # `.bsg/` paths preferred over legacy per ADR-001.
    candidates = [
        ".bsg/NARRATIVE.md",
        ".bsg/DESIGN.md",
        "brand/NARRATIVE.md",
        "brand/identity.md",
        "DESIGN.md",
    ]
    results: list[str] = []

    for c in candidates:
        if (ROOT / c).exists():
            results.append(c)

    for f in _iter_files("*identity*.md", "*DESIGN*.md", "*design-system*.md"):
        rel = _rel(f)
        if rel not in results:
            results.append(rel)

    results.sort()
    for r in results:
        _audit("identity", r, "found")
    return results


# ---------------------------------------------------------------------------
# Existing Office templates
# ---------------------------------------------------------------------------

def _scan_existing_templates() -> list[str]:
    results: list[str] = []
    for f in _iter_files("*.docx", "*.pptx", "*.xlsx"):
        results.append(_rel(f))
    results.sort()
    for r in results:
        _audit("existing_template", r, "found")
    return results


# ---------------------------------------------------------------------------
# Audit report
# ---------------------------------------------------------------------------

def _generate_audit(tokens: dict, audit_path: Path) -> None:
    lines: list[str] = []
    name = tokens["name"]
    lines.append(f"# Brand Audit — {name}")
    lines.append("")
    lines.append(f"Generated by `md-to-office --init` on {date.today().isoformat()}.")
    lines.append("")

    lines.append("## Chosen tokens")
    lines.append("")
    lines.append("| Token | Value | Source |")
    lines.append("|---|---|---|")

    source_map: dict[str, str] = {}
    for signal, source, _value in _audit_log:
        if signal not in source_map:
            source_map[signal] = source

    name_src = source_map.get("name", "default")
    primary_src = source_map.get("primary", "default")
    font_src = source_map.get("font", "default")

    lines.append(f"| Name | {tokens['name']} | {name_src} |")
    lines.append(f"| Primary color | `{tokens['colors']['primary']}` | {primary_src} |")
    lines.append(f"| Font | {tokens['fonts']['primary']} | {font_src} |")
    lines.append("")

    lines.append("## Discovery details")
    lines.append("")

    sections: dict[str, list[tuple[str, str]]] = {}
    for signal, source, value in _audit_log:
        sections.setdefault(signal, []).append((source, value))

    section_labels = {
        "name": "Project name",
        "primary": "Primary color",
        "font": "Typography",
        "logo": "Logo files",
        "identity": "Identity documents",
        "existing_template": "Existing Office templates",
    }

    for key in ("name", "primary", "font", "logo", "identity", "existing_template"):
        label = section_labels.get(key, key)
        lines.append(f"### {label}")
        lines.append("")
        entries = sections.get(key, [])
        if entries:
            for source, value in entries:
                lines.append(f"- {source}" + (f" → `{value}`" if value != "found" else ""))
        else:
            lines.append("- (none found)")
        lines.append("")

    if _defaults_applied:
        lines.append("## Defaults applied")
        lines.append("")
        default_labels = {
            "name": "Name → `project`",
            "primary": "Primary color → `#1a1a2e` (BSG dark navy)",
            "font": "Font → `Helvetica Neue`",
        }
        for d in _defaults_applied:
            lines.append(f"- {default_labels.get(d, d)}")
        lines.append("")
    else:
        lines.append("## Defaults applied")
        lines.append("")
        lines.append("(none — all signals found in repo)")
        lines.append("")

    audit_path.parent.mkdir(parents=True, exist_ok=True)
    audit_path.write_text("\n".join(lines))
    print(f"  Audit written to {_rel(audit_path)}", file=sys.stderr)


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

def main() -> None:
    parser = argparse.ArgumentParser(description="Scan repo for brand signals")
    parser.add_argument("--audit", metavar="PATH", help="Write brand audit markdown to PATH")
    args = parser.parse_args()

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

    logos = _scan_logos()
    identity_docs = _scan_identity_docs()
    existing_templates = _scan_existing_templates()

    tokens = {
        "name":   name,
        "colors": {"primary": primary},
        "fonts":  {"primary": font},
        "logos":  logos,
        "identity_docs": identity_docs,
        "existing_templates": existing_templates,
    }

    print(json.dumps(tokens, indent=2, ensure_ascii=False))
    print(f"  name:    {name}",    file=sys.stderr)
    print(f"  primary: {primary}", file=sys.stderr)
    print(f"  font:    {font}",    file=sys.stderr)

    if args.audit:
        _generate_audit(tokens, Path(args.audit))


if __name__ == "__main__":
    main()
