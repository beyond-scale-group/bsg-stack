#!/usr/bin/env python3
"""Per-agent frontmatter rules for the BSG claude-skills catalog.

Validates that each agent file declares the BSG-wide convention fields
in its YAML frontmatter:

  - tick:                   periodic-run convention (#33)
  - output:                 pr | commit | chat (CLAUDE.md → PRs)
  - auto-implements:        scope contract (#200)
  - never-auto-implements:  scope contract (#200)
  - custom-doc:             per-repo document under .bsg/ (#237)
  - init:                   how --init generates the custom doc (#237)
  - registry alignment:     registry.json output matches frontmatter
  - tick semantics:         no full-stop short-circuit (#261),
                            adaptive back-off (#363),
                            PR URL capture for output: pr (#462)
  - pilot receipts:         seven canonical outcomes for output: commit (#263)

Catalog and footer invariants live in test_skill_invariants.py.

Run locally:

    python3 claude-skills/tests/test_agent_frontmatter.py
"""

from __future__ import annotations

import re
import unittest

from _skill_helpers import (
    ALLOWED_OUTPUT_MODES,
    FRONTMATTER_RE,
    FRONTMATTER_SCALAR_RE,
    REPO_ROOT,
    SKILLS_DIR,
    TOP_LEVEL_KEY_RE,
    extract_folded_body,
    extract_tick_body,
    list_agents,
    list_skill_entrypoints,
)


