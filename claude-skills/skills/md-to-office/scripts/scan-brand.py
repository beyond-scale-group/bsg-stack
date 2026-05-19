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

    # --- Step 3: Style Dictionary / Figma Tokens nested format ---------------
    # Style Dictionary wraps every leaf in { "value": "<hex>" } and nests under
    # categories like color/colors/brand. Figma Tokens (Studio plugin) adds a
    # "type": "color" sibling and groups under "global" / theme names.
    # Both can ship as tokens/**/*.json, *.tokens.json, $themes.json, etc.
    sd_globs = (
        "tokens/**/*.json",
        "design-tokens/**/*.json",
        "tokens.figma.json",
        "figma-tokens.json",
        "*.tokens.json",
        "$themes.json",
    )
    sd_candidates: list[Path] = []
    for pattern in sd_globs:
        for f in ROOT.glob(pattern):
            if any(d in f.parts for d in _SKIP_DIRS):
                continue
            if f.is_file() and f not in sd_candidates:
                sd_candidates.append(f)

    primary_keys = ("primary", "brand", "accent", "main")
    for f in sd_candidates:
        try:
            data = json.loads(f.read_text())
        except Exception:
            continue
        found = _find_token_value(data, primary_keys)
        if found:
            result = _normalize_hex(found)
            _audit("primary", f"Style Dictionary / Figma token in {_rel(f)}", result)
            return result

    _default_applied("primary")
    return "#1a1a2e"


def _find_token_value(node: object, name_hints: tuple[str, ...]) -> str | None:
    """Walk a Style Dictionary / Figma Tokens tree, returning the first hex
    value whose ancestor key matches one of `name_hints`. Leaves are detected
    as dicts that carry a "value" entry (Style Dictionary / Figma convention).
    """
    def _walk(n: object, hint_matched: bool) -> str | None:
        if isinstance(n, dict):
            # Leaf: { "value": "...", "type": "color" } or just { "value": "..." }.
            if "value" in n and isinstance(n["value"], str):
                if hint_matched:
                    raw = n["value"].strip()
                    if re.match(r"#?[0-9a-fA-F]{3,6}$", raw):
                        return raw
                    return None
                # Unmatched leaf — skip.
                return None
            for key, child in n.items():
                key_lc = str(key).lower()
                hit = hint_matched or any(h in key_lc for h in name_hints)
                result = _walk(child, hit)
                if result:
                    return result
        return None

    return _walk(node, hint_matched=False)


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
# Favicon detection
# ---------------------------------------------------------------------------

_FAVICON_DIRS = ("public", "static", "app", "src/app", "brand", "assets", "img")
_FAVICON_EXTS = (".ico", ".svg", ".png", ".webp")
_FAVICON_STEMS = ("favicon", "apple-touch-icon", "apple-icon", "icon")


def _scan_favicons() -> list[str]:
    results: list[str] = []

    def _maybe_add(f: Path) -> None:
        if not f.is_file() or any(skip in f.parts for skip in _SKIP_DIRS):
            return
        if f.suffix.lower() not in _FAVICON_EXTS:
            return
        stem = f.stem.lower()
        # Match canonical names exactly or as a prefix (e.g. icon-192.png),
        # but never "logo-icon" or random "icon"-containing words.
        if stem in _FAVICON_STEMS:
            rel = _rel(f)
            if rel not in results:
                results.append(rel)
            return
        for canonical in _FAVICON_STEMS:
            if stem == canonical or stem.startswith(canonical + "-"):
                rel = _rel(f)
                if rel not in results:
                    results.append(rel)
                return

    for d in _FAVICON_DIRS:
        dir_path = ROOT / d
        if not dir_path.is_dir():
            continue
        for f in dir_path.rglob("*"):
            _maybe_add(f)

    # Top-level favicon.ico / favicon.svg (common in Next.js / Astro repos).
    for ext in _FAVICON_EXTS:
        for stem in _FAVICON_STEMS:
            f = ROOT / f"{stem}{ext}"
            if f.exists():
                _maybe_add(f)

    results.sort()
    for r in results:
        _audit("favicon", r, "found")
    return results


# ---------------------------------------------------------------------------
# Open Graph / social share images
# ---------------------------------------------------------------------------

_OG_DIRS = ("public", "static", "app", "src/app", "brand", "assets", "img", "images")
_OG_EXTS = (".png", ".jpg", ".jpeg", ".webp", ".svg")
_OG_STEM_HINTS = (
    "og-image",
    "ogimage",
    "opengraph-image",
    "opengraph",
    "og",
    "twitter-image",
    "twitter-card",
    "social-card",
    "social-share",
)


