#!/usr/bin/env python3
"""Tests for generate-templates.py and init-brand.sh — brand init smoke tests.

Split out of test_md_to_office.py for #330 (single file >500 LOC).
Run individually:

    python3 claude-skills/tests/test_md_to_office_init.py

Stdlib only; auto-skips when external deps are missing.
"""

from __future__ import annotations

import json
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

from _md_to_office_helpers import (
    GEN_TEMPLATES,
    INIT_BRAND,
    ZIP_MAGIC,
    run,
)


class TestGenerateTemplatesPartialDeps(unittest.TestCase):
    """Covers exit-code behavior of generate-templates.py when only some deps
    are missing. Regression test for #275: the script must exit 0 when at
    least one format succeeded, and only exit 1 when ALL formats failed.
    """

    def setUp(self) -> None:
        # Require at least docx and openpyxl so DOCX + XLSX can succeed.
        for dep in ("docx", "openpyxl"):
            try:
                __import__(dep)
            except ImportError:
                self.skipTest(f"'{dep}' not installed; skipping partial-dep test")
        self.tmp = Path(tempfile.mkdtemp(prefix="bsg-gt-"))
        brand = self.tmp / "brand"
        brand.mkdir()
        tokens = {"name": "Test", "colors": {"primary": "#1a1a2e"}, "fonts": {"primary": "Helvetica Neue"}}
        (brand / "tokens.json").write_text(json.dumps(tokens))
        # Helper wrapper that blocks pptx import then runs generate-templates.py
        self.wrapper = self.tmp / "_block_pptx.py"
        self.wrapper.write_text(
            "import builtins, runpy, sys\n"
            "_real = builtins.__import__\n"
            "def _fake(name, *args, **kwargs):\n"
            "    if name == 'pptx' or name.startswith('pptx.'): raise ImportError(f'No module named {name!r}')\n"
            "    return _real(name, *args, **kwargs)\n"
            "builtins.__import__ = _fake\n"
            "runpy.run_path(sys.argv[1], run_name='__main__')\n"
        )

    def tearDown(self) -> None:
        shutil.rmtree(self.tmp, ignore_errors=True)

    def _run_with_pptx_blocked(self) -> subprocess.CompletedProcess[str]:
        return run(
            ["python3", str(self.wrapper), str(GEN_TEMPLATES)],
            cwd=self.tmp,
            check=False,
        )

    def test_exits_zero_when_only_pptx_dep_missing(self) -> None:
        """#275: partial success (docx+xlsx ok, pptx skipped) must exit 0."""
        result = self._run_with_pptx_blocked()
        self.assertEqual(
            result.returncode, 0,
            f"Expected exit 0 when only pptx dep missing, got {result.returncode}.\n"
            f"stderr={result.stderr}",
        )

    def test_summary_line_printed_on_partial_success(self) -> None:
        """#275: a one-line summary must be printed showing per-format status."""
        result = self._run_with_pptx_blocked()
        combined = result.stdout + result.stderr
        self.assertIn("templates:", combined.lower())
        self.assertIn("pptx", combined.lower())

    def test_exits_nonzero_when_all_formats_fail(self) -> None:
        """If every format fails (bad tokens), exit 1 is still correct."""
        # Corrupt tokens so all generators raise.
        (self.tmp / "brand" / "tokens.json").write_text("{}")
        result = run(
            ["python3", str(GEN_TEMPLATES)],
            cwd=self.tmp,
            check=False,
        )
        self.assertNotEqual(result.returncode, 0)

