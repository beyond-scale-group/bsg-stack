#!/usr/bin/env python3
"""File-level invariants for the BSG claude-skills catalog.

Validates rules that apply uniformly to every command file, skill
SKILL.md, and agent file:

  1. every shared asset ends with the required "How to improve this
     skill" footer (so a developer using the cached copy in ~/.claude/
     knows to PR back here instead of editing locally)
  2. that footer references the file's own canonical path (not a
     copy-paste from another asset)
  3. the "Available commands", "Available skills", and "Available
     agents" catalog tables in INSTALL.md are in sync with the actual
     files in claude-skills/{commands,skills,agents}/

Per-agent frontmatter rules live in test_agent_frontmatter.py.

Run locally:

    python3 claude-skills/tests/test_skill_invariants.py
"""

from __future__ import annotations

import unittest

from _skill_helpers import (
    COMMAND_CATALOG_ROW_RE,
    FOOTER_HEADER,
    FOOTER_PATH_RE,
    INSTALL_MD,
    NAME_CATALOG_ROW_RE,
    REPO_ROOT,
    all_footer_bearing_files,
    canonical_relative_path,
    list_agents,
    list_commands,
    list_skill_entrypoints,
    parse_section,
)


class TestSkillInvariants(unittest.TestCase):
    # ------------------------------------------------------------------ footers

    def test_every_asset_has_footer(self) -> None:
        files = all_footer_bearing_files()
        self.assertGreater(len(files), 0, "no shared assets discovered at all")
        for path in files:
            with self.subTest(path=str(path.relative_to(REPO_ROOT))):
                text = path.read_text()
                self.assertIn(
                    FOOTER_HEADER,
                    text,
                    f"{path.relative_to(REPO_ROOT)} is missing the required "
                    f"'{FOOTER_HEADER}' footer. See claude-skills/INSTALL.md "
                    f"for the template.",
                )

    def test_footer_references_own_canonical_path(self) -> None:
        for path in all_footer_bearing_files():
            with self.subTest(path=str(path.relative_to(REPO_ROOT))):
                text = path.read_text()
                idx = text.find(FOOTER_HEADER)
                if idx < 0:
                    self.skipTest("no footer (covered by another test)")
                footer = text[idx:]
                referenced = set(FOOTER_PATH_RE.findall(footer))
                expected = canonical_relative_path(path)
                self.assertIn(
                    expected,
                    referenced,
                    f"footer in {expected} does not reference its own "
                    f"canonical path `{expected}`. Found references to: "
                    f"{sorted(referenced) or 'nothing'}. This usually means "
                    f"the footer was copy-pasted from another asset — fix "
                    f"the path in the footer.",
                )

    # ----------------------------------------------------------- catalog sync

    def test_install_md_commands_catalog_in_sync(self) -> None:
        install_text = INSTALL_MD.read_text()
        catalog_names = parse_section(
            install_text, "Available commands", COMMAND_CATALOG_ROW_RE
        )
        actual_names = {p.stem for p in list_commands()}
        self._assert_sets_match(catalog_names, actual_names, "Available commands")

    def test_install_md_skills_catalog_in_sync(self) -> None:
        install_text = INSTALL_MD.read_text()
        catalog_names = parse_section(
            install_text, "Available skills", NAME_CATALOG_ROW_RE
        )
        actual_names = {p.parent.name for p in list_skill_entrypoints()}
        self._assert_sets_match(catalog_names, actual_names, "Available skills")

    def test_install_md_agents_catalog_in_sync(self) -> None:
        install_text = INSTALL_MD.read_text()
        catalog_names = parse_section(
            install_text, "Available agents", NAME_CATALOG_ROW_RE
        )
        actual_names = {p.stem for p in list_agents()}
        self._assert_sets_match(catalog_names, actual_names, "Available agents")

    # ------------------------------------------------------------------ helpers

    def _assert_sets_match(
        self, catalog: set[str], actual: set[str], section: str
    ) -> None:
        missing = sorted(actual - catalog)
        orphans = sorted(catalog - actual)
        self.assertSetEqual(
            catalog,
            actual,
            f"INSTALL.md '{section}' table is out of sync with the "
            f"corresponding directory under claude-skills/.\n"
            f"  Missing rows (file exists but no catalog entry): {missing}\n"
            f"  Orphan rows (catalog entry but no file): {orphans}\n"
            f"Update the table in claude-skills/INSTALL.md.",
        )


if __name__ == "__main__":
    unittest.main(verbosity=2)