def _scan_og_images() -> list[str]:
    results: list[str] = []

    def _stem_matches(stem: str) -> bool:
        s = stem.lower()
        for hint in _OG_STEM_HINTS:
            if s == hint or s.startswith(hint + "-") or s.startswith(hint + "."):
                return True
        return False

    for d in _OG_DIRS:
        dir_path = ROOT / d
        if not dir_path.is_dir():
            continue
        for f in dir_path.rglob("*"):
            if any(skip in f.parts for skip in _SKIP_DIRS):
                continue
            if not f.is_file() or f.suffix.lower() not in _OG_EXTS:
                continue
            if _stem_matches(f.stem):
                rel = _rel(f)
                if rel not in results:
                    results.append(rel)

    # Top-level og-image.* / opengraph-image.* (Next.js 13+ App Router convention).
    for ext in _OG_EXTS:
        for f in ROOT.glob(f"*{ext}"):
            if _stem_matches(f.stem):
                rel = _rel(f)
                if rel not in results:
                    results.append(rel)

    results.sort()
    for r in results:
        _audit("og_image", r, "found")
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
        "favicon": "Favicons",
        "og_image": "Open Graph images",
        "identity": "Identity documents",
        "existing_template": "Existing Office templates",
    }

    for key in ("name", "primary", "font", "logo", "favicon", "og_image", "identity", "existing_template"):
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
# DESIGN.md — Google Stitch design-system spec
# ---------------------------------------------------------------------------
#
# https://blog.google/innovation-and-ai/models-and-research/google-labs/stitch-design-md/
#
# Emits a first-draft `.bsg/DESIGN.md` from the same deterministic scan that
# feeds tokens.json. Colors and typography are sourced from the scan; the
# spacing, components and accessibility sections are scaffolded with
# documented defaults and explicit review markers — the document is meant to
# be opened as a PR for human review, not treated as final.


def _rgb(hex_color: str) -> tuple[int, int, int]:
    h = hex_color.lstrip("#")
    if len(h) != 6:
        h = "1a1a2e"
    return int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16)


def _mix(hex_color: str, target: int, ratio: float) -> str:
    """Blend each channel toward `target` (0=black, 255=white) by `ratio`."""
    r, g, b = _rgb(hex_color)
    nr = round(r + (target - r) * ratio)
    ng = round(g + (target - g) * ratio)
    nb = round(b + (target - b) * ratio)
    return f"#{nr:02x}{ng:02x}{nb:02x}"


def _relative_luminance(hex_color: str) -> float:
    def _chan(c: int) -> float:
        s = c / 255.0
        return s / 12.92 if s <= 0.04045 else ((s + 0.055) / 1.055) ** 2.4

    r, g, b = _rgb(hex_color)
    return 0.2126 * _chan(r) + 0.7152 * _chan(g) + 0.0722 * _chan(b)


def _contrast_ratio(fg: str, bg: str) -> float:
    l1, l2 = _relative_luminance(fg), _relative_luminance(bg)
    lighter, darker = max(l1, l2), min(l1, l2)
    return (lighter + 0.05) / (darker + 0.05)


def _format_asset_rows(label: str, items: list[str]) -> list[str]:
    if not items:
        return [f"- **{label}** — _none detected. Add to the repo and re-run "
                "`md-to-office.sh --init` to refresh._"]
    rows = [f"- **{label}**"]
    for item in items:
        rows.append(f"  - `{item}`")
    return rows


