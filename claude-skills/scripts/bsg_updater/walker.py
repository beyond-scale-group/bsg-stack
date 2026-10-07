"""Recursive walk over the GitHub Contents API."""

from __future__ import annotations

from pathlib import Path

from bsg_updater.config import API_BASE, BRANCH
from bsg_updater.http_client import http_get


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
