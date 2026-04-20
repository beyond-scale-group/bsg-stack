#!/usr/bin/env python3
"""
Integration test for the po skill against beyond-scale-group/edomata.

Runs every po script against the real GitHub repo (via `GH_REPO=`
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


class TestPoReportIntegration(unittest.TestCase):
    """End-to-end smoke test of every po script against a real repo."""

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

    # -- helpers --------------------------------------------------------

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

    # -- tests ----------------------------------------------------------

    def test_collect_script_emits_valid_snapshot(self) -> None:
        """The single GraphQL snapshot all other scripts consume."""
        out = self._run("collect.sh")
        data = json.loads(out)
        self.assertEqual(data.get("repo"), TARGET)
        for key in (
            "generatedAt",
            "meta",
            "issues",
            "pullRequests",
            "milestones",
            "releases",
        ):
            self.assertIn(key, data, f"missing top-level key {key!r}")
        self.assertIsInstance(data["issues"], list)
        self.assertIsInstance(data["pullRequests"], list)
        self.assertIsInstance(data["milestones"], list)
        # Schema sanity on a single issue / PR (if any exist).
        if data["issues"]:
            issue = data["issues"][0]
            for key in (
                "number",
                "title",
                "state",
                "createdAt",
                "updatedAt",
                "assignees",
                "labels",
                "lastCommentedAt",
            ):
                self.assertIn(key, issue, f"missing issue field {key!r}")
            self.assertIsInstance(issue["assignees"], list)
            self.assertIsInstance(issue["labels"], list)
        if data["pullRequests"]:
            pr = data["pullRequests"][0]
            for key in (
                "number",
                "state",
                "isDraft",
                "reviewDecision",
                "mergeStateStatus",
                "statusCheck",
                "firstReviewAt",
                "closingIssues",
            ):
                self.assertIn(key, pr, f"missing PR field {key!r}")

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
        prs = data["pullRequests"]
        for key in (
            "open",
            "draft",
            "awaitingReview",
            "failingChecks",
            "oldestOpenAgeDays",
            "avgTimeToFirstReviewHours",
        ):
            self.assertIn(key, prs, f"missing PR metric {key!r}")
        # Derived invariants.
        self.assertLessEqual(prs["draft"], prs["open"])
        self.assertLessEqual(prs["awaitingReview"], prs["open"])
        self.assertLessEqual(prs["failingChecks"], prs["open"])
        self.assertIsInstance(data["topLabels"], list)
        self.assertIsInstance(data["byAssignee"], list)

    def test_milestone_progress_script_emits_json_array(self) -> None:
        out = self._run("milestone-progress.sh")
        data = json.loads(out)
        self.assertIsInstance(data, list)
        for m in data:
            for key in (
                "number",
                "title",
                "state",
                "openIssues",
                "closedIssues",
                "total",
                "percentComplete",
                "daysRemaining",
                "daysSinceLastClose",
                "flags",
                "url",
            ):
                self.assertIn(key, m, f"missing key {key!r} in milestone {m!r}")
            # Sanity: total should equal open + closed.
            self.assertEqual(m["total"], m["openIssues"] + m["closedIssues"])
            # percentComplete is bounded.
            self.assertGreaterEqual(m["percentComplete"], 0)
            self.assertLessEqual(m["percentComplete"], 100)
            # Every risk flag must be a boolean.
            for flag in ("overdue", "at_risk", "understaffed", "stalled"):
                self.assertIn(flag, m["flags"], f"missing flag {flag!r} on {m!r}")
                self.assertIsInstance(m["flags"][flag], bool)

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
                "lastCommentedAt",
                "lastCommentBy",
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
            "## Plan adherence",
            "## At a glance",
            "## Top labels (open issues)",
            "## Open issues by assignee",
            "## Milestone progress",
            "## Stale open issues",
            "## Oldest open PR",
        ):
            self.assertIn(header, out, f"missing section header: {header!r}")
        # New PR flow metrics must appear in the at-a-glance table.
        for metric in (
            "PRs awaiting review",
            "PRs with failing checks",
            "Oldest open PR (days)",
            "Avg time to first review",
        ):
            self.assertIn(metric, out, f"missing at-a-glance row: {metric!r}")

    # -- plan adherence -----------------------------------------------

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

    def test_pr_flow_emits_structured_metrics(self) -> None:
        """pr-flow.sh produces review latency, age buckets, merge-queue, throughput."""
        out = self._run("pr-flow.sh")
        data = json.loads(out)
        for key in ("reviewLatencyHours", "openPrs", "reviewerLoad", "mergeQueue", "throughput"):
            self.assertIn(key, data)
        # Latency stats shape.
        for stat in ("p50", "p90", "max", "sampleSize"):
            self.assertIn(stat, data["reviewLatencyHours"])
        # Open-PR age buckets cover the whole range.
        for bucket in ("le1d", "le7d", "le30d", "gt30d"):
            self.assertIn(bucket, data["openPrs"]["ageBuckets"])
            self.assertIsInstance(data["openPrs"]["ageBuckets"][bucket], int)
        # Throughput keys.
        self.assertIn("mergedLast30d", data["throughput"])
        self.assertIn("mergedPerWeek", data["throughput"])

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


if __name__ == "__main__":
    unittest.main(verbosity=2)
