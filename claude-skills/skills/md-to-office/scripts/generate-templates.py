#!/usr/bin/env python3
"""
Generate brand/templates/ from brand/tokens.json.

Creates:
  brand/templates/reference.docx   DOCX reference-doc with brand heading colours
  brand/templates/template.pptx    PowerPoint with brand theme + title slide
  brand/templates/template.xlsx    Excel with brand-coloured header row

Requires: python-docx, python-pptx, openpyxl
Run scripts/install-local.sh to install all three.
"""

from __future__ import annotations

import json
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path.cwd()
TEMPLATES = ROOT / "brand" / "templates"


# ---------------------------------------------------------------------------
# Colour helpers
# ---------------------------------------------------------------------------

def _hex_to_rgb(h: str) -> tuple[int, int, int]:
    h = h.lstrip("#")
    return int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16)


def _darken(h: str, pct: float = 0.25) -> str:
    r, g, b = _hex_to_rgb(h)
    return "#{:02x}{:02x}{:02x}".format(
        int(r * (1 - pct)), int(g * (1 - pct)), int(b * (1 - pct))
    )


def _lighten(h: str, pct: float = 0.85) -> str:
    r, g, b = _hex_to_rgb(h)
    return "#{:02x}{:02x}{:02x}".format(
        int(r + (255 - r) * pct),
        int(g + (255 - g) * pct),
        int(b + (255 - b) * pct),
    )


# ---------------------------------------------------------------------------
# DOCX
# ---------------------------------------------------------------------------

def _generate_docx(tokens: dict) -> None:
    from docx import Document  # type: ignore
    from docx.shared import Pt, RGBColor  # type: ignore

    primary = tokens["colors"]["primary"]
    font_name = tokens["fonts"]["primary"]
    r, g, b = _hex_to_rgb(primary)
    h2_r, h2_g, h2_b = _hex_to_rgb(_darken(primary, 0.15))
    h3_r, h3_g, h3_b = _hex_to_rgb(_darken(primary, 0.35))

    # Bootstrap from pandoc's default reference.docx so the XML structure
    # is already what pandoc expects.
    doc: Document
    with tempfile.NamedTemporaryFile(suffix=".docx", delete=False) as tmp:
        tmp_path = Path(tmp.name)

    result = subprocess.run(
        ["pandoc", "--print-default-data-file", "reference.docx"],
        capture_output=True,
    )
    if result.returncode == 0 and result.stdout:
        tmp_path.write_bytes(result.stdout)
        doc = Document(str(tmp_path))
    else:
        doc = Document()
    tmp_path.unlink(missing_ok=True)

    for style_name, rgb, size_pt, bold in [
        ("Heading 1", (r, g, b),             18, True),
        ("Heading 2", (h2_r, h2_g, h2_b),    14, True),
        ("Heading 3", (h3_r, h3_g, h3_b),    12, True),
    ]:
        try:
            style = doc.styles[style_name]
            style.font.color.rgb = RGBColor(*rgb)
            style.font.bold = bold
            style.font.size = Pt(size_pt)
            style.font.name = font_name
        except (KeyError, Exception):
            pass

    try:
        normal = doc.styles["Normal"]
        normal.font.size = Pt(11)
        normal.font.name = font_name
    except (KeyError, Exception):
        pass

    out = TEMPLATES / "reference.docx"
    doc.save(str(out))
    print(f"  ✓ {out.relative_to(ROOT)}")


# ---------------------------------------------------------------------------
# PPTX
# ---------------------------------------------------------------------------

