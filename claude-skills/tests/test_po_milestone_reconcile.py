#!/usr/bin/env python3
"""
Unit tests for issue #288 — po-manager reads GitHub milestones
instead of epic:* labels.

Validates:
  1. reconcile-milestones.sh exists and is executable
  2. reconcile-labels.sh has been renamed (no longer present)
  3. po-manager.md tick section calls reconcile-milestones.sh, not
     reconcile-labels.sh
  4. adherence.md examples reference [milestone:] bindings

Stdlib only — no third-party dependencies, no network.

Run locally:
    python3 claude-skills/tests/test_po_milestone_reconcile.py
"""

from __future__ import annotations

import os
import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
PO_SCRIPTS = REPO_ROOT / "claude-skills" / "skills" / "po" / "scripts"
PO_AGENT = REPO_ROOT / "claude-skills" / "agents" / "po-manager.md"
ADHERENCE_REF = REPO_ROOT / "claude-skills" / "skills" / "po" / "references" / "adherence.md"


class TestReconcileMilestones(unittest.TestCase):

    def test_reconcile_milestones_script_exists(self):
        """reconcile-milestones.sh must exist after the rename."""
        script = PO_SCRIPTS / "reconcile-milestones.sh"
        self.assertTrue(
            script.exists(),
            f"reconcile-milestones.sh not found at {script} — issue #288 requires the rename",
        )

    def test_reconcile_milestones_script_is_executable(self):
        """reconcile-milestones.sh must be executable."""
        script = PO_SCRIPTS / "reconcile-milestones.sh"
        if not script.exists():
            self.skipTest("reconcile-milestones.sh does not exist yet")
        self.assertTrue(
            os.access(script, os.X_OK),
            "reconcile-milestones.sh exists but is not executable",
        )

    def test_reconcile_labels_script_removed(self):
        """reconcile-labels.sh must no longer exist — it was renamed."""
        old_script = PO_SCRIPTS / "reconcile-labels.sh"
        self.assertFalse(
            old_script.exists(),
            "reconcile-labels.sh still exists — it should have been renamed to "
            "reconcile-milestones.sh per issue #288",
        )

    def test_reconcile_milestones_uses_milestone_api(self):
        """reconcile-milestones.sh must call gh api milestones, not create epic: labels."""
        script = PO_SCRIPTS / "reconcile-milestones.sh"
        if not script.exists():
            self.skipTest("reconcile-milestones.sh does not exist yet")
        content = script.read_text()
        self.assertIn(
            "milestone",
            content.lower(),
            "reconcile-milestones.sh must reference milestones in its logic",
        )
        self.assertNotIn(
            'label create "epic:',
            content,
            "reconcile-milestones.sh must not create epic: labels — use milestones instead",
        )

    def test_po_manager_tick_calls_reconcile_milestones(self):
        """po-manager.md tick section must call reconcile-milestones.sh."""
        self.assertTrue(PO_AGENT.exists(), f"po-manager.md not found at {PO_AGENT}")
        content = PO_AGENT.read_text()
        self.assertIn(
            "reconcile-milestones.sh",
            content,
            "po-manager.md must reference reconcile-milestones.sh (not reconcile-labels.sh)",
        )
        self.assertNotIn(
            "reconcile-labels.sh",
            content,
            "po-manager.md must not reference reconcile-labels.sh after issue #288",
        )

    def test_adherence_md_uses_milestone_binding_examples(self):
        """adherence.md examples must reference [milestone:] not only [epic:#N]."""
        self.assertTrue(ADHERENCE_REF.exists(), f"adherence.md not found at {ADHERENCE_REF}")
        content = ADHERENCE_REF.read_text()
        self.assertIn(
            "[milestone:",
            content,
            "adherence.md must include [milestone:] binding examples per issue #288",
        )


if __name__ == "__main__":
    unittest.main()
