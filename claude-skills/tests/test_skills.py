#!/usr/bin/env python3
"""Aggregator for the BSG claude-skills catalog test suite.

Historical entry point used by CI (`python3 claude-skills/tests/test_skills.py`).
Splits for #331 — the suite is organized as:

  - test_skill_invariants.py   — file-level invariants (footer + catalog sync)
  - test_agent_frontmatter.py  — per-agent frontmatter rules
  - _skill_helpers.py          — shared discovery + parsing helpers

This shim imports the test classes so unittest.main() discovers them when
the file is run directly. New tests should go in the topic module that
matches their concern, not here.

Run locally:

    python3 claude-skills/tests/test_skills.py
"""

from __future__ import annotations

import os
import sys
import unittest

# When run as `python3 claude-skills/tests/test_skills.py`, the script's
# directory is on sys.path automatically. When invoked via `python3 -m
# unittest …` from the repo root, it isn't. Add it explicitly so the
# `_skill_helpers` and sibling test modules import either way.
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from test_agent_frontmatter import TestAgentFrontmatter  # noqa: E402,F401
from test_skill_invariants import TestSkillInvariants  # noqa: E402,F401


if __name__ == "__main__":
    unittest.main(verbosity=2)
