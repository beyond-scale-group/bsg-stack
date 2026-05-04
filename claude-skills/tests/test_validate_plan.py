#!/usr/bin/env python3
"""
Tests for issue #392 — validate-plan.sh: plan validator script.

E6-plan-schema-hygiene requires a `validate-plan.sh` script that:
  1. Exists and is executable
  2. Exits 0 when PLAN.md is valid (has bound items)
  3. Exits non-zero and prints a diagnostic when PLAN.md is missing
  4. Exits non-zero and prints a diagnostic when PLAN.md has no bound items

Stdlib only — no third-party dependencies, no network.

Run locally:
    python3 claude-skills/tests/test_validate_plan.py
"""

from __future__ import annotations

import os
import subprocess
import tempfile
import textwrap
import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
VALIDATE_SCRIPT = REPO_ROOT / "claude-skills" / "scripts" / "validate-plan.sh"
PARSE_PLAN = REPO_ROOT / "claude-skills" / "skills" / "po" / "scripts" / "parse-plan.sh"

VALID_PLAN = textwrap.dedent("""\
    # Big plan — test-repo

    ## Objectives
    - Ship feature X   [milestone:M1]
    - Fix critical bug  [milestone:M2]

    ## Epics
    - **M1** — feature X   [milestone:M1] [label:enhancement]
    - **M2** — critical fix [milestone:M2] [label:bug]
""")

EMPTY_PLAN = textwrap.dedent("""\
    # Big plan — test-repo

    ## Objectives
    - Ship feature X (no binding tags here)
""")


class TestValidatePlanScriptExists(unittest.TestCase):

    def test_validate_plan_script_exists(self):
        """validate-plan.sh must exist at claude-skills/scripts/validate-plan.sh."""
        self.assertTrue(
            VALIDATE_SCRIPT.exists(),
            f"validate-plan.sh not found at {VALIDATE_SCRIPT} — E6-plan-schema-hygiene requires this script",
        )

    def test_validate_plan_script_is_executable(self):
        """validate-plan.sh must be executable."""
        if not VALIDATE_SCRIPT.exists():
            self.skipTest("validate-plan.sh does not exist yet")
        self.assertTrue(
            os.access(VALIDATE_SCRIPT, os.X_OK),
            "validate-plan.sh exists but is not executable",
        )


class TestValidatePlanBehavior(unittest.TestCase):

    def _run(self, *args: str, plan_path: str | None = None) -> subprocess.CompletedProcess:
        cmd = ["bash", str(VALIDATE_SCRIPT)]
        if plan_path is not None:
            cmd += ["--plan", plan_path]
        cmd += list(args)
        return subprocess.run(cmd, capture_output=True, text=True)

    def setUp(self):
        if not VALIDATE_SCRIPT.exists():
            self.skipTest("validate-plan.sh does not exist yet")

    def test_valid_plan_exits_zero(self):
        """validate-plan.sh exits 0 when PLAN.md contains bound items."""
        with tempfile.NamedTemporaryFile(mode="w", suffix=".md", delete=False) as f:
            f.write(VALID_PLAN)
            plan_path = f.name
        try:
            result = self._run(plan_path=plan_path)
            self.assertEqual(
                result.returncode, 0,
                f"Expected exit 0 for valid plan.\nstdout: {result.stdout}\nstderr: {result.stderr}",
            )
        finally:
            os.unlink(plan_path)

    def test_missing_plan_exits_nonzero(self):
        """validate-plan.sh exits non-zero when PLAN.md does not exist."""
        result = self._run(plan_path="/tmp/does-not-exist-plan-392.md")
        self.assertNotEqual(
            result.returncode, 0,
            "Expected non-zero exit when PLAN.md is missing",
        )

    def test_missing_plan_prints_diagnostic(self):
        """validate-plan.sh prints a useful error message when PLAN.md is missing."""
        result = self._run(plan_path="/tmp/does-not-exist-plan-392.md")
        combined = result.stdout + result.stderr
        self.assertTrue(
            len(combined.strip()) > 0,
            "Expected at least one diagnostic line for missing PLAN.md, got silence",
        )

    def test_empty_plan_exits_nonzero(self):
        """validate-plan.sh exits non-zero when PLAN.md has no binding tags."""
        with tempfile.NamedTemporaryFile(mode="w", suffix=".md", delete=False) as f:
            f.write(EMPTY_PLAN)
            plan_path = f.name
        try:
            result = self._run(plan_path=plan_path)
            self.assertNotEqual(
                result.returncode, 0,
                f"Expected non-zero exit for unbound plan.\nstdout: {result.stdout}\nstderr: {result.stderr}",
            )
        finally:
            os.unlink(plan_path)

    def test_empty_plan_prints_diagnostic(self):
        """validate-plan.sh prints a diagnostic when PLAN.md has no binding tags."""
        with tempfile.NamedTemporaryFile(mode="w", suffix=".md", delete=False) as f:
            f.write(EMPTY_PLAN)
            plan_path = f.name
        try:
            result = self._run(plan_path=plan_path)
            combined = result.stdout + result.stderr
            self.assertTrue(
                len(combined.strip()) > 0,
                "Expected a diagnostic for unbound plan, got silence",
            )
        finally:
            os.unlink(plan_path)


if __name__ == "__main__":
    unittest.main()
