"""SessionStart hook registration + BSG-managed settings.json merge.

The two writers to ``~/.claude/settings.json`` live here so callers see
one atomic surface for "reconcile my Claude settings against BSG
defaults". Both are idempotent and refuse to touch the file when it is
not a JSON object.
"""

from __future__ import annotations

import json

from bsg_updater.config import (
    API_BASE,
    BRANCH,
    BSG_MANAGED_MCP_SERVERS,
    BSG_MANAGED_SETTINGS_KEYS,
    BSG_RETIRED_MCP_SERVERS,
    SCRIPTS_DIR,
    SCRIPT_NAME,
    SETTINGS_FILE,
)
from bsg_updater.http_client import http_get
from bsg_updater.log_setup import log


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


def _fetch_template_settings() -> dict | None:
    """Download the BSG settings template (claude-skills/settings.json)."""
    meta = http_get(f"{API_BASE}/claude-skills/settings.json?ref={BRANCH}")
    if not isinstance(meta, dict):
        return None
    url = meta.get("download_url")
    if not url:
        return None
    raw = http_get(url, raw=True)
    if raw is None:
        return None
    try:
        data = json.loads(raw.decode("utf-8"))
    except json.JSONDecodeError:
        log("  BSG settings template is not valid JSON")
        return None
    return data if isinstance(data, dict) else None


def merge_bsg_settings() -> None:
    """
    Merge BSG-managed keys from claude-skills/settings.json into
    ~/.claude/settings.json. Only the keys listed in
    BSG_MANAGED_SETTINGS_KEYS and BSG_MANAGED_MCP_SERVERS are touched;
    every other user-owned setting is preserved untouched.

    Idempotent: re-running with no upstream changes is a no-op.
    """
    template = _fetch_template_settings()
    if template is None:
        log("  could not fetch BSG settings template, skipping merge")
        return

    if SETTINGS_FILE.exists():
        try:
            settings = json.loads(SETTINGS_FILE.read_text())
        except json.JSONDecodeError:
            log(f"  {SETTINGS_FILE} is not valid JSON, refusing to merge")
            return
    else:
        settings = {}
    if not isinstance(settings, dict):
        log(f"  {SETTINGS_FILE} is not a JSON object, refusing to merge")
        return

    changed = False

    for key in BSG_MANAGED_SETTINGS_KEYS:
        if key in template and settings.get(key) != template[key]:
            settings[key] = template[key]
            changed = True

    t_servers = template.get("mcpServers")
    if isinstance(t_servers, dict):
        servers = settings.setdefault("mcpServers", {})
        if isinstance(servers, dict):
            for name in BSG_MANAGED_MCP_SERVERS:
                if name in t_servers and servers.get(name) != t_servers[name]:
                    servers[name] = t_servers[name]
                    changed = True
            for name in BSG_RETIRED_MCP_SERVERS:
                if name in servers:
                    del servers[name]
                    changed = True
                    log(f"  removed retired MCP server '{name}'")

    if not changed:
        return

    tmp = SETTINGS_FILE.with_suffix(".json.tmp")
    tmp.write_text(json.dumps(settings, indent=2) + "\n")
    tmp.replace(SETTINGS_FILE)
    log(f"  merged BSG-managed keys into {SETTINGS_FILE}")
