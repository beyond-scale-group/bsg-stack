"""Shared fixture for the po integration test suite.

Extracted from test_po_report_integration.py during split for #691
(single file >500 LOC). Feature-focused test modules inherit
`BasePoIntegration` to get a workdir + snapshot without duplicating
the `gh`/`jq`/auth precondition dance.

Stdlib only. Every subclass is auto-skipped when `gh`/`jq` are missing
or when `gh` isn't authenticated, matching the original behavior.
"""

from __future__ import annotations

import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
SCRIPTS = REPO_ROOT / "claude-skills" / "skills" / "po" / "scripts"
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


class BasePoIntegration(unittest.TestCase):
    """Shared fixture: workdir with a git remote pointing at TARGET
    plus one cached snapshot.json that every test reads via `--snapshot`.

    Not a test case itself (no test_* methods) so unittest discovery
    walks over it silently.
    """

    tmpdir: "tempfile.TemporaryDirectory | None" = None
    workdir: Path
    snapshot_path: Path  # collect.sh output cached once per test class

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

        # Collect once per test class so each downstream script reads the
        # same snapshot via `--snapshot <path>` — one GraphQL fetch total.
        cls.snapshot_path = cls.workdir / "snapshot.json"
        result = subprocess.run(
            ["bash", str(SCRIPTS / "collect.sh")],
            cwd=cls.workdir,
            capture_output=True,
            text=True,
            timeout=SCRIPT_TIMEOUT_S,
        )
        if result.returncode != 0:
            raise unittest.SkipTest(
                f"collect.sh failed: {result.stderr}"
            )
        cls.snapshot_path.write_text(result.stdout)

    @classmethod
    def tearDownClass(cls) -> None:
        if cls.tmpdir is not None:
            cls.tmpdir.cleanup()

    def _run(self, script: str, *args: str, use_snapshot: bool = True) -> str:
        path = SCRIPTS / script
        self.assertTrue(path.is_file(), f"script not found: {path}")
        cmd = ["bash", str(path)]
        # collect.sh produces the snapshot; every other script consumes it
        # from the cached path to avoid a fresh GraphQL fetch per test.
        if use_snapshot and script != "collect.sh" and script != "generate-report.sh":
            cmd.extend(["--snapshot", str(self.snapshot_path)])
        cmd.extend(args)
        result = subprocess.run(
            cmd,
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
