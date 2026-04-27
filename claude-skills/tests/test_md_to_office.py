#!/usr/bin/env python3
"""
Unit tests for the md-to-office skill.

Covers four layers, from cheap to expensive:

  1. Pure shell logic of resolve-template.sh — five-priority chain from
     PRD-008 §5.3. Fast; runs without external deps.
  2. Orchestrator semantics of md-to-office.sh — target gating, output
     path convention, idempotency, --force bypass. Exercises bash +
     the skill's own scripts; also runs without external deps because
     the docx renderer is stubbed out via PATH shim.
  3. Brand scanner (scan-brand.py) — pure Python stdlib; tests each
     signal source (README, CSS, tailwind, package.json, etc.) and
     merge / fallback behaviour.
  4. End-to-end tests — pandoc / python-docx / python-pptx / openpyxl
     invoked for real. Skipped when deps are missing so CI doesn't
     break for devs who haven't run install-local.sh yet.

Run locally:

    python3 claude-skills/tests/test_md_to_office.py

Stdlib only for layers 1-3. Layer 4 auto-skips when deps are absent.
"""

from __future__ import annotations

import json
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

RESOLVE      = SCRIPTS / "resolve-template.sh"
ORCH         = SCRIPTS / "md-to-office.sh"
RENDER_DOCX  = SCRIPTS / "render-docx.sh"
SCAN_BRAND   = SCRIPTS / "scan-brand.py"
GEN_TEMPLATES = SCRIPTS / "generate-templates.py"
INIT_BRAND   = SCRIPTS / "init-brand.sh"

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
        """No brand/templates/ — render-docx.sh still succeeds silently.

        The 'unbranded' onboarding message is now the orchestrator's job
        (md-to-office.sh). render-docx.sh is a pure renderer: it just
        omits --reference-doc when no template is given, with no noise.
        """
        out = self.tmp / "report.docx"
        result = run(
            ["bash", str(RENDER_DOCX), str(self.src), str(out)],
            cwd=self.tmp,
        )
        self.assertTrue(out.exists())
        self.assertTrue(out.stat().st_size > 0)
        self.assertTrue(out.read_bytes().startswith(ZIP_MAGIC))
        self.assertEqual(result.returncode, 0)

    def test_renders_end_to_end_via_orchestrator(self) -> None:
        out = self.tmp / "report.docx"
        run(["bash", str(ORCH), str(self.src)], cwd=self.tmp)
        self.assertTrue(out.exists())
        self.assertTrue(out.read_bytes().startswith(ZIP_MAGIC))


if __name__ == "__main__":
    unittest.main(verbosity=2)
