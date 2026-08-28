#!/usr/bin/env python3
"""
Integration test for the po skill's planning surface against
beyond-scale-group/edomata.

Covers plan handling: parse-plan.sh, adherence.sh, trends.sh, and
bootstrap-plan.sh. The report-generation surface (collect / status /
milestone-progress / stale / generate-report / pr-flow) lives in
`test_po_report_integration.py` (split for #691, single file >500 LOC).

Same skip semantics as the sibling module: no `gh`, no auth, or no
`jq` -> the class is skipped cleanly.

Run locally:

    python3 claude-skills/tests/test_po_plan_integration.py
"""

from __future__ import annotations

import json
import subprocess
import tempfile
import unittest

from _po_integration_helpers import (
    SCRIPT_TIMEOUT_S,
    SCRIPTS,
    TARGET,
    BasePoIntegration,
)


class TestPoPlanIntegration(BasePoIntegration):
    """End-to-end smoke test of the planning po scripts."""

    def test_parse_plan_extracts_binding_tags(self) -> None:
        """parse-plan.sh returns one item per tagged bullet with typed bindings."""
        plan = self.workdir / "test-plan.md"
        plan.write_text(
            "# Big plan — fixture\n\n"
            "## Objectives\n"
            "- Ship redesign              [milestone:Payments-v1]\n"
            "- Migrate DB                  [epic:#142]\n"
            "- Hire DevRel                 [label:hire:devrel]\n"
            "- Do everything               [milestone:Payments-v1] [epic:#287] [label:area:core]\n"
            "- Shorthand issue ref         [#7]\n"
            "\n"
            "## Notes\n"
            "This is prose and should be skipped.\n"
        )
        out = self._run("parse-plan.sh", "--plan", str(plan), use_snapshot=False)
        items = json.loads(out)
        self.assertEqual(len(items), 5)
        # Check the multi-tag bullet picked up every binding.
        multi = next(i for i in items if i["raw"] == "Do everything")
        self.assertEqual(multi["bindings"]["milestones"], ["Payments-v1"])
        self.assertEqual(multi["bindings"]["epics"], [287])
        self.assertEqual(multi["bindings"]["labels"], ["area:core"])
        # [#7] shorthand becomes an epic binding with integer value.
        shorthand = next(i for i in items if i["raw"] == "Shorthand issue ref")
        self.assertEqual(shorthand["bindings"]["epics"], [7])
        # Section tracking.
        self.assertEqual(multi["section"], "Objectives")

    def test_parse_plan_returns_empty_array_when_missing(self) -> None:
        """A missing PLAN.md is NOT an error — emit [] so adherence can surface the gap."""
        nonexistent = self.workdir / "does-not-exist.md"
        out = self._run("parse-plan.sh", "--plan", str(nonexistent), use_snapshot=False)
        self.assertEqual(json.loads(out), [])

    def test_adherence_emits_matrix_and_drift(self) -> None:
        """adherence.sh joins a hand-written plan with the snapshot."""
        plan = self.workdir / "adherence-plan.md"
        plan.write_text(
            "# Big plan — edomata fixture\n\n"
            "## Objectives\n"
            "- Audit Renovate PRs           [#21]\n"
            "- Add release automation       [milestone:non-existent]\n"
        )
        out = subprocess.run(
            [
                "bash",
                str(SCRIPTS / "adherence.sh"),
                "--plan",
                str(plan),
                "--snapshot",
                str(self.snapshot_path),
            ],
            cwd=self.workdir,
            capture_output=True,
            text=True,
            timeout=SCRIPT_TIMEOUT_S,
        )
        self.assertEqual(out.returncode, 0, out.stderr)
        data = json.loads(out.stdout)
        self.assertTrue(data["planFound"])
        self.assertEqual(data["repo"], TARGET)
        # Top-level shape.
        for key in ("items", "drift", "summary"):
            self.assertIn(key, data)
        for drift_key in ("scopeCreep", "abandonedItems", "offCourse"):
            self.assertIn(drift_key, data["drift"])
        for summary_key in (
            "totalPlanItems",
            "notStarted",
            "inProgress",
            "done",
            "atRisk",
            "scopeCreep",
        ):
            self.assertIn(summary_key, data["summary"])
        self.assertEqual(data["summary"]["totalPlanItems"], 2)
        # Every plan item carries its derived status + counts.
        for item in data["items"]:
            self.assertIn(item["status"],
                {"done", "in_progress", "at_risk", "not_started"})
            self.assertIn("counts", item)
            self.assertIn("evidence", item)
        # PR #21 is an open Renovate PR on edomata → the #21 binding
        # should resolve to in_progress with non-zero openPrs.
        pr21_item = next(i for i in data["items"] if i["raw"] == "Audit Renovate PRs")
        self.assertEqual(pr21_item["status"], "in_progress")
        self.assertGreaterEqual(pr21_item["counts"]["openPrs"], 1)
        # Milestone binding against a non-existent milestone resolves
        # to not_started (no evidence anywhere).
        missing = next(i for i in data["items"] if i["raw"] == "Add release automation")
        self.assertEqual(missing["status"], "not_started")

    def test_trends_handles_missing_history_dir(self) -> None:
        """trends.sh emits a well-formed empty object when there's no history yet."""
        out = subprocess.run(
            ["bash", str(SCRIPTS / "trends.sh"), "--dir", "/nonexistent-po-history"],
            capture_output=True, text=True, timeout=SCRIPT_TIMEOUT_S,
        )
        self.assertEqual(out.returncode, 0, out.stderr)
        data = json.loads(out.stdout)
        self.assertEqual(data["series"], [])
        self.assertIsNone(data["velocity"])
        self.assertIsNone(data["latestChange"])

    def test_trends_derives_velocity_from_two_snapshots(self) -> None:
        """Given two history files, trends.sh computes velocity from the delta."""
        hist_dir = self.workdir / "history"
        hist_dir.mkdir(exist_ok=True)
        # Two synthetic snapshots 7 days apart; 3 issues closed, 2 PRs merged.
        for offset, (closed, merged) in enumerate([(0, 0), (3, 2)]):
            (hist_dir / f"2026-04-{1 + offset * 7:02d}.json").write_text(json.dumps({
                "generatedAt": f"2026-04-{1 + offset * 7:02d}T00:00:00Z",
                "issues": (
                    [{"state": "OPEN"}] * 5
                    + [{"state": "CLOSED"}] * closed
                ),
                "pullRequests": (
                    [{"state": "OPEN"}] * 2
                    + [{"state": "MERGED"}] * merged
                ),
                "milestones": [],
            }))
        out = subprocess.run(
            ["bash", str(SCRIPTS / "trends.sh"), "--dir", str(hist_dir)],
            capture_output=True, text=True, timeout=SCRIPT_TIMEOUT_S,
        )
        self.assertEqual(out.returncode, 0, out.stderr)
        data = json.loads(out.stdout)
        self.assertEqual(len(data["series"]), 2)
        v = data["velocity"]
        self.assertIsNotNone(v)
        self.assertEqual(v["samplePoints"], 2)
        self.assertEqual(v["spanDays"], 7)
        # 3 issues closed over 7 days = 3 per week.
        self.assertAlmostEqual(v["issuesClosedPerWeek"], 3.0, places=1)
        self.assertAlmostEqual(v["prsMergedPerWeek"], 2.0, places=1)

    def test_bootstrap_plan_emits_draft_markdown(self) -> None:
        """bootstrap-plan.sh produces a reviewable draft — no filesystem writes."""
        out = self._run("bootstrap-plan.sh")
        self.assertIn(f"# Big plan — {TARGET}", out)
        for header in (
            "## Objectives",
            "## Milestones",
            "## Epics",
            "## Cross-cutting work (by label)",
            "## Decision log",
            "## Tracked risks",
        ):
            self.assertIn(header, out, f"missing bootstrap section: {header!r}")
        # Draft references plan-schema.md so readers know how to edit it.
        self.assertIn("plan-schema.md", out)

    def test_bootstrap_plan_seeds_epics_from_issues_when_no_milestones(self) -> None:
        """#115: when no milestones and no epic labels exist, bootstrap seeds
        epics from open issues by token-clustering — not a bare placeholder."""
        snapshot = {
            'repo': 'test-org/test-repo',
            'generatedAt': '2026-05-04T00:00:00Z',
            'meta': {},
            'issues': [
                {
                    'number': 1,
                    'title': 'feat: add authentication login page',
                    'state': 'OPEN',
                    'labels': ['enhancement'],
                    'assignees': [],
                    'createdAt': '2026-01-01T00:00:00Z',
                    'updatedAt': '2026-01-01T00:00:00Z',
                    'lastCommentedAt': None,
                    'closedAt': None,
                },
                {
                    'number': 2,
                    'title': 'feat: add authentication logout flow',
                    'state': 'OPEN',
                    'labels': ['enhancement'],
                    'assignees': [],
                    'createdAt': '2026-01-01T00:00:00Z',
                    'updatedAt': '2026-01-01T00:00:00Z',
                    'lastCommentedAt': None,
                    'closedAt': None,
                },
                {
                    'number': 3,
                    'title': 'feat: authentication session refresh',
                    'state': 'OPEN',
                    'labels': ['enhancement'],
                    'assignees': [],
                    'createdAt': '2026-01-01T00:00:00Z',
                    'updatedAt': '2026-01-01T00:00:00Z',
                    'lastCommentedAt': None,
                    'closedAt': None,
                },
                {
                    'number': 4,
                    'title': 'fix: database query timeout',
                    'state': 'OPEN',
                    'labels': ['bug'],
                    'assignees': [],
                    'createdAt': '2026-01-01T00:00:00Z',
                    'updatedAt': '2026-01-01T00:00:00Z',
                    'lastCommentedAt': None,
                    'closedAt': None,
                },
            ],
            'pullRequests': [],
            'milestones': [],
            'releases': [],
        }
        with tempfile.NamedTemporaryFile(
            mode='w', suffix='.json', delete=False, dir=self.workdir
        ) as fh:
            json.dump(snapshot, fh)
            snap_path = fh.name

        result = subprocess.run(
            ['bash', str(SCRIPTS / 'bootstrap-plan.sh'), '--snapshot', snap_path],
            capture_output=True,
            text=True,
            timeout=30,
        )
        self.assertEqual(
            result.returncode, 0,
            f'bootstrap-plan.sh failed: {result.stderr}',
        )
        out = result.stdout
        # Must not emit the bare placeholder when >= 3 issues are available.
        self.assertNotIn(
            '- _No epic candidates detected. Add parent issues manually._',
            out,
            'bootstrap-plan.sh fell back to bare placeholder despite >= 3 open issues',
        )
        # Must contain at least one auto-suggested epic cluster.
        self.assertIn(
            '_auto-suggested',
            out,
            'bootstrap-plan.sh did not emit any _auto-suggested epic clusters',
        )
        # The issues should be bound in the suggestion.
        self.assertIn('#1', out)
        self.assertIn('#2', out)
        self.assertIn('#3', out)


if __name__ == "__main__":
    unittest.main(verbosity=2)