def _generate_pptx(tokens: dict) -> None:
    from pptx import Presentation  # type: ignore
    from pptx.dml.color import RGBColor  # type: ignore
    from pptx.oxml.ns import qn  # type: ignore
    from pptx.util import Emu, Pt  # type: ignore
    from lxml import etree  # type: ignore

    primary = tokens["colors"]["primary"]
    name = tokens.get("name", "Project")
    primary_no_hash = primary.lstrip("#")

    prs = Presentation()
    prs.slide_width  = Emu(9144000)   # 10 in
    prs.slide_height = Emu(5143500)   # 5.625 in

    # Apply primary to the slide master's theme colour scheme (accent1 + dk1).
    for master in prs.slide_masters:
        clr_scheme = master.element.find(".//" + qn("a:clrScheme"))
        if clr_scheme is None:
            continue
        for tag in (qn("a:dk1"), qn("a:accent1")):
            elem = clr_scheme.find(tag)
            if elem is None:
                continue
            # Remove existing colour children (sysClr / srgbClr) and replace.
            for child in list(elem):
                elem.remove(child)
            srgb = etree.SubElement(elem, qn("a:srgbClr"))
            srgb.set("val", primary_no_hash)

    # Title slide — layout 0 is always "Title Slide" in the default theme.
    slide = prs.slides.add_slide(prs.slide_layouts[0])
    title_ph = slide.shapes.title
    if title_ph is not None:
        title_ph.text = name
        run = title_ph.text_frame.paragraphs[0].runs[0]
        run.font.color.rgb = RGBColor(*_hex_to_rgb(primary))
        run.font.size = Pt(36)

    out = TEMPLATES / "template.pptx"
    prs.save(str(out))
    print(f"  ✓ {out.relative_to(ROOT)}")


# ---------------------------------------------------------------------------
# XLSX
# ---------------------------------------------------------------------------

def _generate_xlsx(tokens: dict) -> None:
    from openpyxl import Workbook  # type: ignore
    from openpyxl.styles import Alignment, Border, Font, PatternFill, Side  # type: ignore

    primary = tokens["colors"]["primary"].lstrip("#")
    font_name = tokens["fonts"]["primary"]
    light_hex = _lighten("#" + primary, 0.93).lstrip("#")

    wb = Workbook()
    ws = wb.active
    ws.title = "Data"

    header_fill   = PatternFill("solid", fgColor=primary)
    header_font   = Font(bold=True, color="FFFFFF", name=font_name)
    body_font     = Font(name=font_name)
    alt_fill      = PatternFill("solid", fgColor=light_hex)
    thin          = Side(style="thin", color="DDDDDD")
    border        = Border(left=thin, right=thin, top=thin, bottom=thin)
    center        = Alignment(horizontal="center", vertical="center")

    for col, header in enumerate(["Column A", "Column B", "Column C"], start=1):
        cell = ws.cell(row=1, column=col, value=header)
        cell.fill   = header_fill
        cell.font   = header_font
        cell.border = border
        cell.alignment = center
        ws.column_dimensions[cell.column_letter].width = 20

    ws.row_dimensions[1].height = 22

    for row in range(2, 6):
        for col in range(1, 4):
            cell = ws.cell(row=row, column=col, value=f"Sample {row - 1}-{col}")
            cell.font   = body_font
            cell.border = border
            if row % 2 == 0:
                cell.fill = alt_fill

    out = TEMPLATES / "template.xlsx"
    wb.save(str(out))
    print(f"  ✓ {out.relative_to(ROOT)}")


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

def main() -> None:
    tokens_path = ROOT / "brand" / "tokens.json"
    if not tokens_path.exists():
        print(f"Error: {tokens_path} not found. Run scan-brand.py first.", file=sys.stderr)
        sys.exit(1)

    tokens = json.loads(tokens_path.read_text())
    TEMPLATES.mkdir(parents=True, exist_ok=True)

    errors: list[str] = []

    for label, fn in [
        ("DOCX",  _generate_docx),
        ("PPTX",  _generate_pptx),
        ("XLSX",  _generate_xlsx),
    ]:
        try:
            fn(tokens)
        except ImportError as e:
            errors.append(f"{label}: missing dep — {e}. Run scripts/install-local.sh.")
        except Exception as e:
            errors.append(f"{label}: generation failed — {e}")

    if errors:
        for msg in errors:
            print(f"  ⚠️  {msg}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