class TestAgentFrontmatter(unittest.TestCase):
    # ------------------------------------------------------------- tick action

    def test_every_agent_declares_a_tick_action(self) -> None:
        """Every agent file must declare a `tick` field in its frontmatter.

        The `tick` action is the BSG-wide convention for periodic agent runs
        (see CLAUDE.md → "The `tick` convention"). Each agent must document
        in one place — its frontmatter — what `tick` does for that agent,
        so users can discover it uniformly across the catalog.

        Silent-by-default semantics and commit behavior are defined in the
        convention; the per-agent `tick` field describes the concrete work
        and the conditions under which the agent breaks silence.
        """
        agents = list_agents()
        self.assertGreater(len(agents), 0, "no agents discovered")
        for path in agents:
            with self.subTest(agent=path.stem):
                text = path.read_text()
                fm_match = FRONTMATTER_RE.match(text)
                self.assertIsNotNone(
                    fm_match,
                    f"{path.relative_to(REPO_ROOT)}: missing or malformed "
                    f"YAML frontmatter (expected '---\\n...\\n---' at top).",
                )
                frontmatter = fm_match.group(1)
                keys = set(TOP_LEVEL_KEY_RE.findall(frontmatter))
                self.assertIn(
                    "tick",
                    keys,
                    f"{path.relative_to(REPO_ROOT)}: agent frontmatter is "
                    f"missing a `tick:` field. Every BSG agent must declare "
                    f"what its periodic `tick` action does — see CLAUDE.md "
                    f"→ 'The `tick` convention' and beyond-scale-group/bsg-stack#33. "
                    f"Found keys: {sorted(keys)}.",
                )
                tick_body = extract_tick_body(frontmatter)
                self.assertTrue(
                    tick_body.strip(),
                    f"{path.relative_to(REPO_ROOT)}: `tick:` field is empty. "
                    f"Describe what this agent's periodic tick does.",
                )

    # ---------------------------------------------------------- output mode

    def test_every_agent_declares_an_output_mode(self) -> None:
        """Every agent file must declare a valid `output:` in frontmatter.

        Allowed values: pr, commit, chat. See CLAUDE.md →
        "Reporting agents output via auto-merge PRs" for the semantics:
        reporting agents must use `output: pr` and call
        `claude-skills/scripts/open-report-pr.sh` to wrap their output in
        an auto-merge PR instead of pushing directly to main.
        """
        agents = list_agents()
        self.assertGreater(len(agents), 0, "no agents discovered")
        for path in agents:
            with self.subTest(agent=path.stem):
                text = path.read_text()
                fm_match = FRONTMATTER_RE.match(text)
                self.assertIsNotNone(
                    fm_match,
                    f"{path.relative_to(REPO_ROOT)}: missing or malformed "
                    f"YAML frontmatter (expected '---\\n...\\n---' at top).",
                )
                frontmatter = fm_match.group(1)
                scalars = dict(FRONTMATTER_SCALAR_RE.findall(frontmatter))
                self.assertIn(
                    "output",
                    scalars,
                    f"{path.relative_to(REPO_ROOT)}: agent frontmatter is "
                    f"missing a scalar `output:` field. Every BSG agent must "
                    f"declare where its results go — see CLAUDE.md → "
                    f"'Reporting agents output via auto-merge PRs'. "
                    f"Allowed values: {sorted(ALLOWED_OUTPUT_MODES)}.",
                )
                value = scalars["output"]
                self.assertIn(
                    value,
                    ALLOWED_OUTPUT_MODES,
                    f"{path.relative_to(REPO_ROOT)}: unknown `output: {value}`. "
                    f"Allowed values: {sorted(ALLOWED_OUTPUT_MODES)}.",
                )

    # -------------------------------------------------- scope contract (#200)

    def test_every_agent_declares_scope_contract_fields(self) -> None:
        """Every agent frontmatter must carry `auto-implements` and
        `never-auto-implements` lists (may be empty for output: pr agents).

        For `output: commit` agents the contract is additionally enforced —
        both lists must be non-empty so the reviewer can see exactly what
        the agent will (and won't) attempt automatically. See CLAUDE.md →
        "Per-agent scope contract" and ticket #200.
        """
        agents = list_agents()
        for path in agents:
            with self.subTest(agent=path.stem):
                text = path.read_text()
                fm_match = FRONTMATTER_RE.match(text)
                self.assertIsNotNone(fm_match)
                frontmatter = fm_match.group(1)
                keys = set(TOP_LEVEL_KEY_RE.findall(frontmatter))

                self.assertIn(
                    "auto-implements",
                    keys,
                    f"{path.relative_to(REPO_ROOT)}: missing `auto-implements:` "
                    f"in frontmatter. Add an empty list `auto-implements: []` "
                    f"for output: pr agents; see #200 for the schema.",
                )
                self.assertIn(
                    "never-auto-implements",
                    keys,
                    f"{path.relative_to(REPO_ROOT)}: missing "
                    f"`never-auto-implements:` in frontmatter. Add an empty "
                    f"list for output: pr agents; see #200 for the schema.",
                )

                scalars = dict(FRONTMATTER_SCALAR_RE.findall(frontmatter))
                if scalars.get("output") == "commit":
                    auto_line = re.search(
                        r"^auto-implements:\s*(.*)$", frontmatter, re.MULTILINE
                    )
                    never_line = re.search(
                        r"^never-auto-implements:\s*(.*)$", frontmatter, re.MULTILINE
                    )
                    auto_empty = (
                        auto_line is not None
                        and auto_line.group(1).strip().startswith("[]")
                    ) or not re.search(
                        r"^auto-implements:\s*\n\s*-\s+", frontmatter, re.MULTILINE
                    )
                    never_empty = (
                        never_line is not None
                        and never_line.group(1).strip().startswith("[]")
                    ) or not re.search(
                        r"^never-auto-implements:\s*\n\s*-\s+",
                        frontmatter,
                        re.MULTILINE,
                    )
                    self.assertFalse(
                        auto_empty,
                        f"{path.relative_to(REPO_ROOT)}: output: commit agents "
                        f"must list at least one `auto-implements` clause.",
                    )
                    self.assertFalse(
                        never_empty,
                        f"{path.relative_to(REPO_ROOT)}: output: commit agents "
                        f"must list at least one `never-auto-implements` clause.",
                    )

    # -------------------------------------- pilot receipt (#263)

    def test_output_commit_agents_document_pilot_receipts(self) -> None:
        """Every output: commit agent must document all seven canonical
        pilot receipt outcomes (#263).

        The pilot receipt is a mandatory single-line phase-B log that
        prevents silent phase-B skips. Each canonical outcome string
        must appear somewhere in the agent definition file.
        """
        PILOT_RECEIPT_MARKERS = [
            "pilot: attempted #NN",
            "pilot: no candidates",
            "pilot: blocked by circuit-breaker",
            "pilot: not authorized",
            "pilot: skipped #NN — never-auto-implements",
            "pilot: skipped #NN — no test harness",
            "pilot: aborted #NN — budget",
        ]
        for path in list_agents():
            with self.subTest(agent=path.stem):
                text = path.read_text()
                fm_match = FRONTMATTER_RE.match(text)
                self.assertIsNotNone(fm_match)
                scalars = dict(FRONTMATTER_SCALAR_RE.findall(fm_match.group(1)))
                if scalars.get("output") != "commit":
                    continue
                for marker in PILOT_RECEIPT_MARKERS:
                    self.assertIn(
                        marker,
                        text,
                        f"{path.relative_to(REPO_ROOT)}: output: commit agent "
                        f"must document the canonical pilot receipt "
                        f"'{marker}' — see #263.",
                    )

    # ---------------------------------------- custom-doc + init (#237)

    def test_every_agent_declares_custom_doc(self) -> None:
        """Every agent must declare a `custom-doc:` field listing the
        per-repo document(s) it reads/writes under .bsg/.

        See CLAUDE.md → "Unified .bsg/ directory convention" and #237.
        """
        agents = list_agents()
        self.assertGreater(len(agents), 0, "no agents discovered")
        for path in agents:
            with self.subTest(agent=path.stem):
                text = path.read_text()
                fm_match = FRONTMATTER_RE.match(text)
                self.assertIsNotNone(fm_match)
                frontmatter = fm_match.group(1)
                scalars = dict(FRONTMATTER_SCALAR_RE.findall(frontmatter))
                self.assertIn(
                    "custom-doc",
                    scalars,
                    f"{path.relative_to(REPO_ROOT)}: agent frontmatter is "
                    f"missing a `custom-doc:` field. Every BSG agent must "
                    f"declare the per-repo document it reads/writes — see "
                    f"#237 for the schema.",
                )
                self.assertTrue(
                    scalars["custom-doc"].strip(),
                    f"{path.relative_to(REPO_ROOT)}: `custom-doc:` is empty. "
                    f"Specify the .bsg/ path this agent owns.",
                )

    def test_every_agent_declares_init_action(self) -> None:
        """Every agent must declare an `init:` field in frontmatter
        describing what --init generates and from what sources.

        See CLAUDE.md → "Mandatory --init on every agent" and #237.
        """
        agents = list_agents()
        self.assertGreater(len(agents), 0, "no agents discovered")
        for path in agents:
            with self.subTest(agent=path.stem):
                text = path.read_text()
                fm_match = FRONTMATTER_RE.match(text)
                self.assertIsNotNone(fm_match)
                frontmatter = fm_match.group(1)
                keys = set(TOP_LEVEL_KEY_RE.findall(frontmatter))
                self.assertIn(
                    "init",
                    keys,
                    f"{path.relative_to(REPO_ROOT)}: agent frontmatter is "
                    f"missing an `init:` field. Every BSG agent must declare "
                    f"what its --init generates — see #237.",
                )
                init_body = extract_folded_body(frontmatter, "init")
                self.assertTrue(
                    init_body.strip(),
                    f"{path.relative_to(REPO_ROOT)}: `init:` field is empty. "
                    f"Describe what --init generates and from what sources.",
                )

    def test_every_skill_with_custom_doc_has_init(self) -> None:
        """Skills that declare a custom-doc must also declare init."""
        skills = list_skill_entrypoints()
        for path in skills:
            with self.subTest(skill=path.parent.name):
                text = path.read_text()
                fm_match = FRONTMATTER_RE.match(text)
                if not fm_match:
                    continue
                frontmatter = fm_match.group(1)
                scalars = dict(FRONTMATTER_SCALAR_RE.findall(frontmatter))
                if "custom-doc" not in scalars:
                    continue
                keys = set(TOP_LEVEL_KEY_RE.findall(frontmatter))
                self.assertIn(
                    "init",
                    keys,
                    f"{path.relative_to(REPO_ROOT)}: skill declares "
                    f"`custom-doc: {scalars['custom-doc']}` but has no "
                    f"`init:` field. Skills with a custom doc must declare "
                    f"how --init generates it — see #237.",
                )
                init_body = extract_folded_body(frontmatter, "init")
                self.assertTrue(
                    init_body.strip(),
                    f"{path.relative_to(REPO_ROOT)}: `init:` field is empty.",
                )

    # ---------------------------------------- registry/frontmatter alignment

    def test_registry_output_matches_frontmatter(self) -> None:
        """registry.json output field must match the agent's frontmatter."""
        import json

        registry_path = SKILLS_DIR / "agents" / "registry.json"
        if not registry_path.is_file():
            self.skipTest("registry.json not found")
        registry = json.loads(registry_path.read_text())
        agent_map = {a["name"]: a["output"] for a in registry["agents"]}

        for path in list_agents():
            name = path.stem
            if name not in agent_map:
                continue
            with self.subTest(agent=name):
                text = path.read_text()
                fm_match = FRONTMATTER_RE.match(text)
                self.assertIsNotNone(fm_match)
                scalars = dict(FRONTMATTER_SCALAR_RE.findall(fm_match.group(1)))
                self.assertEqual(
                    scalars.get("output"),
                    agent_map[name],
                    f"{name}: registry.json says output={agent_map[name]} but "
                    f"frontmatter says output={scalars.get('output')}.",
                )

    # --------------------------------- tick short-circuit scope (#261)

    def test_commit_agents_tick_does_not_short_circuit_phase_b(self) -> None:
        """output: commit agents must not skip phase (B) on audit short-circuit.

        The tick-fingerprint short-circuit only means the audit (A) is
        unchanged. Phases (B) implementation pilot and (C) peer review have
        independent triggers and must always run. See #261.
        """
        for path in list_agents():
            with self.subTest(agent=path.stem):
                text = path.read_text()
                fm_match = FRONTMATTER_RE.match(text)
                self.assertIsNotNone(fm_match)
                frontmatter = fm_match.group(1)
                scalars = dict(FRONTMATTER_SCALAR_RE.findall(frontmatter))
                if scalars.get("output") != "commit":
                    continue
                tick_body = extract_tick_body(frontmatter)
                self.assertNotRegex(
                    tick_body,
                    r"SHORT_CIRCUIT.*and stop",
                    f"{path.relative_to(REPO_ROOT)}: tick field instructs a "
                    f"full stop on audit short-circuit, which blocks phase "
                    f"(B) implementation pilot from running. The short-circuit "
                    f"should only skip phases (A) and (A.5). See #261.",
                )

    # --------------------------------- adaptive back-off (#363)

    def test_all_agents_tick_has_adaptive_backoff(self) -> None:
        """Every agent tick must include the adaptive back-off step (0.6).

        tick-idle-check.sh short-circuits the tick when there are no
        phase-B candidates AND the audit fingerprint matches yesterday's.
        Without it, a no-change tick-all sweep reruns the full audit
        pipeline for every agent on every loop — the primary token-burn
        source identified in E1-tick-hygiene. See #363 and #393.
        """
        for path in list_agents():
            with self.subTest(agent=path.stem):
                text = path.read_text()
                fm_match = FRONTMATTER_RE.match(text)
                self.assertIsNotNone(fm_match)
                frontmatter = fm_match.group(1)
                tick_body = extract_tick_body(frontmatter)
                self.assertIn(
                    "tick-idle-check.sh",
                    tick_body,
                    f"{path.relative_to(REPO_ROOT)}: tick field is missing the "
                    f"adaptive back-off step (0.6). Add: eval \"$(bash "
                    f"claude-skills/scripts/tick-idle-check.sh <agent> <bus> "
                    f"<report-dir>)\". See #363 and #393.",
                )

    # ----------------------------------------- output:pr agents have exclusions

    def test_pr_agents_have_never_auto_implements_clauses(self) -> None:
        """output: pr agents must carry at least one never-auto-implements clause."""
        for path in list_agents():
            with self.subTest(agent=path.stem):
                text = path.read_text()
                fm_match = FRONTMATTER_RE.match(text)
                self.assertIsNotNone(fm_match)
                frontmatter = fm_match.group(1)
                scalars = dict(FRONTMATTER_SCALAR_RE.findall(frontmatter))
                if scalars.get("output") != "pr":
                    continue
                never_has_items = re.search(
                    r"^never-auto-implements:\s*\n\s*-\s+",
                    frontmatter,
                    re.MULTILINE,
                )
                self.assertTrue(
                    never_has_items,
                    f"{path.relative_to(REPO_ROOT)}: output: pr agents must "
                    f"carry at least one never-auto-implements clause "
                    f"explaining why auto-implementation is out of scope.",
                )

    # -------------------- output:pr agents capture PR URL from open-report-pr.sh (#462)

    def test_pr_agents_tick_captures_pr_url(self) -> None:
        """output: pr agents that call open-report-pr.sh must capture the
        returned PR URL so the tick receipt includes a GitHub URL, not a
        local worktree path.

        open-report-pr.sh emits the PR URL as its final stdout line.
        Agents must capture it: PR_URL=$(bash ... open-report-pr.sh ...)
        and include it in the one-line tick receipt.

        See #462 and CLAUDE.md → "The tick convention" (one-line receipt
        format: `Tick: <state> — <PR url>`).
        """
        for path in list_agents():
            with self.subTest(agent=path.stem):
                text = path.read_text()
                fm_match = FRONTMATTER_RE.match(text)
                self.assertIsNotNone(fm_match)
                frontmatter = fm_match.group(1)
                scalars = dict(FRONTMATTER_SCALAR_RE.findall(frontmatter))
                if scalars.get("output") != "pr":
                    continue
                tick_body = extract_tick_body(frontmatter)
                if "open-report-pr.sh" not in tick_body:
                    continue
                has_capture = bool(
                    re.search(r"PR_URL\s*=\s*\$\(", tick_body)
                    or re.search(r"PR_URL\s*=\s*\$\(", text)
                )
                self.assertTrue(
                    has_capture,
                    f"{path.relative_to(REPO_ROOT)}: output: pr agent tick "
                    f"calls open-report-pr.sh but does not capture its stdout "
                    f"into PR_URL. Add: "
                    f"PR_URL=$(bash claude-skills/scripts/open-report-pr.sh ...) "
                    f"so the tick receipt emits a GitHub PR URL, not a local "
                    f"worktree path. See #462.",
                )


if __name__ == "__main__":
    unittest.main(verbosity=2)
