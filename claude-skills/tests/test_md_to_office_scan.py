#!/usr/bin/env python3
"""Tests for scan-brand.py — README/CSS/Tailwind/package.json signal extraction.

Split out of test_md_to_office.py for #330 (single file >500 LOC).
Run individually:

    python3 claude-skills/tests/test_md_to_office_scan.py

Stdlib only; auto-skips when external deps are missing.
"""

from __future__ import annotations

import json
import os
import shutil
import tempfile
import textwrap
import unittest
from pathlib import Path

from _md_to_office_helpers import (
    ORCH,
    SCAN_BRAND,
    run,
)


class TestScanBrand(unittest.TestCase):
    """Covers scan-brand.py signal sources. Pure Python stdlib, no external deps."""

    def setUp(self) -> None:
        self.tmp = Path(tempfile.mkdtemp(prefix="bsg-scan-"))

    def tearDown(self) -> None:
        shutil.rmtree(self.tmp, ignore_errors=True)

    def _scan(self, env: dict[str, str] | None = None) -> dict:
        result = run(
            ["python3", str(SCAN_BRAND)],
            cwd=self.tmp,
            env={**os.environ, **(env or {})},
        )
        return json.loads(result.stdout)

    # ---- name detection ----------------------------------------------------

    def test_name_from_readme_h1(self) -> None:
        (self.tmp / "README.md").write_text("# Acme Platform\n\nDesc.\n")
        self.assertEqual(self._scan()["name"], "Acme Platform")

    def test_name_from_package_json(self) -> None:
        (self.tmp / "package.json").write_text('{"name": "acme-frontend", "version": "1.0.0"}')
        self.assertEqual(self._scan()["name"], "acme-frontend")

    def test_name_from_pyproject_toml(self) -> None:
        (self.tmp / "pyproject.toml").write_text('[project]\nname = "acme-backend"\n')
        self.assertEqual(self._scan()["name"], "acme-backend")

    def test_name_from_stack_yaml(self) -> None:
        (self.tmp / "stack.yaml").write_text("name: acme-stack\nversion: 1\n")
        self.assertEqual(self._scan()["name"], "acme-stack")

    def test_name_from_narrative_wins_over_readme(self) -> None:
        (self.tmp / "README.md").write_text("# Readme Name\n")
        brand = self.tmp / "brand"
        brand.mkdir()
        (brand / "NARRATIVE.md").write_text("# Narrative Name\n\nBrand voice.\n")
        self.assertEqual(self._scan()["name"], "Narrative Name")

    def test_name_defaults_to_project(self) -> None:
        # Totally empty repo with no git — should not crash.
        tokens = self._scan()
        self.assertIn("name", tokens)
        self.assertTrue(len(tokens["name"]) > 0)

    # ---- primary colour detection ------------------------------------------

    def test_primary_from_css_custom_property(self) -> None:
        css = self.tmp / "styles.css"
        css.write_text(":root { --primary-color: #e63946; }\n")
        self.assertEqual(self._scan()["colors"]["primary"], "#e63946")

    def test_primary_from_css_color_primary(self) -> None:
        css = self.tmp / "theme.css"
        css.write_text(":root { --color-primary: #2b9348; }\n")
        self.assertEqual(self._scan()["colors"]["primary"], "#2b9348")

    def test_primary_from_tailwind_config(self) -> None:
        tw = self.tmp / "tailwind.config.js"
        tw.write_text("module.exports = { theme: { colors: { primary: '#6d28d9' } } }\n")
        self.assertEqual(self._scan()["colors"]["primary"], "#6d28d9")

    def test_primary_from_tailwind_v4_theme_block(self) -> None:
        """#241: Tailwind v4 @theme blocks with --color-* tokens must be parsed."""
        apps_css = self.tmp / "apps" / "web-app" / "src" / "app"
        apps_css.mkdir(parents=True)
        (apps_css / "globals.css").write_text(
            "@theme {\n"
            "  --color-ef-blue-50: #eff6ff;\n"
            "  --color-ef-blue-500: #1A56DB;\n"
            "  --color-ef-blue-900: #1e3a5f;\n"
            "}\n"
        )
        result = self._scan()["colors"]["primary"]
        self.assertEqual(
            result.lower(),
            "#1a56db",
            f"Expected #1a56db from Tailwind v4 @theme block, got {result}",
        )

    def test_primary_app_css_preferred_over_public_html(self) -> None:
        """#241: main app CSS should win over stray HTML files under public/."""
        # Stray demo HTML in public/ with a different color
        pub = self.tmp / "public" / "images" / "brand"
        pub.mkdir(parents=True)
        (pub / "index.html").write_text(
            "<link href='https://fonts.googleapis.com/css2?family=Outfit' rel='stylesheet'>\n"
            "<style>:root { --primary-color: #badcol; }</style>\n"
        )
        # Real app globals.css with the actual brand color
        apps_css = self.tmp / "apps" / "web-app" / "src" / "app"
        apps_css.mkdir(parents=True)
        (apps_css / "globals.css").write_text(
            "@theme {\n"
            "  --color-ef-blue-500: #1A56DB;\n"
            "}\n"
        )
        result = self._scan()["colors"]["primary"]
        self.assertEqual(
            result.lower(),
            "#1a56db",
            f"Expected #1a56db from app globals.css, got {result} (stray public HTML color leaked)",
        )


    def test_primary_from_tokens_json(self) -> None:
        (self.tmp / "tokens.json").write_text(
            json.dumps({"colors": {"primary": "#ff6b35"}})
        )
        self.assertEqual(self._scan()["colors"]["primary"], "#ff6b35")

    def test_primary_shorthand_hex_expanded(self) -> None:
        css = self.tmp / "main.css"
        css.write_text(":root { --primary: #f0f; }\n")
        result = self._scan()["colors"]["primary"]
        self.assertEqual(result, "#ff00ff")

    def test_primary_defaults_to_bsg_navy(self) -> None:
        tokens = self._scan()
        self.assertEqual(tokens["colors"]["primary"], "#1a1a2e")

    # ---- font detection ----------------------------------------------------

    def test_font_from_css_variable(self) -> None:
        css = self.tmp / "vars.css"
        css.write_text(":root { --font-family-primary: 'Inter', sans-serif; }\n")
        font = self._scan()["fonts"]["primary"]
        self.assertIn("Inter", font)

    def test_font_defaults_to_helvetica(self) -> None:
        self.assertEqual(self._scan()["fonts"]["primary"], "Helvetica Neue")

    # ---- merge with existing partial tokens --------------------------------

    def test_existing_tokens_take_priority_over_scan(self) -> None:
        brand = self.tmp / "brand"
        brand.mkdir()
        existing = {"name": "Locked Name", "colors": {"primary": "#locked"}, "fonts": {"primary": "Locked Font"}}
        (brand / "tokens.json").write_text(json.dumps(existing))
        # Also put a README that would normally win.
        (self.tmp / "README.md").write_text("# Different Name\n")
        tokens = self._scan()
        self.assertEqual(tokens["name"], "Locked Name")
        self.assertEqual(tokens["colors"]["primary"], "#locked")

    def test_partial_tokens_filled_by_scan(self) -> None:
        brand = self.tmp / "brand"
        brand.mkdir()
        (brand / "tokens.json").write_text(json.dumps({"name": "My Project"}))
        (self.tmp / "styles.css").write_text(":root { --primary: #aabbcc; }\n")
        tokens = self._scan()
        self.assertEqual(tokens["name"], "My Project")   # from existing
        self.assertEqual(tokens["colors"]["primary"], "#aabbcc")  # from CSS

    # ---- @font-face detection ------------------------------------------------

    def test_font_from_font_face(self) -> None:
        css = self.tmp / "fonts.css"
        css.write_text(
            "@font-face {\n"
            "  font-family: 'Cabinet Grotesk';\n"
            "  src: url('cabinet.woff2');\n"
            "}\n"
        )
        self.assertEqual(self._scan()["fonts"]["primary"], "Cabinet Grotesk")

    def test_font_from_google_fonts_import(self) -> None:
        css = self.tmp / "global.css"
        css.write_text(
            "@import url('https://fonts.googleapis.com/css2?family=Poppins:wght@400;700');\n"
        )
        self.assertEqual(self._scan()["fonts"]["primary"], "Poppins")

    def test_css_variable_font_wins_over_font_face(self) -> None:
        css = self.tmp / "all.css"
        css.write_text(
            ":root { --font-family-primary: 'Manrope', sans-serif; }\n"
            "@font-face { font-family: 'Cabinet Grotesk'; src: url('c.woff2'); }\n"
        )
        self.assertIn("Manrope", self._scan()["fonts"]["primary"])

    # ---- logo detection ------------------------------------------------------

    def test_logos_found_in_public_dir(self) -> None:
        pub = self.tmp / "public"
        pub.mkdir()
        (pub / "logo.svg").write_text("<svg/>")
        (pub / "logo-dark.png").write_bytes(b"\x89PNG")
        tokens = self._scan()
        self.assertIn("logos", tokens)
        self.assertEqual(len(tokens["logos"]), 2)
        self.assertTrue(any("logo.svg" in l for l in tokens["logos"]))

    def test_logos_empty_when_none_found(self) -> None:
        tokens = self._scan()
        self.assertEqual(tokens["logos"], [])

    # ---- identity doc detection ----------------------------------------------

    def test_identity_docs_found(self) -> None:
        brand = self.tmp / "brand"
        brand.mkdir()
        (brand / "NARRATIVE.md").write_text("# Brand\n\nVoice.\n")
        (self.tmp / "DESIGN.md").write_text("# Design System\n")
        tokens = self._scan()
        self.assertIn("identity_docs", tokens)
        self.assertTrue(len(tokens["identity_docs"]) >= 2)

    def test_identity_docs_empty_when_none(self) -> None:
        tokens = self._scan()
        self.assertEqual(tokens["identity_docs"], [])

    # ---- existing template detection -----------------------------------------

    def test_existing_templates_found(self) -> None:
        (self.tmp / "old-report.docx").write_bytes(b"PK\x03\x04stub")
        tokens = self._scan()
        self.assertIn("existing_templates", tokens)
        self.assertTrue(any("old-report.docx" in t for t in tokens["existing_templates"]))

    # ---- audit generation ----------------------------------------------------

    def test_audit_flag_writes_markdown(self) -> None:
        (self.tmp / "README.md").write_text("# Audit Test\n\nDesc.\n")
        css = self.tmp / "style.css"
        css.write_text(":root { --primary-color: #abcdef; }\n")
        audit_path = self.tmp / "brand" / "templates" / "brand-audit.md"
        result = run(
            ["python3", str(SCAN_BRAND), "--audit", str(audit_path)],
            cwd=self.tmp,
        )
        self.assertTrue(audit_path.exists(), f"audit not written; stderr={result.stderr}")
        content = audit_path.read_text()
        self.assertIn("# Brand Audit", content)
        self.assertIn("Audit Test", content)
        self.assertIn("#abcdef", content)
        self.assertIn("Chosen tokens", content)
        self.assertIn("Discovery details", content)

    def test_audit_shows_defaults_when_empty_repo(self) -> None:
        audit_path = self.tmp / "audit.md"
        run(
            ["python3", str(SCAN_BRAND), "--audit", str(audit_path)],
            cwd=self.tmp,
        )
        content = audit_path.read_text()
        self.assertIn("Defaults applied", content)

    # ---- orchestrator onboarding banner ------------------------------------

    def _make_fake_pandoc(self, bin_dir: Path) -> None:
        """Write a portable fake pandoc that creates a stub ZIP at the -o path."""
        fake = bin_dir / "pandoc"
        fake.write_text(textwrap.dedent("""\
            #!/usr/bin/env bash
            while [[ $# -gt 0 ]]; do
              case "$1" in
                -o) printf 'PK\\x03\\x04stub' > "$2"; shift 2 ;;
                *)  shift ;;
              esac
            done
            """))
        fake.chmod(0o755)

    def test_orchestrator_shows_init_hint_when_no_brand_dir(self) -> None:
        src = self.tmp / "doc.md"
        src.write_text("# Hello\n\nBody.\n")
        bin_dir = self.tmp / "bin"
        bin_dir.mkdir()
        self._make_fake_pandoc(bin_dir)
        result = run(
            ["bash", str(ORCH), str(src)],
            cwd=self.tmp,
            env={**os.environ, "PATH": f"{bin_dir}:{os.environ.get('PATH', '')}"},
        )
        self.assertIn("--init", result.stderr)
        self.assertIn("No brand standard", result.stderr)

    def test_orchestrator_renders_despite_missing_brand(self) -> None:
        """Rendering succeeds even when brand/ is absent — no hard failure."""
        src = self.tmp / "doc.md"
        src.write_text("# Hello\n")
        bin_dir = self.tmp / "bin"
        bin_dir.mkdir()
        self._make_fake_pandoc(bin_dir)
        result = run(
            ["bash", str(ORCH), str(src)],
            cwd=self.tmp,
            env={**os.environ, "PATH": f"{bin_dir}:{os.environ.get('PATH', '')}"},
        )
        self.assertEqual(result.returncode, 0)
        self.assertTrue((self.tmp / "doc.docx").exists())


if __name__ == "__main__":
    unittest.main(verbosity=2)
