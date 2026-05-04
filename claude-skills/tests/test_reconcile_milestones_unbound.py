#!/usr/bin/env python3
"""
Regression test for issue #546 — reconcile-milestones.sh fails with
'slug_to_nums: unbound variable' when epic_lines is empty.

The script uses `set -euo pipefail`. When `epic_lines` is empty, the
for loop never writes a key into the `declare -A slug_to_nums` array.
Under bash 5.x, referencing `${#slug_to_nums[@]}` on a never-populated
associative array trips "unbound variable" and aborts the script.

This test invokes the script in an isolated tmpdir with an empty /
missing PLAN.md and asserts that the script exits 0 (or with a clean
"no plan" skip) rather than failing with "unbound variable".

It also validates that the fix (sentinel-touch pattern) is present in
the script source and that the patched pattern executes cleanly.

Stdlib only — no third-party dependencies, no network.

Run locally:
    python3 claude-skills/tests/test_reconcile_milestones_unbound.py
"""

from __future__ import annotations

import os
import subprocess
import tempfile
import textwrap
import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
SCRIPT = (
    REPO_ROOT / "claude-skills" / "skills" / "po" / "scripts" / "reconcile-milestones.sh"
)


class TestReconcileMilestonesUnbound(unittest.TestCase):

    def setUp(self):
        self.assertTrue(
            SCRIPT.exists(),
            f"reconcile-milestones.sh not found at {SCRIPT}",
        )

    def _run_in_tmpdir(self, extra_env: dict | None = None) -> subprocess.CompletedProcess:
        """Run the script in a fresh tmpdir that looks like a repo root with no plan."""
        with tempfile.TemporaryDirectory() as tmpdir:
            # Create minimal directory structure expected by the script
            po_dir = Path(tmpdir) / "po"
            po_dir.mkdir()

            # Write a stub parse-plan.sh that returns an empty envelope
            # so epic_lines is empty, triggering the unbound-variable path.
            scripts_dir = Path(tmpdir) / "claude-skills" / "skills" / "po" / "scripts"
            scripts_dir.mkdir(parents=True)

            parse_plan_stub = scripts_dir / "parse-plan.sh"
            parse_plan_stub.write_text(
                textwrap.dedent("""\
                    #!/usr/bin/env bash
                    # Stub: return empty JSON envelope (no epics)
                    echo '{"items":[]}'
                """)
            )
            parse_plan_stub.chmod(0o755)

            # Link the real script into the tmpdir so relative paths resolve
            sut = scripts_dir / "reconcile-milestones.sh"
            sut.symlink_to(SCRIPT)

            env = {**os.environ, "PATH": str(scripts_dir) + ":" + os.environ.get("PATH", "")}
            if extra_env:
                env.update(extra_env)

            # Run from the tmpdir so the script's `po/PLAN.md` lookup lands
            # in a directory with no plan file — the shortest path to
            # triggering the "no plan" early-exit (which is fine) or, on
            # an unpatched script, the "unbound variable" crash.
            result = subprocess.run(
                ["bash", str(sut)],
                cwd=tmpdir,
                capture_output=True,
                text=True,
                env=env,
            )
            return result

    def test_empty_plan_does_not_produce_unbound_variable_error(self):
        """Script must not abort with 'unbound variable' when plan has no epics.

        Regression test for #546. Before the fix, bash 5.x exits 1 and
        stderr contains 'slug_to_nums: unbound variable'.
        After the fix, the script exits 0 with a clean 'nothing to
        reconcile' message.
        """
        result = self._run_in_tmpdir()
        self.assertNotIn(
            "unbound variable",
            result.stderr,
            f"Script aborted with 'unbound variable'.\nstdout={result.stdout}\nstderr={result.stderr}",
        )
        self.assertEqual(
            result.returncode,
            0,
            f"Script exited {result.returncode} (expected 0).\nstdout={result.stdout}\nstderr={result.stderr}",
        )

    def test_script_contains_sentinel_touch_fix(self):
        """reconcile-milestones.sh must contain the sentinel-touch fix for #546.

        The fix initialises slug_to_nums with a dummy key then immediately
        unsets it, so bash 5.x considers the array "bound" before the first
        ${#slug_to_nums[@]} reference even when the populate loop never ran.
        """
        content = SCRIPT.read_text()
        self.assertIn(
            'slug_to_nums["__init__"]=""',
            content,
            "Fix #546: sentinel initialisation slug_to_nums[\"__init__\"]=\"\" not found in script",
        )
        self.assertIn(
            "unset 'slug_to_nums[__init__]'",
            content,
            "Fix #546: sentinel unset 'slug_to_nums[__init__]' not found in script",
        )

    def test_patched_pattern_does_not_abort_under_set_u(self):
        """The sentinel-touch pattern must allow ${#slug_to_nums[@]} under set -u.

        Validates that the exact fix committed in #546 executes cleanly on
        the current bash: declare -A, touch+unset sentinel, empty loop,
        then ${#slug_to_nums[@]} must not produce 'unbound variable'.
        """
        snippet = textwrap.dedent("""\
            set -euo pipefail
            declare -A slug_to_nums
            # Sentinel touch — the fix from #546
            slug_to_nums["__init__"]=""
            unset 'slug_to_nums[__init__]'
            # Simulate the loop that never writes a real key
            for line in ""; do
                [[ -z "$line" ]] && continue
                slug="${line%%$'\\t'*}"
                slug_to_nums["$slug"]="1"
            done
            # This was the crash site before the fix:
            echo "count: ${#slug_to_nums[@]}"
        """)
        result = subprocess.run(
            ["bash", "-c", snippet],
            capture_output=True,
            text=True,
        )
        self.assertNotIn(
            "unbound variable",
            result.stderr,
            f"Patched inline snippet still hits 'unbound variable'.\nstderr={result.stderr}",
        )
        self.assertEqual(
            result.returncode,
            0,
            f"Patched inline snippet exited {result.returncode}.\nstderr={result.stderr}",
        )


if __name__ == "__main__":
    unittest.main()