def _generate_design_md(tokens: dict, design_path: Path) -> None:
    name = tokens["name"]
    primary = tokens["colors"]["primary"]
    font = tokens["fonts"]["primary"]
    logos = tokens.get("logos", [])
    favicons = tokens.get("favicons", [])
    og_images = tokens.get("og_images", [])

    accent = _mix(primary, 255, 0.25)
    bg = "#ffffff"
    surface = _mix(primary, 255, 0.96)
    text = "#1a1a2e"
    muted = _mix(text, 255, 0.45)

    text_on_bg = _contrast_ratio(text, bg)
    primary_on_bg = _contrast_ratio(primary, bg)

    def _aa(ratio: float) -> str:
        if ratio >= 7.0:
            return "AAA"
        if ratio >= 4.5:
            return "AA"
        if ratio >= 3.0:
            return "AA (large text only)"
        return "FAIL — adjust before shipping"

    lines: list[str] = [
        f"# {name} — Design System",
        "",
        "<!--",
        "  Generated by `md-to-office --init` (scan-brand.py) on "
        f"{date.today().isoformat()}.",
        "  Format: Google Stitch DESIGN.md open specification —",
        "  https://blog.google/innovation-and-ai/models-and-research/google-labs/stitch-design-md/",
        "",
        "  This is a first draft derived from a deterministic repo scan",
        "  (CSS variables, Tailwind config, design tokens, logos). Colors and",
        "  typography reflect what was detected; spacing, components and",
        "  accessibility carry documented defaults. Review and edit before use —",
        "  `brand/tokens.json` is derived from this file, not the other way round.",
        "-->",
        "",
        "## Colors",
        "",
        "| Role | Value | Purpose |",
        "|---|---|---|",
        f"| `primary` | `{primary}` | Primary brand color — CTAs, links, "
        "active state |",
        f"| `accent` | `{accent}` | Accent / hover — derived from primary |",
        f"| `background` | `{bg}` | Page background |",
        f"| `surface` | `{surface}` | Cards, panels — tinted from primary |",
        f"| `text` | `{text}` | Default body text |",
        f"| `text-muted` | `{muted}` | Secondary / caption text |",
        "",
        "> Derived shades are computed from the detected primary color. "
        "Replace with the team's exact palette where it differs.",
        "",
        "## Typography",
        "",
        "| Usage | Family | Weight | Size | Line height |",
        "|---|---|---|---|---|",
        f"| Heading | {font} | 700 | 2rem / 1.5rem / 1.25rem | 1.2 |",
        f"| Body | {font} | 400 | 1rem | 1.5 |",
        f"| Caption | {font} | 400 | 0.875rem | 1.4 |",
        "| Code | ui-monospace, SFMono-Regular, monospace | 400 | 0.875rem "
        "| 1.5 |",
        "",
        "## Spacing & layout",
        "",
        "- **Scale** (rem): `0.25 · 0.5 · 0.75 · 1 · 1.5 · 2 · 3 · 4`",
        "- **Grid**: 12 columns, 1rem gutter",
        "- **Container max-width**: 72rem",
        "- **Breakpoints**: `sm 640px · md 768px · lg 1024px · xl 1280px`",
        "",
        "<!-- Defaults — confirm against the project's actual layout system. -->",
        "",
        "## Components",
        "",
        "- **Button** — primary uses `primary` bg / `background` text; "
        "radius `0.375rem`; padding `0.5rem 1rem`.",
        "- **Card** — `surface` bg, 1px `text-muted` border, radius "
        "`0.5rem`, padding `1rem`.",
        "- **Form element** — 1px border, `0.375rem` radius, focus ring in "
        "`primary`.",
        "",
        "<!-- Defaults — replace with the project's real component patterns. -->",
        "",
        "## Brand assets",
        "",
        *_format_asset_rows("Logos", logos),
        *_format_asset_rows("Favicons", favicons),
        *_format_asset_rows("Open Graph / social images", og_images),
        "",
        "<!-- Detected by scan-brand.py. Replace placeholders with the team's "
        "canonical assets and re-run `md-to-office.sh --init --force`. -->",
        "",
        "## Accessibility",
        "",
        f"- Body text on background: contrast **{text_on_bg:.1f}:1** "
        f"(WCAG {_aa(text_on_bg)}).",
        f"- Primary on background: contrast **{primary_on_bg:.1f}:1** "
        f"(WCAG {_aa(primary_on_bg)}) — used for large text / icons only "
        "unless it passes AA.",
        "- Focus indicators: visible 2px outline in `primary`, never "
        "removed without a replacement.",
        "- Motion: honor `prefers-reduced-motion`; no essential information "
        "conveyed by motion alone.",
        "",
    ]

    design_path.parent.mkdir(parents=True, exist_ok=True)
    design_path.write_text("\n".join(lines))
    print(f"  DESIGN.md written to {_rel(design_path)}", file=sys.stderr)


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

def main() -> None:
    parser = argparse.ArgumentParser(description="Scan repo for brand signals")
    parser.add_argument("--audit", metavar="PATH", help="Write brand audit markdown to PATH")
    parser.add_argument(
        "--design",
        metavar="PATH",
        help="Write a Google Stitch DESIGN.md design-system spec to PATH",
    )
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
    favicons = _scan_favicons()
    og_images = _scan_og_images()
    identity_docs = _scan_identity_docs()
    existing_templates = _scan_existing_templates()

    tokens = {
        "name":   name,
        "colors": {"primary": primary},
        "fonts":  {"primary": font},
        "logos":  logos,
        "favicons": favicons,
        "og_images": og_images,
        "identity_docs": identity_docs,
        "existing_templates": existing_templates,
    }

    print(json.dumps(tokens, indent=2, ensure_ascii=False))
    print(f"  name:    {name}",    file=sys.stderr)
    print(f"  primary: {primary}", file=sys.stderr)
    print(f"  font:    {font}",    file=sys.stderr)

    if args.audit:
        _generate_audit(tokens, Path(args.audit))

    if args.design:
        _generate_design_md(tokens, Path(args.design))


if __name__ == "__main__":
    main()
