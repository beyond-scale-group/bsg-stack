#!/usr/bin/env python3
"""Tests for md-to-office.sh — target gating, output paths, idempotency, --force.

Split out of test_md_to_office.py for #330 (single file >500 LOC).
Run individually:

    python3 claude-skills/tests/test_md_to_office_orchestrator.py

Stdlib only; auto-skips when external deps are missing.
"""

from __future__ import annotations

import os
import shutil
import subprocess
import tempfile
import textwrap
import time
import unittest
from pathlib import Path

from _md_to_office_helpers import (
    ORCH,
    ZIP_MAGIC,
    run,
)


class TestOrchestrator(unittest.TestCase):
    """Covers md-to-office.sh behaviors that don't need pandoc.

    A fake `pandoc` is placed on PATH and just emits a stub DOCX so we
    can verify the orchestrator calls the renderer with the right args,
    resolves templates correctly, and honors idempotency / --force.
    """

    def setUp(self) -> None:
        self.tmp = Path(tempfile.mkdtemp(prefix="bsg-orch-"))
        self.bin = self.tmp / "bin"
        self.bin.mkdir()
        fake = self.bin / "pandoc"
        fake.write_text(
            textwrap.dedent(
                """\
                #!/usr/bin/env bash
                # Find the -o <output> pair and emit a stub ZIP there.
                out=""
                while [[ $# -gt 0 ]]; do
                  case "$1" in
                    -o) out="$2"; shift 2 ;;
                    *)  shift ;;
                  esac
                done
                printf 'PK\\x03\\x04stub-from-fake-pandoc' > "$out"
                """
            )
        )
        fake.chmod(0o755)
        self.env = {"PATH": f"{self.bin}:{os.environ.get('PATH', '')}"}

        self.src = self.tmp / "report.md"
        self.src.write_text("# Hello\n\nBody.\n")

    def tearDown(self) -> None:
        shutil.rmtree(self.tmp, ignore_errors=True)

    def _run_orch(self, *args: str, check: bool = True) -> subprocess.CompletedProcess[str]:
        return run(
            ["bash", str(ORCH), *args],
            cwd=self.tmp,
            env=self.env,
            check=check,
        )

    # ---- output path convention --------------------------------------------

    def test_default_output_path_swaps_extension(self) -> None:
        result = self._run_orch(str(self.src))
        out = self.tmp / "report.docx"
        self.assertTrue(out.exists(), f"expected {out}; stderr={result.stderr}")
        self.assertTrue(out.read_bytes().startswith(ZIP_MAGIC))
        self.assertIn(str(out), result.stdout)

    def test_explicit_out_flag_is_honored(self) -> None:
        custom = self.tmp / "dist" / "custom.docx"
        self._run_orch(str(self.src), "--out", str(custom))
        self.assertTrue(custom.exists())

    # ---- idempotency -------------------------------------------------------

    def test_idempotent_when_output_is_newer(self) -> None:
        out = self.tmp / "report.docx"
        out.write_bytes(ZIP_MAGIC + b"existing")
        # Make the output newer than the source.
        future = time.time() + 10
        os.utime(out, (future, future))

        result = self._run_orch(str(self.src))
        self.assertIn("cached", result.stdout)
        # Body unchanged — fake pandoc would have overwritten it.
        self.assertEqual(out.read_bytes(), ZIP_MAGIC + b"existing")

    def test_force_flag_bypasses_cache(self) -> None:
        out = self.tmp / "report.docx"
        out.write_bytes(ZIP_MAGIC + b"existing")
        future = time.time() + 10
        os.utime(out, (future, future))

        self._run_orch(str(self.src), "--force")
        # Fake pandoc overwrites with its stub payload.
        self.assertIn(b"stub-from-fake-pandoc", out.read_bytes())

    # ---- target gating -----------------------------------------------------

    def test_pptx_target_accepted(self) -> None:
        """pptx is now a valid target; the orchestrator should not reject it."""
        try:
            __import__("pptx")
        except ImportError:
            self.skipTest("python-pptx not installed")
        result = self._run_orch(str(self.src), "--target", "pptx", check=False)
        self.assertEqual(result.returncode, 0)
        out = self.tmp / "report.pptx"
        self.assertTrue(out.exists(), f"expected {out}; stderr={result.stderr}")

    def test_xlsx_target_is_not_implemented(self) -> None:
        result = self._run_orch(str(self.src), "--target", "xlsx", check=False)
        self.assertNotEqual(result.returncode, 0)

    def test_unknown_target_is_error(self) -> None:
        result = self._run_orch(str(self.src), "--target", "html", check=False)
        self.assertNotEqual(result.returncode, 0)

    # ---- auto-detection from frontmatter -----------------------------------

    def test_autodetect_gamma_presentation_produces_pptx(self) -> None:
        try:
            __import__("pptx")
        except ImportError:
            self.skipTest("python-pptx not installed")
        src = self.tmp / "deck.md"
        src.write_text("---\ngamma:\n  format: presentation\n---\n# Deck\n\nSlide content.\n")
        result = self._run_orch(str(src), check=False)
        self.assertEqual(result.returncode, 0, f"stderr={result.stderr}")
        self.assertTrue((self.tmp / "deck.pptx").exists())

    def test_autodetect_gamma_document_produces_docx(self) -> None:
        src = self.tmp / "report.md"
        src.write_text("---\ngamma:\n  format: document\n---\n# Report\n\nBody.\n")
        result = self._run_orch(str(src))
        self.assertTrue((self.tmp / "report.docx").exists())

    def test_autodetect_target_field_in_frontmatter(self) -> None:
        try:
            __import__("pptx")
        except ImportError:
            self.skipTest("python-pptx not installed")
        src = self.tmp / "slides.md"
        src.write_text("---\ntarget: pptx\n---\n# Slides\n\nContent.\n")
        result = self._run_orch(str(src), check=False)
        self.assertEqual(result.returncode, 0, f"stderr={result.stderr}")
        self.assertTrue((self.tmp / "slides.pptx").exists())

    def test_autodetect_no_frontmatter_defaults_to_docx(self) -> None:
        result = self._run_orch(str(self.src))
        self.assertTrue((self.tmp / "report.docx").exists())

    def test_explicit_target_overrides_frontmatter(self) -> None:
        src = self.tmp / "deck.md"
        src.write_text("---\ngamma:\n  format: presentation\n---\n# Deck\n")
        result = self._run_orch(str(src), "--target", "docx")
        self.assertTrue((self.tmp / "deck.docx").exists())

    # ---- batch mode --------------------------------------------------------

    def test_batch_converts_directory(self) -> None:
        batch_dir = self.tmp / "docs"
        batch_dir.mkdir()
        (batch_dir / "a.md").write_text("# Doc A\n\nBody.\n")
        (batch_dir / "b.md").write_text("# Doc B\n\nBody.\n")
        result = self._run_orch(str(batch_dir))
        self.assertTrue((batch_dir / "a.docx").exists())
        self.assertTrue((batch_dir / "b.docx").exists())

    def test_batch_autodetects_per_file(self) -> None:
        try:
            __import__("pptx")
        except ImportError:
            self.skipTest("python-pptx not installed")
        batch_dir = self.tmp / "mixed"
        batch_dir.mkdir()
        (batch_dir / "deck.md").write_text("---\ngamma:\n  format: presentation\n---\n# Deck\n")
        (batch_dir / "doc.md").write_text("---\ngamma:\n  format: document\n---\n# Doc\n")
        result = self._run_orch(str(batch_dir), check=False)
        self.assertEqual(result.returncode, 0, f"stderr={result.stderr}")
        self.assertTrue((batch_dir / "deck.pptx").exists())
        self.assertTrue((batch_dir / "doc.docx").exists())

    def test_batch_empty_dir_is_error(self) -> None:
        empty = self.tmp / "empty"
        empty.mkdir()
        result = self._run_orch(str(empty), check=False)
        self.assertNotEqual(result.returncode, 0)

    # ---- missing input -----------------------------------------------------

    def test_missing_input_is_error(self) -> None:
        result = self._run_orch(str(self.tmp / "nope.md"), check=False)
        self.assertNotEqual(result.returncode, 0)


if __name__ == "__main__":
    unittest.main(verbosity=2)
