"""
Tests for update-bsg-skills.py resilience (issue #67).

Verifies:
1. A dangling symlink under ~/.claude/skills/ does not abort the sync
   — agents/ and scripts/ sections still run.
2. install_file treats a broken symlink as a path it can overwrite
   (same as owned-by-manifest), rather than crashing.

Updated for #692: the updater is split across ``bsg_updater/*.py``, so
tests import the submodules directly (``bsg_updater.installer``,
``bsg_updater.reconcile``) and patch at the boundary they actually use.
"""

import sys
import tempfile
import types
import unittest
from pathlib import Path
from unittest.mock import patch


def _load_bsg_updater() -> tuple[types.ModuleType, types.ModuleType]:
    """Import the updater submodules under test.

    ``update-bsg-skills.py`` is a bootstrap wrapper that fetches
    ``bsg_updater/`` on first run. The package is committed to the repo
    so tests can import it directly without any network I/O.
    """
    scripts_dir = Path(__file__).resolve().parent.parent / "scripts"
    if str(scripts_dir) not in sys.path:
        sys.path.insert(0, str(scripts_dir))
    from bsg_updater import installer, reconcile  # noqa: WPS433 (deferred import)
    return installer, reconcile


class TestDanglingSymlinkDoesNotAbortSync(unittest.TestCase):
    """
    Regression test for #67: a dangling symlink in skills/ must not
    prevent agents/ and scripts/ from syncing.
    """

    def test_per_section_isolation(self):
        """
        reconcile() must continue to the next section even when one
        section's walk_remote raises an unexpected exception.
        """
        _, reconcile_mod = _load_bsg_updater()

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
        with patch.object(reconcile_mod, "walk_remote", side_effect=fake_walk_remote):
            # Should not raise; should complete all sections
            try:
                reconcile_mod.reconcile(manifest)
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
        installer, _ = _load_bsg_updater()

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

            with patch.object(installer, "http_get", return_value=fake_content):
                result = installer.install_file(
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
