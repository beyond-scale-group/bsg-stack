#!/usr/bin/env python3
"""
Unit tests for the BSG claude-skills catalog.

Validates structural invariants that are easy to break by hand when adding
or editing a shared skill:

  1. every command file ends with the required "How to improve this skill"
     footer (so a developer using the cached copy in ~/.claude/ knows to PR
     back here instead of editing locally)
  2. that footer references the file's own filename (not a copy-paste from
     another skill)
  3. the "Available commands" catalog table in INSTALL.md is in sync with
     the actual files in claude-skills/commands/

Run locally:

    python3 claude-skills/tests/test_skills.py

Stdlib only — no third-party dependencies, no network.
"""

from __future__ import annotations

import re
import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
SKILLS_DIR = REPO_ROOT / "claude-skills"
COMMANDS_DIR = SKILLS_DIR / "commands"
INSTALL_MD = SKILLS_DIR / "INSTALL.md"

FOOTER_HEADER = "## How to improve this skill"
# matches `claude-skills/commands/<name>.md` inside backticks
FOOTER_PATH_RE = re.compile(r"`claude-skills/commands/([a-z0-9_-]+\.md)`")
# matches a row in the "Available commands" table: `| `/<name>` | ... |`
CATALOG_ROW_RE = re.compile(r"^\|\s*`/([a-z0-9_-]+)`\s*\|", re.MULTILINE)


def list_commands() -> list[Path]:
    return sorted(p for p in COMMANDS_DIR.glob("*.md") if p.is_file())


class TestSharedSkills(unittest.TestCase):
    def test_every_command_has_footer(self) -> None:
        for path in list_commands():
            with self.subTest(path=path.name):
                text = path.read_text()
                self.assertIn(
                    FOOTER_HEADER,
                    text,
                    f"{path.relative_to(REPO_ROOT)} is missing the required "
                    f"'{FOOTER_HEADER}' footer. See claude-skills/INSTALL.md "
                    f"for the template.",
                )

    def test_footer_references_own_filename(self) -> None:
        for path in list_commands():
            with self.subTest(path=path.name):
                text = path.read_text()
                idx = text.find(FOOTER_HEADER)
                if idx < 0:
                    self.skipTest("no footer (covered by another test)")
                footer = text[idx:]
                referenced = set(FOOTER_PATH_RE.findall(footer))
                self.assertIn(
                    path.name,
                    referenced,
                    f"footer in {path.relative_to(REPO_ROOT)} does not "
                    f"reference its own filename "
                    f"`claude-skills/commands/{path.name}`. Found references "
                    f"to: {sorted(referenced) or 'nothing'}. This usually "
                    f"means the footer was copy-pasted from another skill — "
                    f"fix the file name in the footer.",
                )

    def test_install_md_catalog_in_sync(self) -> None:
        install_text = INSTALL_MD.read_text()
        catalog_names = set(CATALOG_ROW_RE.findall(install_text))
        actual_names = {p.stem for p in list_commands()}

        missing = sorted(actual_names - catalog_names)
        orphans = sorted(catalog_names - actual_names)
        self.assertSetEqual(
            catalog_names,
            actual_names,
            f"INSTALL.md 'Available commands' table is out of sync with "
            f"claude-skills/commands/.\n"
            f"  Missing rows (file exists but no catalog entry): {missing}\n"
            f"  Orphan rows (catalog entry but no file): {orphans}\n"
            f"Update the table in claude-skills/INSTALL.md.",
        )


if __name__ == "__main__":
    unittest.main(verbosity=2)
