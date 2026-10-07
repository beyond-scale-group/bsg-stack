"""Load/save the BSG skills manifest.

The manifest at ``~/.claude/scripts/.bsg-skills-manifest.json`` is the
source of truth for which files under ``~/.claude/`` are BSG-owned.
Anything not listed is treated as user-owned and never overwritten.
"""

from __future__ import annotations

import json

from bsg_updater.config import MANIFEST_FILE
from bsg_updater.log_setup import log


def load_manifest() -> dict:
    if not MANIFEST_FILE.exists():
        return {"version": 1, "files": []}
    try:
        data = json.loads(MANIFEST_FILE.read_text())
    except json.JSONDecodeError:
        log("  manifest is corrupt, starting fresh")
        return {"version": 1, "files": []}
    if not isinstance(data, dict) or not isinstance(data.get("files"), list):
        return {"version": 1, "files": []}
    return data


def save_manifest(manifest: dict) -> None:
    tmp = MANIFEST_FILE.with_suffix(".json.tmp")
    tmp.write_text(json.dumps(manifest, indent=2) + "\n")
    tmp.replace(MANIFEST_FILE)
