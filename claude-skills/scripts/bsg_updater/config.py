"""Constants + on-disk paths for the BSG skills updater.

Central config so the other submodules never hard-code paths. Values are
computed from ``CLAUDE_CONFIG_DIR`` (fall-back ``~/.claude``) at import
time — the process must not switch CLAUDE dirs mid-run.
"""

from __future__ import annotations

import os
from pathlib import Path

REPO = "beyond-scale-group/bsg-stack"
BRANCH = "main"
SCRIPT_NAME = "update-bsg-skills.py"
# Opt-in SessionEnd hook that uploads the session transcript to a personal
# gbrain. Registered for everyone (it no-ops without GBRAIN_INGEST_URL +
# GBRAIN_MCP_TOKEN in the environment).
CAPTURE_SCRIPT_NAME = "upload-session-to-gbrain.py"

# Top-level settings keys the BSG updater merges from
# claude-skills/settings.json into ~/.claude/settings.json on every run.
# Keys not listed here are left completely alone, so user-owned settings
# coexist with BSG-managed ones.
BSG_MANAGED_SETTINGS_KEYS = ["autoMemoryEnabled"]
# Sub-keys under `mcpServers` that the updater owns. Other MCP servers the
# user has configured are preserved.
BSG_MANAGED_MCP_SERVERS = ["context7"]
# MCP servers previously managed by BSG that should be removed from user
# settings on the next update run (e.g. stale entries for packages that no
# longer exist).
BSG_RETIRED_MCP_SERVERS = ["claude-in-chrome"]

CLAUDE_DIR = Path(os.environ.get("CLAUDE_CONFIG_DIR", str(Path.home() / ".claude")))
COMMANDS_DIR = CLAUDE_DIR / "commands"
SKILLS_DIR = CLAUDE_DIR / "skills"
AGENTS_DIR = CLAUDE_DIR / "agents"
SCRIPTS_DIR = CLAUDE_DIR / "scripts"
LOGS_DIR = CLAUDE_DIR / "logs"
LOG_FILE = LOGS_DIR / "update-bsg-skills.log"
MANIFEST_FILE = SCRIPTS_DIR / ".bsg-skills-manifest.json"
SETTINGS_FILE = CLAUDE_DIR / "settings.json"
COOLDOWN_FILE = SCRIPTS_DIR / ".bsg-skills-last-run"
COOLDOWN_SECONDS = 3600

API_BASE = f"https://api.github.com/repos/{REPO}/contents"

# Sections of the repo that are mirrored into ~/.claude/. Each tuple is:
#   (api subpath under claude-skills/, local destination, manifest prefix)
SECTIONS = [
    ("commands", COMMANDS_DIR, "commands"),
    ("skills", SKILLS_DIR, "skills"),
    ("agents", AGENTS_DIR, "agents"),
    ("scripts", SCRIPTS_DIR, "scripts"),
]
