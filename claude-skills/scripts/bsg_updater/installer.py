"""Write a fetched blob to disk, honoring manifest ownership."""

from __future__ import annotations

import os
from pathlib import Path

from bsg_updater.config import SCRIPT_NAME
from bsg_updater.http_client import http_get
from bsg_updater.log_setup import log


def is_self(rel_key: str) -> bool:
    return rel_key == f"scripts/{SCRIPT_NAME}"


def install_file(url: str, dest: Path, owned: set, rel_key: str) -> bool:
    """
    Download ``url`` to ``dest``. Refuses to overwrite files that are not
    in the manifest, with one exception: this script is always allowed to
    overwrite itself (otherwise the very first run after install would
    refuse to claim the file the install flow just dropped on disk).

    Dangling symlinks (broken symlinks where the target doesn't exist) are
    treated as writable destinations — they are removed before writing so
    that mkdir/replace don't raise FileExistsError (issue #67).

    Content-identity check (issue #313): after downloading, if the local
    file already exists and its bytes are identical to what was fetched,
    log "unchanged" and skip the write. This prevents false-positive
    "updated" messages when the GitHub/CDN layer serves a cached response
    with old bytes for a file that has not actually changed on disk.
    """
    # A dangling symlink: is_symlink() is True but exists() is False.
    # Remove it so the path is clear for writing.
    if dest.is_symlink() and not dest.exists():
        try:
            dest.unlink()
            log(f"  removed dangling symlink {dest}")
        except OSError as e:
            log(f"  SKIP {dest} (dangling symlink, could not remove: {e})")
            return False

    if dest.exists() and rel_key not in owned and not is_self(rel_key):
        log(f"  SKIP {dest} (exists, not owned by BSG manifest)")
        return False
    data = http_get(url, raw=True)
    if data is None:
        log(f"  FAILED {url}")
        return False
    # Issue #313: compare fetched bytes against the existing local file.
    # If they are identical the file is already up-to-date — log "unchanged"
    # and skip the write so the operator can distinguish a genuine cache
    # refresh from a CDN-cached no-op.
    if dest.exists() and not dest.is_symlink():
        try:
            if dest.read_bytes() == data:
                log(f"  unchanged {dest}")
                return True
        except OSError:
            pass  # unreadable existing file — proceed with write
    dest.parent.mkdir(parents=True, exist_ok=True)
    tmp = dest.with_suffix(dest.suffix + ".tmp")
    tmp.write_bytes(data)
    if dest.suffix in (".sh", ".py"):
        os.chmod(tmp, 0o755)
    tmp.replace(dest)
    log(f"  updated {dest}")
    return True
