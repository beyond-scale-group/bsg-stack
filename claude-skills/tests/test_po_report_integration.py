#!/usr/bin/env python3
"""
Integration test for the po skill against beyond-scale-group/edomata.

Covers the report-generation pipeline: collect.sh, status.sh,
milestone-progress.sh, stale-issues.sh, generate-report.sh, and
pr-flow.sh — all reading from the shared cached snapshot.

Plan / adherence / trends / bootstrap tests live in
`test_po_plan_integration.py` (split for #691, single file >500 LOC).

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
import unittest

from _po_integration_helpers import TARGET, BasePoIntegration


class TestPoReportIntegration(BasePoIntegration):
    """End-to-end smoke test of the report-generation po scripts."""

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


if __name__ == "__main__":
    unittest.main(verbosity=2)
