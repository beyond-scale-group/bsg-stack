"""Main entry point for the BSG skills updater — see ``run``."""

from __future__ import annotations

from bsg_updater.config import COOLDOWN_FILE
from bsg_updater.http_client import apply_token
from bsg_updater.log_setup import log, setup_dirs, setup_logging
from bsg_updater.manifest import load_manifest, save_manifest
from bsg_updater.reconcile import reconcile
from bsg_updater.settings import (
    merge_bsg_settings,
    register_session_end_hook,
    register_session_hook,
)


def run() -> int:
    setup_dirs()
    setup_logging()
    apply_token()
    register_session_hook()
    register_session_end_hook()
    merge_bsg_settings()
    manifest = load_manifest()
    manifest = reconcile(manifest)
    save_manifest(manifest)
    COOLDOWN_FILE.touch()
    log("done.")
    return 0
