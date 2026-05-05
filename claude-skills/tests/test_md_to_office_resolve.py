#!/usr/bin/env python3
"""Tests for resolve-template.sh — 5-priority resolution chain (PRD-008 §5.3).

Split out of test_md_to_office.py for #330 (single file >500 LOC).
Run individually:

    python3 claude-skills/tests/test_md_to_office_resolve.py

Stdlib only; auto-skips when external deps are missing.
"""

from __future__ import annotations

import shutil
import tempfile
import unittest
from pathlib import Path

from _md_to_office_helpers import (
    RESOLVE,
    ZIP_MAGIC,
    run,
)


class TestResolveTemplate(unittest.TestCase):
    """Covers the 5-priority resolution chain from PRD-008 §5.3."""

    def setUp(self) -> None:
        self.tmp = Path(tempfile.mkdtemp(prefix="bsg-mdto-"))
        (self.tmp / "brand" / "templates").mkdir(parents=True)

    def tearDown(self) -> None:
        shutil.rmtree(self.tmp, ignore_errors=True)

    def _touch(self, rel: str) -> Path:
        p = self.tmp / rel
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_bytes(ZIP_MAGIC + b"stub")
        return p

    def _resolve(
        self, target: str, *extra: str, env: dict[str, str] | None = None
    ) -> str:
        result = run(
            ["bash", str(RESOLVE), target, *extra],
            cwd=self.tmp,
            env=env,
        )
        return result.stdout.strip()

    # ---- level 1 -----------------------------------------------------------

    def test_flag_override_wins(self) -> None:
        override = self._touch("custom/foo.docx")
        # Also drop a canonical template to prove the override is preferred.
        self._touch("brand/templates/docx.docx")
        out = self._resolve("docx", "--override", str(override))
        self.assertEqual(out, str(override))

    def test_flag_override_missing_is_error(self) -> None:
        result = run(
            ["bash", str(RESOLVE), "docx", "--override", "does/not/exist.docx"],
            cwd=self.tmp,
            check=False,
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("not found", result.stderr.lower())

    # ---- level 2 -----------------------------------------------------------

    def test_env_var_wins_over_canonical(self) -> None:
        env_dir = self.tmp / "env-templates"
        env_dir.mkdir()
        env_template = env_dir / "docx.docx"
        env_template.write_bytes(ZIP_MAGIC + b"envstub")
        # Canonical exists too — env var should outrank it.
        self._touch("brand/templates/docx.docx")
        out = self._resolve(
            "docx",
            env={"BSG_BRAND_TEMPLATES": str(env_dir)},
        )
        self.assertEqual(out, str(env_template))

    # ---- level 3 -----------------------------------------------------------

    def test_canonical_per_repo_template(self) -> None:
        tmpl = self._touch("brand/templates/docx.docx")
        out = self._resolve("docx")
        self.assertEqual(out, "./brand/templates/docx.docx")
        self.assertTrue(tmpl.exists())  # sanity

    # ---- level 4 -----------------------------------------------------------

    def test_legacy_reference_docx_alias(self) -> None:
        self._touch("brand/templates/reference.docx")
        out = self._resolve("docx")
        self.assertEqual(out, "./brand/templates/reference.docx")

    def test_legacy_alias_does_not_apply_to_pptx(self) -> None:
        # reference.docx exists but target is pptx — the alias must not leak.
        self._touch("brand/templates/reference.docx")
        out = self._resolve("pptx")
        self.assertEqual(out, "")

    # ---- level 5 -----------------------------------------------------------

    def test_no_template_returns_empty_success(self) -> None:
        """No brand/, no env, no override — exit 0 with empty stdout."""
        result = run(["bash", str(RESOLVE), "docx"], cwd=self.tmp)
        self.assertEqual(result.returncode, 0)
        self.assertEqual(result.stdout.strip(), "")

    # ---- argument validation -----------------------------------------------

    def test_unknown_target_is_error(self) -> None:
        result = run(
            ["bash", str(RESOLVE), "html"],
            cwd=self.tmp,
            check=False,
        )
        self.assertNotEqual(result.returncode, 0)

    def test_missing_target_is_error(self) -> None:
        result = run(
            ["bash", str(RESOLVE)],
            cwd=self.tmp,
            check=False,
        )
        self.assertNotEqual(result.returncode, 0)


if __name__ == "__main__":
    unittest.main(verbosity=2)
