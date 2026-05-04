#!/usr/bin/env python3
"""
test(#104): /learn skill short-circuit dedup — failing test first.

Acceptance criteria from issue #104:
- The learn skill SKILL.md must exist in claude-skills/skills/learn/SKILL.md
- It must document a short-circuit branch for the "no new signal" case
- The short-circuit receipt must cite prior ticket(s) covering the same findings
- INSTALL.md Available skills table must list `learn`
"""

from __future__ import annotations

import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
SKILL_PATH = REPO_ROOT / "claude-skills" / "skills" / "learn" / "SKILL.md"
INSTALL_MD = REPO_ROOT / "claude-skills" / "INSTALL.md"


class TestLearnSkillDedup(unittest.TestCase):
    def test_learn_skill_file_exists(self) -> None:
        """claude-skills/skills/learn/SKILL.md must exist in the catalog."""
        self.assertTrue(
            SKILL_PATH.exists(),
            f"{SKILL_PATH} does not exist. The /learn skill must be added to "
            f"the bsg-stack catalog at claude-skills/skills/learn/SKILL.md.",
        )

    def test_learn_skill_documents_short_circuit(self) -> None:
        """SKILL.md must document the no-new-signal short-circuit path (#104).

        The skill must describe the dedup / overlap check that produces a
        one-line skip receipt instead of a full proposal list when ≥ 80 % of
        findings overlap with open issues filed in the last ~2 hours.
        """
        if not SKILL_PATH.exists():
            self.skipTest("learn/SKILL.md missing (covered by test_learn_skill_file_exists)")
        text = SKILL_PATH.read_text()
        self.assertIn(
            "no new signal",
            text,
            "SKILL.md must document the 'no new signal' short-circuit receipt string.",
        )

    def test_learn_skill_documents_overlap_threshold(self) -> None:
        """SKILL.md must document the ≥ 80 % overlap threshold for short-circuit."""
        if not SKILL_PATH.exists():
            self.skipTest("learn/SKILL.md missing (covered by test_learn_skill_file_exists)")
        text = SKILL_PATH.read_text()
        self.assertIn(
            "80",
            text,
            "SKILL.md must document the 80 % overlap threshold for the dedup check.",
        )

    def test_learn_skill_listed_in_install_md(self) -> None:
        """INSTALL.md Available skills table must list `learn`."""
        install_text = INSTALL_MD.read_text()
        self.assertIn(
            "`learn`",
            install_text,
            "INSTALL.md Available skills table must include a row for `learn`.",
        )

    def test_learn_skill_has_footer(self) -> None:
        """SKILL.md must carry the required 'How to improve this skill' footer."""
        if not SKILL_PATH.exists():
            self.skipTest("learn/SKILL.md missing (covered by test_learn_skill_file_exists)")
        text = SKILL_PATH.read_text()
        self.assertIn(
            "## How to improve this skill",
            text,
            "SKILL.md is missing the required '## How to improve this skill' footer.",
        )

    def test_learn_skill_footer_references_own_path(self) -> None:
        """Footer must reference claude-skills/skills/learn/SKILL.md (not a copy-paste)."""
        if not SKILL_PATH.exists():
            self.skipTest("learn/SKILL.md missing (covered by test_learn_skill_file_exists)")
        text = SKILL_PATH.read_text()
        idx = text.find("## How to improve this skill")
        if idx < 0:
            self.skipTest("no footer (covered by test_learn_skill_has_footer)")
        footer = text[idx:]
        self.assertIn(
            "claude-skills/skills/learn/SKILL.md",
            footer,
            "Footer must reference its own canonical path "
            "`claude-skills/skills/learn/SKILL.md`.",
        )


if __name__ == "__main__":
    unittest.main()
