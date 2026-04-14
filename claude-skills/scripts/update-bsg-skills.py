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
  - The settings.json merge is idempotent: it appends a SessionStart
    entry only if no existing entry already references this script. It
    refuses to touch the file if it is not valid JSON.

Network errors are swallowed (exit 0) so the updater never blocks a
Claude Code session from starting. Logs to
~/.claude/logs/update-bsg-skills.log (rotated at 256 KiB).

This file is a cached copy of claude-skills/scripts/update-bsg-skills.py
in beyond-scale-group/bsg-stack. The repo is the source of truth;
the local copy is overwritten on every run.
"""

from __future__ import annotations

import json
import os
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

REPO = "beyond-scale-group/bsg-stack"
BRANCH = "main"
SCRIPT_NAME = "update-bsg-skills.py"

CLAUDE_DIR = Path(os.environ.get("CLAUDE_CONFIG_DIR", str(Path.home() / ".claude")))
COMMANDS_DIR = CLAUDE_DIR / "commands"
SKILLS_DIR = CLAUDE_DIR / "skills"
AGENTS_DIR = CLAUDE_DIR / "agents"
SCRIPTS_DIR = CLAUDE_DIR / "scripts"
LOGS_DIR = CLAUDE_DIR / "logs"
LOG_FILE = LOGS_DIR / "update-bsg-skills.log"
MANIFEST_FILE = SCRIPTS_DIR / ".bsg-skills-manifest.json"
SETTINGS_FILE = CLAUDE_DIR / "settings.json"

API_BASE = f"https://api.github.com/repos/{REPO}/contents"
API_HEADERS = {
    "Accept": "application/vnd.github+json",
    "X-GitHub-Api-Version": "2022-11-28",
    "User-Agent": "bsg-skills-updater",
}

# Sections of the repo that are mirrored into ~/.claude/. Each tuple is:
#   (api subpath under claude-skills/, local destination, manifest prefix)
SECTIONS = [
    ("commands", COMMANDS_DIR, "commands"),
    ("skills", SKILLS_DIR, "skills"),
    ("agents", AGENTS_DIR, "agents"),
    ("scripts", SCRIPTS_DIR, "scripts"),
]


def log(msg: str) -> None:
    print(msg, flush=True)


def setup_dirs() -> None:
    for d in (COMMANDS_DIR, SKILLS_DIR, AGENTS_DIR, SCRIPTS_DIR, LOGS_DIR):
        d.mkdir(parents=True, exist_ok=True)


def setup_logging() -> None:
    if LOG_FILE.exists() and LOG_FILE.stat().st_size > 262144:
        LOG_FILE.replace(LOG_FILE.with_suffix(".log.1"))
    fp = open(LOG_FILE, "a")
    sys.stdout = fp
    sys.stderr = fp
    log(f"--- {time.strftime('%Y-%m-%d %H:%M:%S')} {SCRIPT_NAME} ---")


def http_get(url: str, raw: bool = False, timeout: int = 15):
    req = urllib.request.Request(url, headers=API_HEADERS)
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            data = resp.read()
        return data if raw else json.loads(data.decode("utf-8"))
    except urllib.error.HTTPError as e:
        if e.code == 404:
            return None
        log(f"  HTTP {e.code} on {url}")
        return None
    except (urllib.error.URLError, TimeoutError, OSError, json.JSONDecodeError) as e:
        log(f"  network error on {url}: {e}")
        return None


# ---------- manifest ----------

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


# ---------- file install ----------

def is_self(rel_key: str) -> bool:
    return rel_key == f"scripts/{SCRIPT_NAME}"


def install_file(url: str, dest: Path, owned: set, rel_key: str) -> bool:
    """
    Download `url` to `dest`. Refuses to overwrite files that are not in
    the manifest, with one exception: this script is always allowed to
    overwrite itself (otherwise the very first run after install would
    refuse to claim the file the install flow just dropped on disk).
    """
    if dest.exists() and rel_key not in owned and not is_self(rel_key):
        log(f"  SKIP {dest} (exists, not owned by BSG manifest)")
        return False
    data = http_get(url, raw=True)
    if data is None:
        log(f"  FAILED {url}")
        return False
    dest.parent.mkdir(parents=True, exist_ok=True)
    tmp = dest.with_suffix(dest.suffix + ".tmp")
    tmp.write_bytes(data)
    if dest.suffix in (".sh", ".py"):
        os.chmod(tmp, 0o755)
    tmp.replace(dest)
    log(f"  updated {dest}")
    return True


# ---------- remote walk ----------

def list_dir(api_path: str):
    """List a contents-API directory; returns list (or None on error/404)."""
    data = http_get(f"{API_BASE}/{api_path}?ref={BRANCH}")
    if data is None:
        return None
    if not isinstance(data, list):
        return None
    return data


def walk_remote(api_path: str, dest_dir: Path, rel_prefix: str):
    """
    Walk a remote directory recursively. Returns (entries, definitive)
    where entries is a list of (rel_key, dest_path, download_url) and
    definitive is True iff every directory in the walk listed
    successfully (so the caller can safely reconcile deletions).
    """
    listing = list_dir(api_path)
    if listing is None:
        return [], False
    out = []
    definitive = True
    for entry in listing:
        name = entry.get("name", "")
        etype = entry.get("type")
        if etype == "file":
            rel_key = f"{rel_prefix}/{name}" if rel_prefix else name
            url = entry.get("download_url")
            if url:
                out.append((rel_key, dest_dir / name, url))
        elif etype == "dir":
            sub_rel = f"{rel_prefix}/{name}" if rel_prefix else name
            sub_entries, sub_def = walk_remote(
                f"{api_path}/{name}", dest_dir / name, sub_rel
            )
            out.extend(sub_entries)
            definitive = definitive and sub_def
    return out, definitive


# ---------- reconcile ----------

def reconcile(manifest: dict) -> dict:
    owned = set(manifest.get("files", []))
    new_owned: set = set()
    section_results: dict = {}

    for api_sub, dest, prefix in SECTIONS:
        log(f"fetching {api_sub}...")
        entries, definitive = walk_remote(
            f"claude-skills/{api_sub}", dest, prefix
        )
        if not entries and not definitive:
            log("  unreachable, leaving existing files alone")
        section_results[prefix] = (entries, definitive)
        for rel_key, dest_path, url in entries:
            if install_file(url, dest_path, owned, rel_key):
                new_owned.add(rel_key)
            elif rel_key in owned:
                # Transient failure on a file we already own — keep
                # ownership so we don't drop it from the manifest.
                new_owned.add(rel_key)

    # Reconcile deletions: only act when we got a definitive listing.
    for rel_key in owned:
        prefix = rel_key.split("/", 1)[0]
        results = section_results.get(prefix)
        if not results or not results[1]:
            new_owned.add(rel_key)
            continue
        upstream_keys = {k for k, _, _ in results[0]}
        if rel_key in upstream_keys:
            continue  # still upstream, already handled above
        if is_self(rel_key):
            # Don't delete the running script even if it disappears
            # upstream — leaves a clean recovery path.
            new_owned.add(rel_key)
            continue
        local = CLAUDE_DIR / rel_key
        try:
            if local.exists():
                local.unlink()
                log(f"  removed {local} (no longer upstream)")
        except OSError as e:
            log(f"  failed to remove {local}: {e}")
            new_owned.add(rel_key)

    manifest["files"] = sorted(new_owned)
    return manifest


# ---------- session hook self-registration ----------

def register_session_hook() -> None:
    script_path = SCRIPTS_DIR / SCRIPT_NAME
    command = f"{script_path} &"

    if SETTINGS_FILE.exists():
        try:
            settings = json.loads(SETTINGS_FILE.read_text())
        except json.JSONDecodeError:
            log(f"  {SETTINGS_FILE} is not valid JSON, refusing to modify")
            return
    else:
        settings = {}

    if not isinstance(settings, dict):
        log(f"  {SETTINGS_FILE} is not a JSON object, refusing to modify")
        return

    hooks = settings.setdefault("hooks", {})
    if not isinstance(hooks, dict):
        log("  settings.hooks is not an object, refusing to modify")
        return
    session_start = hooks.setdefault("SessionStart", [])
    if not isinstance(session_start, list):
        log("  settings.hooks.SessionStart is not a list, refusing to modify")
        return

    for entry in session_start:
        if not isinstance(entry, dict):
            continue
        for h in entry.get("hooks", []) or []:
            if isinstance(h, dict) and SCRIPT_NAME in str(h.get("command", "")):
                return  # already registered, nothing to do

    session_start.append(
        {
            "matcher": "startup|resume|clear",
            "hooks": [{"type": "command", "command": command}],
        }
    )
    tmp = SETTINGS_FILE.with_suffix(".json.tmp")
    tmp.write_text(json.dumps(settings, indent=2) + "\n")
    tmp.replace(SETTINGS_FILE)
    log(f"  registered SessionStart hook in {SETTINGS_FILE}")


# ---------- entry point ----------

def main() -> int:
    setup_dirs()
    setup_logging()
    register_session_hook()
    manifest = load_manifest()
    manifest = reconcile(manifest)
    save_manifest(manifest)
    log("done.")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as e:  # never let an exception block a session
        try:
            log(f"unexpected error: {e}")
        except Exception:
            pass
        sys.exit(0)
