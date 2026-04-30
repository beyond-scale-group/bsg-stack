"""
Tests for update-bsg-skills.py resilience (issue #67).

Verifies:
1. A dangling symlink under ~/.claude/skills/ does not abort the sync
   — agents/ and scripts/ sections still run.
2. install_file treats a broken symlink as a path it can overwrite
   (same as owned-by-manifest), rather than crashing.
"""

import importlib.util
import json
import os
import sys
import tempfile
import types
import unittest
from pathlib import Path
from unittest.mock import MagicMock, patch


def _load_updater(monkeypatch_env: dict | None = None) -> types.ModuleType:
    """Load update-bsg-skills.py as a module without executing main()."""
    script = (
        Path(__file__).parent.parent / "scripts" / "update-bsg-skills.py"
    )
    spec = importlib.util.spec_from_file_location("update_bsg_skills", script)
    mod = importlib.util.module_from_spec(spec)
    # Patch CLAUDE_DIR before the module-level token discovery runs
    if monkeypatch_env:
        old = {k: os.environ.get(k) for k in monkeypatch_env}
        os.environ.update(monkeypatch_env)
    spec.loader.exec_module(mod)
    if monkeypatch_env:
        for k, v in old.items():
            if v is None:
                os.environ.pop(k, None)
            else:
                os.environ[k] = v
    return mod


class TestDanglingSymlinkDoesNotAbortSync(unittest.TestCase):
    """
    Regression test for #67: a dangling symlink in skills/ must not
    prevent agents/ and scripts/ from syncing.
    """

    def test_per_section_isolation(self):
        """
        reconcile() must continue to the next section even when one
        section's install_file raises an unexpected exception.
        """
        mod = _load_updater()

        # Track which sections were attempted
        attempted: list[str] = []

        def fake_walk_remote(api_path, dest_dir, rel_prefix):
            attempted.append(rel_prefix)
            if rel_prefix == "skills":
                # Simulate a FileExistsError raised by mkdir on a broken symlink
                raise FileExistsError(
                    17, "File exists", str(dest_dir / "github-compliance")
                )
            return [], True

        manifest = {"files": []}
        with patch.object(mod, "walk_remote", side_effect=fake_walk_remote):
            # Should not raise; should complete all sections
            try:
                mod.reconcile(manifest)
            except FileExistsError:
                self.fail(
                    "reconcile() propagated FileExistsError — "
                    "per-section isolation is missing (issue #67)"
                )

        # agents and scripts must still have been attempted even though skills crashed
        self.assertIn("agents", attempted, "agents section was skipped after skills crashed")
        self.assertIn("scripts", attempted, "scripts section was skipped after skills crashed")

    def test_broken_symlink_is_overwritable(self):
        """
        install_file must treat a broken symlink as a writable destination,
        not skip it as 'exists, not owned by BSG manifest'.
        """
        mod = _load_updater()

        with tempfile.TemporaryDirectory() as tmpdir:
            dest = Path(tmpdir) / "subdir" / "target.md"
            dest.parent.mkdir()
            # Create a dangling symlink at dest
            dangling_target = Path(tmpdir) / "nonexistent"
            dest.symlink_to(dangling_target)
            self.assertTrue(dest.is_symlink())
            self.assertFalse(dest.exists())  # dangling

            # File is NOT in the manifest (empty owned set)
            owned: set = set()
            fake_content = b"# hello from upstream"

            with patch.object(mod, "http_get", return_value=fake_content):
                result = mod.install_file(
                    "https://example.com/fake", dest, owned, "skills/github-compliance/SKILL.md"
                )

            self.assertTrue(
                result,
                "install_file returned False for a dangling symlink — "
                "it should overwrite the broken link, not skip it (issue #67)"
            )
            # The destination should now be a real file with the fetched content
            self.assertTrue(dest.exists() and not dest.is_symlink())
            self.assertEqual(dest.read_bytes(), fake_content)


if __name__ == "__main__":
    unittest.main()
