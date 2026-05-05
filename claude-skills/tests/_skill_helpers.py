"""Shared helpers for the claude-skills catalog test modules.

Extracted from test_skills.py during split for #331 (file >500 LOC).
The constants, regexes, and discovery functions are reused by every
test module that asserts something about commands, skills, or agents.

Stdlib only — no third-party dependencies, no network.
"""

from __future__ import annotations

import re
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
    pattern = re.compile(
        rf"^##\s+{re.escape(header)}\s*$(.*?)(?=^##\s|\Z)",
        re.MULTILINE | re.DOTALL,
    )
    match = pattern.search(install_text)
    if not match:
        return set()
    return set(regex.findall(match.group(1)))


def extract_folded_body(frontmatter: str, key: str) -> str:
    """Return the value of a YAML key (inline or folded block)."""
    lines = frontmatter.splitlines()
    body: list[str] = []
    in_block = False
    for line in lines:
        if not in_block:
            m = re.match(rf"^{re.escape(key)}\s*:\s*(.*)$", line)
            if m:
                in_block = True
                inline = m.group(1).strip()
                if inline and inline not in (">", "|", ">-", "|-"):
                    body.append(inline)
            continue
        if re.match(r"^[A-Za-z_][A-Za-z0-9_-]*\s*:", line):
            break
        body.append(line)
    return "\n".join(body)


def extract_tick_body(frontmatter: str) -> str:
    """Return the value of the `tick:` key (inline or folded block)."""
    return extract_folded_body(frontmatter, "tick")
