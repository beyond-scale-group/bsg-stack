#!/usr/bin/env python3
"""
Unit tests for the md-to-office skill.

Covers three layers, from cheap to expensive:

  1. Pure shell logic of resolve-template.sh — five-priority chain from
     PRD-008 §5.3. Fast; runs without external deps.
  2. Orchestrator semantics of md-to-office.sh — target gating, output
     path convention, idempotency, --force bypass. Exercises bash +
     the skill's own scripts; also runs without external deps because
     the docx renderer is stubbed out via PATH shim.
  3. End-to-end docx smoke — pandoc actually invoked on a tiny
     fixture markdown. Skipped when pandoc is missing so CI doesn't
     break for devs who haven't run install-local.sh yet.

Run locally:

    python3 claude-skills/tests/test_md_to_office.py

Stdlib only. No third-party dependencies, no network.
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

REPO_ROOT = Path(__file__).resolve().parents[2]
SKILL_DIR = REPO_ROOT / "claude-skills" / "skills" / "md-to-office"
SCRIPTS = SKILL_DIR / "scripts"

RESOLVE = SCRIPTS / "resolve-template.sh"
ORCH = SCRIPTS / "md-to-office.sh"
RENDER_DOCX = SCRIPTS / "render-docx.sh"

# Magic bytes of a ZIP archive — DOCX/PPTX/XLSX all use the ZIP container.
ZIP_MAGIC = b"PK\x03\x04"


def run(
    cmd: list[str],
    *,
    cwd: Path | None = None,
    env: dict[str, str] | None = None,
    check: bool = True,
) -> subprocess.CompletedProcess[str]:
    """Run a command, capturing stdout/stderr as text."""
    final_env = os.environ.copy()
    if env:
        final_env.update(env)
    return subprocess.run(
        cmd,
        cwd=str(cwd) if cwd else None,
        env=final_env,
        text=True,
        capture_output=True,
        check=check,
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

    def test_pptx_target_is_not_implemented_in_v01(self) -> None:
        result = self._run_orch(str(self.src), "--target", "pptx", check=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("not implemented", result.stderr)

    def test_xlsx_target_is_not_implemented_in_v01(self) -> None:
        result = self._run_orch(str(self.src), "--target", "xlsx", check=False)
        self.assertNotEqual(result.returncode, 0)

    def test_unknown_target_is_error(self) -> None:
        result = self._run_orch(str(self.src), "--target", "html", check=False)
        self.assertNotEqual(result.returncode, 0)

    # ---- missing input -----------------------------------------------------

    def test_missing_input_is_error(self) -> None:
        result = self._run_orch(str(self.tmp / "nope.md"), check=False)
        self.assertNotEqual(result.returncode, 0)


class TestRenderDocxSmoke(unittest.TestCase):
    """End-to-end DOCX render via the real pandoc.

    Skipped when pandoc isn't installed — devs run install-local.sh to
    opt in. In CI, pandoc is a prerequisite of this skill's test job.
    """

    def setUp(self) -> None:
        if not shutil.which("pandoc"):
            self.skipTest("pandoc not installed; run scripts/install-local.sh")
        self.tmp = Path(tempfile.mkdtemp(prefix="bsg-smoke-"))
        self.src = self.tmp / "report.md"
        self.src.write_text("# Title\n\nParagraph with **bold** text.\n")

    def tearDown(self) -> None:
        if hasattr(self, "tmp"):
            shutil.rmtree(self.tmp, ignore_errors=True)

    def test_renders_unbranded_docx_without_template(self) -> None:
        """No brand/templates/ — must still succeed with a warning."""
        out = self.tmp / "report.docx"
        result = run(
            ["bash", str(RENDER_DOCX), str(self.src), str(out)],
            cwd=self.tmp,
        )
        self.assertTrue(out.exists())
        self.assertTrue(out.stat().st_size > 0)
        self.assertTrue(out.read_bytes().startswith(ZIP_MAGIC))
        # The unbranded warning is the contract guard for level 5.
        self.assertIn("unbranded", result.stderr.lower())

    def test_renders_end_to_end_via_orchestrator(self) -> None:
        out = self.tmp / "report.docx"
        run(["bash", str(ORCH), str(self.src)], cwd=self.tmp)
        self.assertTrue(out.exists())
        self.assertTrue(out.read_bytes().startswith(ZIP_MAGIC))


if __name__ == "__main__":
    unittest.main(verbosity=2)
