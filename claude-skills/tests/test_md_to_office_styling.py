#!/usr/bin/env python3
"""Tests for generate-templates.py professional docx styling presets.

Split out of test_md_to_office.py for #330 (single file >500 LOC).
Run individually:

    python3 claude-skills/tests/test_md_to_office_styling.py

Stdlib only; auto-skips when external deps are missing.
"""

from __future__ import annotations

import json
import shutil
import sys
import tempfile
import unittest
from pathlib import Path

from _md_to_office_helpers import (
    GEN_TEMPLATES,
    run,
)


class TestGenerateDocxProfessionalStyling(unittest.TestCase):
    """#266: _generate_docx must produce BPI/investor-grade styling by default.

    Verifies that the generated reference.docx carries:
    - Page margins 2.5 cm on all four sides
    - Normal body: line spacing 1.25, space_after 8pt, body color #2A3340
    - Heading 1: 22pt, space_before 18pt, space_after 8pt
    - Heading 2: 16pt, space_before 14pt, space_after 6pt
    - Heading 3: 13pt, space_before 10pt, space_after 4pt
    - Heading 4: 11pt, italic, muted slate colour
    - Title: 32pt
    - Footer with project name + "Confidentiel"
    """

    # Load the module once at class level so we don't re-import per test.
    _mod = None

    @classmethod
    def _load_mod(cls):
        if cls._mod is not None:
            return cls._mod
        import importlib.util
        spec = importlib.util.spec_from_file_location(
            "generate_templates", str(GEN_TEMPLATES)
        )
        mod = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(mod)
        cls._mod = mod
        return mod

    def setUp(self) -> None:
        try:
            import docx  # noqa: F401
        except ImportError:
            self.skipTest("python-docx not installed; run scripts/install-local.sh")
        self.tmp = Path(tempfile.mkdtemp(prefix="bsg-docx-style-"))
        brand = self.tmp / "brand"
        brand.mkdir()
        tokens = {
            "name": "TestProject",
            "colors": {"primary": "#1a1a2e"},
            "fonts": {"primary": "Helvetica Neue"},
        }
        (brand / "tokens.json").write_text(json.dumps(tokens))
        # Redirect TEMPLATES so the module writes to our tmpdir
        mod = self._load_mod()
        self._orig_templates = mod.TEMPLATES
        templates_dir = self.tmp / "brand" / "templates"
        templates_dir.mkdir(parents=True, exist_ok=True)
        mod.TEMPLATES = templates_dir
        # Also patch ROOT so relative paths in print() don't error
        self._orig_root = mod.ROOT
        mod.ROOT = self.tmp

    def tearDown(self) -> None:
        mod = self._load_mod()
        mod.TEMPLATES = self._orig_templates
        mod.ROOT = self._orig_root
        shutil.rmtree(self.tmp, ignore_errors=True)

    def _make_docx(self, extra_tokens: dict | None = None) -> "Document":  # type: ignore[name-defined]
        from docx import Document
        mod = self._load_mod()
        tokens_path = self.tmp / "brand" / "tokens.json"
        tokens = json.loads(tokens_path.read_text())
        if extra_tokens:
            tokens.update(extra_tokens)
            tokens_path.write_text(json.dumps(tokens))
        mod._generate_docx(tokens)
        docx_path = mod.TEMPLATES / "reference.docx"
        self.assertTrue(docx_path.exists(), "reference.docx not created")
        return Document(str(docx_path))

    # --- margin tests ---

    def test_page_margins_are_2_5_cm(self) -> None:
        """#266: all four page margins must be 2.5 cm (900 000 EMU)."""
        from docx.shared import Cm
        doc = self._make_docx()
        for section in doc.sections:
            for attr in ("left_margin", "right_margin", "top_margin", "bottom_margin"):
                val = getattr(section, attr)
                self.assertIsNotNone(val, f"{attr} is None")
                self.assertAlmostEqual(
                    val, Cm(2.5), delta=1000,
                    msg=f"Expected {attr}=2.5 cm (900 000 EMU), got {val}"
                )

    # --- Normal body style tests ---

    def test_normal_line_spacing_is_1_25(self) -> None:
        """#266: Normal paragraph format must have line_spacing=1.25."""
        doc = self._make_docx()
        normal = doc.styles["Normal"]
        ls = normal.paragraph_format.line_spacing
        self.assertIsNotNone(ls, "Normal line_spacing is None")
        self.assertAlmostEqual(float(ls), 1.25, places=2,
                               msg=f"Expected line_spacing=1.25, got {ls}")

    def test_normal_space_after_8pt(self) -> None:
        """#266: Normal paragraph must have 8pt space after."""
        from docx.shared import Pt
        doc = self._make_docx()
        normal = doc.styles["Normal"]
        sa = normal.paragraph_format.space_after
        self.assertIsNotNone(sa, "Normal space_after is None")
        self.assertAlmostEqual(sa, Pt(8), delta=1000,
                               msg=f"Expected space_after=8pt ({int(Pt(8))} EMU), got {sa}")

    def test_normal_body_color_is_slate(self) -> None:
        """#266: Normal font color must be slate #2A3340."""
        doc = self._make_docx()
        normal = doc.styles["Normal"]
        color = normal.font.color.rgb
        self.assertIsNotNone(color, "Normal font color is None")
        self.assertEqual(str(color).upper(), "2A3340",
                         f"Expected body color 2A3340, got {color}")

    # --- Heading spacing tests ---

    def test_heading1_size_and_spacing(self) -> None:
        """#266: H1 must be 22pt, space_before=18pt, space_after=8pt."""
        from docx.shared import Pt
        doc = self._make_docx()
        h1 = doc.styles["Heading 1"]
        self.assertAlmostEqual(h1.font.size, Pt(22), delta=1000,
                               msg=f"H1 size expected 22pt, got {h1.font.size}")
        self.assertAlmostEqual(h1.paragraph_format.space_before, Pt(18), delta=1000,
                               msg=f"H1 space_before expected 18pt")
        self.assertAlmostEqual(h1.paragraph_format.space_after, Pt(8), delta=1000,
                               msg=f"H1 space_after expected 8pt")

    def test_heading2_size_and_spacing(self) -> None:
        """#266: H2 must be 16pt, space_before=14pt, space_after=6pt."""
        from docx.shared import Pt
        doc = self._make_docx()
        h2 = doc.styles["Heading 2"]
        self.assertAlmostEqual(h2.font.size, Pt(16), delta=1000)
        self.assertAlmostEqual(h2.paragraph_format.space_before, Pt(14), delta=1000)
        self.assertAlmostEqual(h2.paragraph_format.space_after, Pt(6), delta=1000)

    def test_heading3_size_and_spacing(self) -> None:
        """#266: H3 must be 13pt, space_before=10pt, space_after=4pt."""
        from docx.shared import Pt
        doc = self._make_docx()
        h3 = doc.styles["Heading 3"]
        self.assertAlmostEqual(h3.font.size, Pt(13), delta=1000)
        self.assertAlmostEqual(h3.paragraph_format.space_before, Pt(10), delta=1000)
        self.assertAlmostEqual(h3.paragraph_format.space_after, Pt(4), delta=1000)

    def test_heading4_exists_and_is_italic(self) -> None:
        """#266: H4 style must exist, be 11pt, and italic."""
        from docx.shared import Pt
        doc = self._make_docx()
        try:
            h4 = doc.styles["Heading 4"]
        except KeyError:
            self.fail("Heading 4 style not found in generated reference.docx")
        self.assertAlmostEqual(h4.font.size, Pt(11), delta=1000,
                               msg=f"H4 size expected 11pt, got {h4.font.size}")
        self.assertTrue(h4.font.italic, "H4 must be italic")

    def test_title_style_is_32pt(self) -> None:
        """#266: Title style must be set to 32pt."""
        from docx.shared import Pt
        doc = self._make_docx()
        try:
            title = doc.styles["Title"]
        except KeyError:
            self.skipTest("Title style not in pandoc default reference.docx")
        self.assertAlmostEqual(title.font.size, Pt(32), delta=1000,
                               msg=f"Title size expected 32pt, got {title.font.size}")

    def test_footer_contains_project_name_and_confidentiel(self) -> None:
        """#266: document footer must include project name + Confidentiel."""
        doc = self._make_docx()
        footer_text = ""
        for section in doc.sections:
            footer = section.footer
            for para in footer.paragraphs:
                footer_text += para.text
        self.assertIn("TestProject", footer_text,
                      f"Footer must contain project name 'TestProject', got: {footer_text!r}")
        self.assertIn("Confidentiel", footer_text,
                      f"Footer must contain 'Confidentiel', got: {footer_text!r}")

    # --- tokens.json override tests ---

    def test_docx_tokens_override_margins(self) -> None:
        """#266: tokens.json docx.margins_cm must override the default 2.5cm."""
        from docx.shared import Cm
        tokens_path = self.tmp / "brand" / "tokens.json"
        tokens = json.loads(tokens_path.read_text())
        tokens["docx"] = {"margins_cm": 3.0}
        tokens_path.write_text(json.dumps(tokens))
        mod = self._load_mod()
        doc = self._make_docx()
        for section in doc.sections:
            for attr in ("left_margin", "right_margin", "top_margin", "bottom_margin"):
                val = getattr(section, attr)
                self.assertAlmostEqual(
                    val, Cm(3.0), delta=1000,
                    msg=f"Expected overridden {attr}=3.0 cm, got {val}"
                )

    def test_docx_tokens_override_body_line_spacing(self) -> None:
        """#266: tokens.json docx.body.line_spacing must override the default."""
        tokens_path = self.tmp / "brand" / "tokens.json"
        tokens = json.loads(tokens_path.read_text())
        tokens["docx"] = {"body": {"line_spacing": 1.5}}
        tokens_path.write_text(json.dumps(tokens))
        doc = self._make_docx()
        normal = doc.styles["Normal"]
        ls = normal.paragraph_format.line_spacing
        self.assertAlmostEqual(float(ls), 1.5, places=2,
                               msg=f"Expected overridden line_spacing=1.5, got {ls}")


if __name__ == "__main__":
    unittest.main(verbosity=2)
