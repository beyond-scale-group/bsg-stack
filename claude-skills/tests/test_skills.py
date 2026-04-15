#!/usr/bin/env python3
"""
Unit tests for the BSG claude-skills catalog.

Validates structural invariants that are easy to break by hand when adding
or editing a shared command, skill, or subagent:

  1. every command file, skill SKILL.md, and agent file ends with the
     required "How to improve this skill" footer (so a developer using the
     cached copy in ~/.claude/ knows to PR back here instead of editing
     locally)
  2. that footer references the file's own canonical path (not a
     copy-paste from another asset)
  3. the "Available commands", "Available skills", and "Available agents"
     catalog tables in INSTALL.md are in sync with the actual files in
     claude-skills/{commands,skills,agents}/

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
SKILLS_SUBDIR = SKILLS_DIR / "skills"
AGENTS_DIR = SKILLS_DIR / "agents"
INSTALL_MD = SKILLS_DIR / "INSTALL.md"

FOOTER_HEADER = "## How to improve this skill"

# Frontmatter block at the top of a markdown file, bounded by '---' lines.
FRONTMATTER_RE = re.compile(r"\A---\s*\n(.*?)\n---\s*\n", re.DOTALL)
# Top-level YAML-ish key at column 0 (ignores indented continuation lines of
# folded scalars). Matches `key:` or `key: value`.
TOP_LEVEL_KEY_RE = re.compile(r"^([A-Za-z_][A-Za-z0-9_-]*)\s*:", re.MULTILINE)
# Inline `key: value` match for scalar fields in frontmatter — captures the
# value too, unlike TOP_LEVEL_KEY_RE which only captures the key name.
FRONTMATTER_SCALAR_RE = re.compile(
    r"^([A-Za-z_][A-Za-z0-9_-]*)\s*:\s*(.*?)\s*$", re.MULTILINE
)

# Output modes allowed in an agent's frontmatter `output:` field.
# See CLAUDE.md → "Reporting agents output via auto-merge PRs" for semantics.
ALLOWED_OUTPUT_MODES = {"pr", "commit", "chat"}

# Catches any reference of the form `claude-skills/<...>` inside backticks
# in a footer block, regardless of whether it's a command, skill, or agent.
FOOTER_PATH_RE = re.compile(r"`(claude-skills/[A-Za-z0-9_/.-]+\.md)`")

# Row in the "Available commands" table: `| `/<name>` | ... |`
COMMAND_CATALOG_ROW_RE = re.compile(r"^\|\s*`/([a-z0-9_-]+)`\s*\|", re.MULTILINE)
# Rows in "Available skills" / "Available agents" — same shape: `| `<name>` | ... |`
NAME_CATALOG_ROW_RE = re.compile(r"^\|\s*`([a-z0-9_-]+)`\s*\|", re.MULTILINE)


def list_commands() -> list[Path]:
    return sorted(p for p in COMMANDS_DIR.glob("*.md") if p.is_file())


def list_skill_entrypoints() -> list[Path]:
    """One SKILL.md per skill directory."""
    if not SKILLS_SUBDIR.is_dir():
        return []
    return sorted(
        p / "SKILL.md"
        for p in SKILLS_SUBDIR.iterdir()
        if p.is_dir() and (p / "SKILL.md").is_file()
    )


def list_agents() -> list[Path]:
    if not AGENTS_DIR.is_dir():
        return []
    return sorted(p for p in AGENTS_DIR.glob("*.md") if p.is_file())


def all_footer_bearing_files() -> list[Path]:
    return list_commands() + list_skill_entrypoints() + list_agents()


def canonical_relative_path(path: Path) -> str:
    """The path the footer in this file MUST reference (relative to repo root)."""
    return str(path.relative_to(REPO_ROOT))


def parse_section(install_text: str, header: str, regex: re.Pattern[str]) -> set[str]:
    """Extract names from a single H2 section's first table."""
    # Slice from this header to the next H2 (or EOF), then run the row regex.
    pattern = re.compile(
        rf"^##\s+{re.escape(header)}\s*$(.*?)(?=^##\s|\Z)",
        re.MULTILINE | re.DOTALL,
    )
    match = pattern.search(install_text)
    if not match:
        return set()
    return set(regex.findall(match.group(1)))


class TestSharedSkills(unittest.TestCase):
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
                # Guard against an empty `tick:` line — it must describe the
                # work. Easiest check: the frontmatter must contain at least
                # one non-empty line after the `tick:` key before the next
                # top-level key or end of frontmatter.
                tick_body = self._extract_tick_body(frontmatter)
                self.assertTrue(
                    tick_body.strip(),
                    f"{path.relative_to(REPO_ROOT)}: `tick:` field is empty. "
                    f"Describe what this agent's periodic tick does.",
                )

    @staticmethod
    def _extract_tick_body(frontmatter: str) -> str:
        """Return the value of the `tick:` key (inline or folded block)."""
        # Find the `tick:` line and everything up to the next top-level key.
        lines = frontmatter.splitlines()
        body: list[str] = []
        in_tick = False
        for line in lines:
            if not in_tick:
                m = re.match(r"^tick\s*:\s*(.*)$", line)
                if m:
                    in_tick = True
                    inline = m.group(1).strip()
                    # Strip the YAML folded-scalar indicator if present.
                    if inline and inline not in (">", "|", ">-", "|-"):
                        body.append(inline)
                continue
            # A new top-level key ends the tick block.
            if re.match(r"^[A-Za-z_][A-Za-z0-9_-]*\s*:", line):
                break
            body.append(line)
        return "\n".join(body)

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
