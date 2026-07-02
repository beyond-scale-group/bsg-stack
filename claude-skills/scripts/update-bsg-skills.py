#!/usr/bin/env python3
"""
update-bsg-skills.py

Refreshes the cached BSG shared Claude Code commands and skills from
beyond-scale-group/bsg-stack@main into the user's ~/.claude/.

Designed to be invoked by a Claude Code SessionStart hook so every new
session picks up the latest version automatically. The script also
self-registers that hook in ~/.claude/settings.json on first run, which
means the install flow only has to drop this single file on disk and run
it once — everything else (commands, skills, hook) is managed here.

Conflict avoidance:
  - Maintains a manifest at ~/.claude/scripts/.bsg-skills-manifest.json
    listing every path BSG installed. The updater only overwrites files
    that are in the manifest. Pre-existing files at the same path
    (yours, or another shared-skills system's) are skipped with a
    warning. To adopt a BSG file that you already have, delete your
    local copy and re-run.
  - Files removed upstream are removed locally on the next run, but
    only if they are in the manifest, so unrelated files in the same
    directories are never touched.
  - The settings.json merge is idempotent on two fronts:
      * The SessionStart hook is appended only if no existing entry
        already references this script.
      * BSG-managed keys from claude-skills/settings.json
        (currently: autoMemoryEnabled, mcpServers.context7) are
        overwritten to the upstream value; all other keys in
        ~/.claude/settings.json are left untouched.
    Refuses to touch the file if it is not valid JSON.

Network errors are swallowed (exit 0) so the updater never blocks a
Claude Code session from starting. Logs to
~/.claude/logs/update-bsg-skills.log (rotated at 256 KiB).

Structure (#692): the real logic lives in the ``bsg_updater`` package
next to this file. This entry point stays intentionally tiny — it
handles the cooldown gate, bootstraps the helper package via
raw.githubusercontent.com on first install (when only this single file
is on disk), then delegates to ``bsg_updater.core.run``. Subsequent runs
reuse the on-disk package, which the manifest reconcile keeps refreshed
alongside every other BSG file.

This file is a cached copy of claude-skills/scripts/update-bsg-skills.py
in beyond-scale-group/bsg-stack. The repo is the source of truth;
the local copy is overwritten on every run.
"""

from __future__ import annotations

import os
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

REPO = "beyond-scale-group/bsg-stack"
BRANCH = "main"

CLAUDE_DIR = Path(os.environ.get("CLAUDE_CONFIG_DIR", str(Path.home() / ".claude")))
SCRIPTS_DIR = CLAUDE_DIR / "scripts"
COOLDOWN_FILE = SCRIPTS_DIR / ".bsg-skills-last-run"
COOLDOWN_SECONDS = 3600

# Early exit before any network I/O if we ran recently.
if COOLDOWN_FILE.exists():
    if time.time() - COOLDOWN_FILE.stat().st_mtime < COOLDOWN_SECONDS:
        sys.exit(0)

# ---------- helper package bootstrap ----------
#
# First-run scenario: the install flow (INSTALL.md) drops only this
# single file on disk. The bsg_updater/ package does not exist yet, so
# we fetch it once from raw.githubusercontent.com (unauth, generous
# rate limit — no token needed for public content) before importing.
# On subsequent runs the files already exist and this loop is a no-op;
# reconcile keeps them in sync via the manifest.

_PKG_DIR = SCRIPTS_DIR / "bsg_updater"
_PKG_MODULES = (
    "__init__.py",
    "config.py",
    "log_setup.py",
    "http_client.py",
    "manifest.py",
    "installer.py",
    "walker.py",
    "reconcile.py",
    "settings.py",
    "core.py",
)
_RAW_BASE = (
    f"https://raw.githubusercontent.com/{REPO}/{BRANCH}/claude-skills/scripts/bsg_updater"
)


def _bootstrap_helpers() -> bool:
    """Fetch any missing bsg_updater/*.py so ``import bsg_updater`` works.

    Returns True on success. Any network failure is non-fatal to the
    parent script — the outermost handler still exits 0 so a flaky
    connection never blocks a Claude Code session from starting.
    """
    _PKG_DIR.mkdir(parents=True, exist_ok=True)
    for mod in _PKG_MODULES:
        target = _PKG_DIR / mod
        if target.exists() and target.stat().st_size > 0:
            continue
        url = f"{_RAW_BASE}/{mod}"
        try:
            req = urllib.request.Request(
                url, headers={"User-Agent": "bsg-skills-updater"}
            )
            with urllib.request.urlopen(req, timeout=15) as resp:
                data = resp.read()
        except (urllib.error.URLError, TimeoutError, OSError) as e:
            print(f"bsg-skills-updater: bootstrap failed for {mod}: {e}", file=sys.stderr)
            return False
        tmp = target.with_suffix(target.suffix + ".tmp")
        tmp.write_bytes(data)
        tmp.replace(target)
    return True


def main() -> int:
    SCRIPTS_DIR.mkdir(parents=True, exist_ok=True)
    if not _bootstrap_helpers():
        return 0
    if str(SCRIPTS_DIR) not in sys.path:
        sys.path.insert(0, str(SCRIPTS_DIR))
    from bsg_updater.core import run
    return run()


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as e:  # never let an exception block a session
        try:
            print(f"bsg-skills-updater: unexpected error: {e}", file=sys.stderr)
        except Exception:
            pass
        sys.exit(0)