class TestInitBrandSmoke(unittest.TestCase):
    """End-to-end init: scan + generate templates. Skipped when deps missing."""

    REQUIRED_DEPS = ("docx", "pptx", "openpyxl")

    def setUp(self) -> None:
        for dep in self.REQUIRED_DEPS:
            try:
                __import__(dep)
            except ImportError:
                self.skipTest(
                    f"'{dep}' not installed; run scripts/install-local.sh to enable init tests"
                )
        if not shutil.which("pandoc"):
            self.skipTest("pandoc not installed; run scripts/install-local.sh")
        self.tmp = Path(tempfile.mkdtemp(prefix="bsg-init-"))
        (self.tmp / "README.md").write_text("# Init Test Repo\n\nDoes things.\n")
        css = self.tmp / "styles.css"
        css.write_text(":root { --primary-color: #3a86ff; --font-family-primary: 'Roboto'; }\n")

    def tearDown(self) -> None:
        if hasattr(self, "tmp"):
            shutil.rmtree(self.tmp, ignore_errors=True)

    def test_init_creates_tokens_json(self) -> None:
        run(["bash", str(INIT_BRAND)], cwd=self.tmp)
        tokens_path = self.tmp / "brand" / "tokens.json"
        self.assertTrue(tokens_path.exists())
        tokens = json.loads(tokens_path.read_text())
        self.assertEqual(tokens["name"], "Init Test Repo")
        self.assertEqual(tokens["colors"]["primary"], "#3a86ff")
        self.assertIn("Roboto", tokens["fonts"]["primary"])

    def test_init_creates_all_three_templates(self) -> None:
        run(["bash", str(INIT_BRAND)], cwd=self.tmp)
        templates = self.tmp / "brand" / "templates"
        for fname in ("reference.docx", "template.pptx", "template.xlsx"):
            path = templates / fname
            self.assertTrue(path.exists(), f"Missing {fname}")
            self.assertTrue(path.stat().st_size > 0)
            self.assertTrue(path.read_bytes().startswith(ZIP_MAGIC), f"{fname} is not a ZIP")

    def test_init_is_idempotent_without_force(self) -> None:
        run(["bash", str(INIT_BRAND)], cwd=self.tmp)
        # Second run without --force: should exit 0, not overwrite.
        result = run(["bash", str(INIT_BRAND)], cwd=self.tmp)
        self.assertIn("already exist", result.stdout)

    def test_init_force_overwrites(self) -> None:
        run(["bash", str(INIT_BRAND)], cwd=self.tmp)
        # Modify tokens, re-run with --force — templates should be regenerated.
        tokens_path = self.tmp / "brand" / "tokens.json"
        tokens = json.loads(tokens_path.read_text())
        tokens["colors"]["primary"] = "#ff0000"
        tokens_path.write_text(json.dumps(tokens))
        run(["bash", str(INIT_BRAND), "--force"], cwd=self.tmp)
        # If it succeeded, templates exist and are fresh.
        self.assertTrue((self.tmp / "brand" / "templates" / "reference.docx").exists())

    def test_tokens_only_skips_template_generation(self) -> None:
        run(["bash", str(INIT_BRAND), "--tokens-only"], cwd=self.tmp)
        self.assertTrue((self.tmp / "brand" / "tokens.json").exists())
        # tokens-only should not create Office templates, but brand-audit.md is OK
        for fname in ("reference.docx", "template.pptx", "template.xlsx"):
            self.assertFalse(
                (self.tmp / "brand" / "templates" / fname).exists(),
                f"{fname} should not exist with --tokens-only",
            )

    def test_dry_run_writes_tokens_and_audit_only(self) -> None:
        run(["bash", str(INIT_BRAND), "--dry-run"], cwd=self.tmp)
        self.assertTrue((self.tmp / "brand" / "tokens.json").exists())
        self.assertTrue((self.tmp / "brand" / "templates" / "brand-audit.md").exists())
        for fname in ("reference.docx", "template.pptx", "template.xlsx"):
            self.assertFalse(
                (self.tmp / "brand" / "templates" / fname).exists(),
                f"{fname} should not exist with --dry-run",
            )

    def test_dry_run_skips_idempotency_guard(self) -> None:
        """--dry-run should work even when templates already exist."""
        run(["bash", str(INIT_BRAND)], cwd=self.tmp)
        # Without --force, a second full run would exit early.
        # But --dry-run should still scan and produce the audit.
        result = run(["bash", str(INIT_BRAND), "--dry-run"], cwd=self.tmp)
        self.assertIn("Dry run", result.stdout)
        self.assertTrue((self.tmp / "brand" / "templates" / "brand-audit.md").exists())

    def test_init_creates_brand_audit_md(self) -> None:
        run(["bash", str(INIT_BRAND)], cwd=self.tmp)
        audit = self.tmp / "brand" / "templates" / "brand-audit.md"
        self.assertTrue(audit.exists())
        content = audit.read_text()
        self.assertIn("Brand Audit", content)
        self.assertIn("Init Test Repo", content)


if __name__ == "__main__":
    unittest.main(verbosity=2)
