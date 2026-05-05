"""Shared fixtures for the md-to-office test suite.

Extracted from test_md_to_office.py during split for #330 (file >500 LOC).
Each topic test module imports the script paths and `run()` helper from
here so the canonical script locations live in one place.

Stdlib only — pandoc / python-docx / python-pptx / openpyxl are auto-skipped
inside the test modules when missing.
"""

from __future__ import annotations

import os
import subprocess
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
SKILL_DIR = REPO_ROOT / "claude-skills" / "skills" / "md-to-office"
SCRIPTS = SKILL_DIR / "scripts"

RESOLVE = SCRIPTS / "resolve-template.sh"
ORCH = SCRIPTS / "md-to-office.sh"
RENDER_DOCX = SCRIPTS / "render-docx.sh"
RENDER_PPTX = SCRIPTS / "render-pptx.sh"
RENDER_PPTX_PY = SCRIPTS / "render-pptx.py"
SCAN_BRAND = SCRIPTS / "scan-brand.py"
GEN_TEMPLATES = SCRIPTS / "generate-templates.py"
INIT_BRAND = SCRIPTS / "init-brand.sh"

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
