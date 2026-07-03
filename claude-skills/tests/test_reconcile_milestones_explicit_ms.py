#!/usr/bin/env python3
"""
Regression test for issue #657 — reconcile-milestones.sh silently
assigns 0 milestones because the `as $var` jq binding used to
re-derive the milestone slug short-circuits to zero output whenever
`capture(...)` fails to match.

Root cause (see issue #657 for the full writeup):

  1. parse-plan.sh strips inline `[tag:...]` brackets out of the
     `raw` field — the parsed slug lives in `.bindings.milestones[]`,
     not in `.raw` anymore. So `capture("\\[milestone:...\\]")` against
     `.raw` never matches.
  2. In jq, `EXPR as $var | BODY` evaluates `BODY` once per *output*
     of EXPR. A non-matching `capture(...)` (without `?` recovering
     an error, and without the `[...][0]` single-output idiom)
     produces zero outputs — so `BODY` never runs at all, not even
     to try the inferred-from-title fallback. The whole per-epic
     pipeline silently emits zero lines regardless of whether the
     inferred pattern would have matched.

This test invokes reconcile-milestones.sh against a stubbed
parse-plan.sh that emits a fixture envelope shaped like the real
parser's output — one "Epics" item with `bindings.milestones:
["E1-tick-hygiene"]` and a `raw` field with the bracket tag already
stripped (matching real parse-plan.sh behaviour) — and asserts the
script reports a non-zero "epics parsed from plan" count instead of
the silent "0 epics parsed from plan" regression.

Stdlib only — no third-party dependencies, no network (gh is stubbed).

Run locally:
    python3 claude-skills/tests/test_reconcile_milestones_explicit_ms.py
"""

from __future__ import annotations

import json
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

# Mirrors the shape parse-plan.sh --typed actually emits: bracket tags
# are stripped from `raw` and resolved into `bindings.milestones[]` /
# `bindings.epics[]`. This is the exact shape that broke the old
# capture-against-raw re-derivation.
FIXTURE_ENVELOPE = {
    "status": "ok",
    "items": [
        {
            "section": "Epics",
            "raw": "tick-hygiene work",
            "bindings": {
                "milestones": ["E1-tick-hygiene"],
                "epics": [123],
                "labels": [],
            },
        }
    ],
}


class TestReconcileMilestonesExplicitMs(unittest.TestCase):

    def setUp(self):
        self.assertTrue(SCRIPT.exists(), f"reconcile-milestones.sh not found at {SCRIPT}")

    def _run_with_fixture(self) -> subprocess.CompletedProcess:
        with tempfile.TemporaryDirectory() as tmpdir:
            scripts_dir = Path(tmpdir) / "claude-skills" / "skills" / "po" / "scripts"
            scripts_dir.mkdir(parents=True)

            # Stub parse-plan.sh: emit the fixture envelope regardless of args.
            parse_plan_stub = scripts_dir / "parse-plan.sh"
            parse_plan_stub.write_text(
                "#!/usr/bin/env bash\ncat <<'JSON'\n"
                + json.dumps(FIXTURE_ENVELOPE)
                + "\nJSON\n"
            )
            parse_plan_stub.chmod(0o755)

            # Stub gh: no-op success with empty output for every call so
            # the script never touches the network and never crashes past
            # the "epics parsed from plan" line we're asserting on.
            bin_dir = Path(tmpdir) / "bin"
            bin_dir.mkdir()
            gh_stub = bin_dir / "gh"
            gh_stub.write_text(
                textwrap.dedent(
                    """\
                    #!/usr/bin/env bash
                    exit 0
                    """
                )
            )
            gh_stub.chmod(0o755)

            sut = scripts_dir / "reconcile-milestones.sh"
            sut.symlink_to(SCRIPT)

            env = {
                **os.environ,
                "PATH": str(bin_dir) + ":" + str(scripts_dir) + ":" + os.environ.get("PATH", ""),
            }

            return subprocess.run(
                ["bash", str(sut)],
                cwd=tmpdir,
                capture_output=True,
                text=True,
                env=env,
                timeout=30,
            )

    def test_explicit_milestone_binding_is_parsed(self):
        """A plan item with an already-resolved [milestone:] binding must
        be counted — not silently dropped to zero.

        Before the #657 fix: stdout contains "0 epics parsed from plan"
        even though the fixture carries one epic with an explicit
        milestone binding.
        After the fix: stdout contains "1 epics parsed from plan".
        """
        result = self._run_with_fixture()
        self.assertIn(
            "1 epics parsed from plan",
            result.stdout,
            "Regression #657: reconcile-milestones.sh must count the explicit "
            f"[milestone:] binding, not silently drop to zero.\n"
            f"stdout={result.stdout}\nstderr={result.stderr}",
        )
        self.assertNotIn(
            "0 epics parsed from plan",
            result.stdout,
            f"Regression #657 reproduced: 0 epics parsed.\nstdout={result.stdout}",
        )


if __name__ == "__main__":
    unittest.main()
