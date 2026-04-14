#!/usr/bin/env python3
"""
Integration test for the po-report skill against beyond-scale-group/edomata.

Runs every po-report script against the real GitHub repo (via `GH_REPO=`
— no checkout needed) and asserts:

  - JSON-emitting scripts produce well-formed JSON with the expected
    top-level keys
  - generate-report.sh produces markdown with the expected section headers
  - repo-level values (repo slug, invariants between fields) are correct

Assertions are schema-level so the test tolerates edomata's real issue /
PR / milestone counts drifting over time. No hardcoded counts.

The scripts are invoked from a tmpdir that contains only a minimal
`git init` + remote pointing at the target repo (no source code
cloned). That's enough for `gh`'s CWD autodetection to pick the right
repo — and unlike a real `gh repo clone`, it avoids the fork-upstream
confusion where a fork clone resolves `gh repo view` to the upstream.
It's also dramatically faster than a full clone in CI.

Requires: gh (authenticated), jq. In CI, the default GITHUB_TOKEN is
forwarded to gh via the GH_TOKEN env var in the workflow. The test
skips itself cleanly if any of those are missing, so running the file
on a dev machine without `gh auth login` is a no-op rather than a
failure.

Run locally:

    python3 claude-skills/tests/test_po_report_integration.py
"""

from __future__ import annotations

import json
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
SCRIPTS = REPO_ROOT / "claude-skills" / "skills" / "po-report" / "scripts"
TARGET = "beyond-scale-group/edomata"

SCRIPT_TIMEOUT_S = 120


def _which(cmd: str) -> bool:
    return shutil.which(cmd) is not None


def _gh_authenticated() -> bool:
    try:
        r = subprocess.run(
            ["gh", "auth", "status"],
            capture_output=True,
            text=True,
            timeout=10,
        )
        return r.returncode == 0
    except (FileNotFoundError, subprocess.TimeoutExpired):
        return False


class TestPoReportIntegration(unittest.TestCase):
    """End-to-end smoke test of every po-report script against a real repo."""

    tmpdir: "tempfile.TemporaryDirectory | None" = None
    workdir: Path

    @classmethod
    def setUpClass(cls) -> None:
        if not _which("gh"):
            raise unittest.SkipTest("gh CLI not available")
        if not _which("jq"):
            raise unittest.SkipTest("jq not available")
        if not _gh_authenticated():
            raise unittest.SkipTest(
                "gh is not authenticated (set GH_TOKEN or run `gh auth login`)"
            )

        # Minimal git init + remote pointing at TARGET so `gh`'s CWD
        # autodetection resolves to the right repo without a real clone.
        cls.tmpdir = tempfile.TemporaryDirectory(prefix="po-integration-")
        cls.workdir = Path(cls.tmpdir.name)
        remote_url = f"https://github.com/{TARGET}.git"
        for cmd in (
            ["git", "init", "--quiet"],
            ["git", "remote", "add", "origin", remote_url],
        ):
            subprocess.run(
                cmd, cwd=cls.workdir, check=True, capture_output=True, text=True
            )

    @classmethod
    def tearDownClass(cls) -> None:
        if cls.tmpdir is not None:
            cls.tmpdir.cleanup()

    # -- helpers --------------------------------------------------------

    def _run(self, script: str, *args: str) -> str:
        path = SCRIPTS / script
        self.assertTrue(path.is_file(), f"script not found: {path}")
        result = subprocess.run(
            ["bash", str(path), *args],
            cwd=self.workdir,
            capture_output=True,
            text=True,
            timeout=SCRIPT_TIMEOUT_S,
        )
        self.assertEqual(
            result.returncode,
            0,
            f"{script} exited {result.returncode}\nSTDERR:\n{result.stderr}",
        )
        return result.stdout

    # -- tests ----------------------------------------------------------

    def test_status_script_emits_valid_json(self) -> None:
        out = self._run("status.sh")
        data = json.loads(out)
        self.assertEqual(data.get("repo"), TARGET)
        for key in (
            "generatedAt",
            "issues",
            "pullRequests",
            "topLabels",
            "byAssignee",
            "oldestOpenPr",
        ):
            self.assertIn(key, data)
        self.assertIn("open", data["issues"])
        self.assertIn("closed", data["issues"])
        self.assertIsInstance(data["issues"]["open"], int)
        self.assertIsInstance(data["issues"]["closed"], int)
        self.assertIn("open", data["pullRequests"])
        self.assertIn("draft", data["pullRequests"])
        self.assertIsInstance(data["topLabels"], list)
        self.assertIsInstance(data["byAssignee"], list)
        # Draft count can never exceed open count.
        self.assertLessEqual(
            data["pullRequests"]["draft"], data["pullRequests"]["open"]
        )

    def test_milestone_progress_script_emits_json_array(self) -> None:
        out = self._run("milestone-progress.sh")
        data = json.loads(out)
        self.assertIsInstance(data, list)
        for m in data:
            for key in (
                "number",
                "title",
                "state",
                "open_issues",
                "closed_issues",
                "total",
                "percent_complete",
                "url",
            ):
                self.assertIn(key, m, f"missing key {key!r} in milestone {m!r}")
            # Sanity: total should equal open + closed.
            self.assertEqual(m["total"], m["open_issues"] + m["closed_issues"])
            # percent_complete is bounded.
            self.assertGreaterEqual(m["percent_complete"], 0)
            self.assertLessEqual(m["percent_complete"], 100)

    def test_stale_issues_script_emits_json_array(self) -> None:
        out = self._run("stale-issues.sh", "14")
        data = json.loads(out)
        self.assertIsInstance(data, list)
        for issue in data:
            for key in (
                "number",
                "title",
                "assignees",
                "labels",
                "updatedAt",
                "daysStale",
                "url",
            ):
                self.assertIn(key, issue, f"missing key {key!r} in {issue!r}")
            # By construction, an issue only appears here if it's stale >= DAYS.
            self.assertGreaterEqual(issue["daysStale"], 14)
            self.assertIsInstance(issue["assignees"], list)
            self.assertIsInstance(issue["labels"], list)

    def test_generate_report_emits_expected_markdown(self) -> None:
        out = self._run("generate-report.sh")
        self.assertIn(f"# PO Report — {TARGET}", out)
        for header in (
            "## At a glance",
            "## Top labels (open issues)",
            "## Open issues by assignee",
            "## Milestone progress",
            "## Stale open issues",
            "## Oldest open PR",
        ):
            self.assertIn(header, out, f"missing section header: {header!r}")


if __name__ == "__main__":
    unittest.main(verbosity=2)
