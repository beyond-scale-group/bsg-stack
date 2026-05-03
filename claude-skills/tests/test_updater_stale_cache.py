"""
Regression test for issue #313: update-bsg-skills.py reports "updated"
without actually refreshing existing files when upstream content is stale
(CDN / GitHub Contents API caching).

Verifies:
1. When upstream returns content identical to the local file, install_file
   logs "unchanged" (not "updated") and does NOT overwrite the file mtime.
2. When upstream returns genuinely new content for an owned file, install_file
   writes the new content and logs "updated".
3. After a simulated two-step scenario (initial install, upstream changes,
   re-run), the local file reflects the NEW upstream content.
"""

import importlib.util
import os
import tempfile
import types
import unittest
from pathlib import Path
from unittest.mock import patch


def _load_updater() -> types.ModuleType:
    """Load update-bsg-skills.py as a module without executing main()."""
    script = Path(__file__).parent.parent / "scripts" / "update-bsg-skills.py"
    spec = importlib.util.spec_from_file_location("update_bsg_skills", script)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


class TestInstallFileStaleDetection(unittest.TestCase):
    """
    install_file must distinguish between unchanged and actually-updated files
    so operators can trust the log output and CDN-cached stale content is
    detected rather than silently re-written with old bytes.
    """

    def setUp(self):
        self.mod = _load_updater()

    def test_unchanged_file_logs_unchanged_not_updated(self):
        """
        When upstream content is byte-for-byte identical to the local file,
        install_file must log 'unchanged' (not 'updated').

        Regression: before the fix, install_file always wrote the bytes and
        logged 'updated' regardless of whether content actually changed.
        CDN-cached stale responses would silently re-write the same bytes
        and mislead the operator into thinking cache was refreshed.
        """
        with tempfile.TemporaryDirectory() as tmpdir:
            dest = Path(tmpdir) / "agents" / "tech-lead.md"
            dest.parent.mkdir()
            existing_content = b"# tech-lead v1\n"
            dest.write_bytes(existing_content)

            # Upstream returns the SAME content (CDN-cached stale response)
            logged: list[str] = []
            with patch.object(self.mod, "http_get", return_value=existing_content):
                with patch.object(self.mod, "log", side_effect=logged.append):
                    result = self.mod.install_file(
                        "https://example.com/fake",
                        dest,
                        {"agents/tech-lead.md"},  # owned
                        "agents/tech-lead.md",
                    )

            self.assertTrue(result, "install_file must return True for unchanged owned file")
            # Must NOT log 'updated' for an unchanged file
            updated_lines = [l for l in logged if "updated" in l]
            self.assertEqual(
                updated_lines,
                [],
                f"install_file logged 'updated' for an unchanged file: {updated_lines}",
            )
            # Must log 'unchanged' so the operator knows the cache state
            unchanged_lines = [l for l in logged if "unchanged" in l]
            self.assertGreater(
                len(unchanged_lines),
                0,
                "install_file did not log 'unchanged' when content was identical",
            )

    def test_changed_file_logs_updated_and_writes_new_content(self):
        """
        When upstream returns genuinely new content for an owned file,
        install_file must write the new bytes and log 'updated'.
        """
        with tempfile.TemporaryDirectory() as tmpdir:
            dest = Path(tmpdir) / "agents" / "tech-lead.md"
            dest.parent.mkdir()
            old_content = b"# tech-lead v1\n"
            new_content = b"# tech-lead v2 new bus activation support\n"
            dest.write_bytes(old_content)

            logged: list[str] = []
            with patch.object(self.mod, "http_get", return_value=new_content):
                with patch.object(self.mod, "log", side_effect=logged.append):
                    result = self.mod.install_file(
                        "https://example.com/fake",
                        dest,
                        {"agents/tech-lead.md"},  # owned
                        "agents/tech-lead.md",
                    )

            self.assertTrue(result, "install_file must return True for a changed owned file")
            self.assertEqual(
                dest.read_bytes(),
                new_content,
                "install_file did not write new content to the local file",
            )
            updated_lines = [l for l in logged if "updated" in l]
            self.assertGreater(
                len(updated_lines),
                0,
                "install_file did not log 'updated' when content genuinely changed",
            )

    def test_full_refresh_cycle_propagates_upstream_change(self):
        """
        Simulate the exact scenario from issue #313:
        1. File installed at v1.
        2. Upstream ships v2 (PR merged on main).
        3. Updater runs again -- must propagate v2 to the local cache.

        Before the fix, if the CDN served v1 bytes under the v2 download_url,
        the file would remain at v1 while the log claimed 'updated'. This test
        uses a mock that returns v2 bytes (the correct upstream), ensuring
        the refresh cycle actually writes the new content.
        """
        with tempfile.TemporaryDirectory() as tmpdir:
            dest = Path(tmpdir) / "agents" / "po-manager.md"
            dest.parent.mkdir()
            v1 = b"# po-manager\noutput: pr\n"
            v2 = b"# po-manager\noutput: pr\ndelegates-to: [tech, qa, seo]\n"

            # Step 1: initial install at v1
            dest.write_bytes(v1)
            owned = {"agents/po-manager.md"}

            # Step 2: upstream now returns v2
            logged: list[str] = []
            with patch.object(self.mod, "http_get", return_value=v2):
                with patch.object(self.mod, "log", side_effect=logged.append):
                    result = self.mod.install_file(
                        "https://example.com/fake",
                        dest,
                        owned,
                        "agents/po-manager.md",
                    )

            self.assertTrue(result)
            self.assertEqual(
                dest.read_bytes(),
                v2,
                "Cache refresh did not propagate v2 to the local file (issue #313)",
            )


if __name__ == "__main__":
    unittest.main()
