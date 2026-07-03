"""Orchestrate install + upstream-deletion for each mirrored section."""

from __future__ import annotations

from bsg_updater.config import CLAUDE_DIR, SECTIONS
from bsg_updater.installer import install_file, is_self
from bsg_updater.log_setup import log
from bsg_updater.walker import walk_remote


def reconcile(manifest: dict) -> dict:
    owned = set(manifest.get("files", []))
    new_owned: set = set()
    section_results: dict = {}

    for api_sub, dest, prefix in SECTIONS:
        log(f"fetching {api_sub}...")
        try:
            entries, definitive = walk_remote(
                f"claude-skills/{api_sub}", dest, prefix
            )
        except Exception as e:  # noqa: BLE001
            # Per-section isolation: one broken path must not prevent
            # the remaining sections (agents/, scripts/) from syncing.
            # Log the failure and leave existing files for this section alone.
            log(
                f"  ERROR in {api_sub}: {e} — skipping section, "
                "existing files untouched"
            )
            # Preserve ownership of all files already owned under this prefix
            # so they survive the deletion reconcile below.
            for rel_key in owned:
                if rel_key.split("/", 1)[0] == prefix:
                    new_owned.add(rel_key)
            continue

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
