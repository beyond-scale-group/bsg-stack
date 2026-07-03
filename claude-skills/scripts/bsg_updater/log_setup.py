"""Log-file rotation + stdout/stderr redirection."""

from __future__ import annotations

import sys
import time

from bsg_updater.config import (
    AGENTS_DIR,
    COMMANDS_DIR,
    LOG_FILE,
    LOGS_DIR,
    SCRIPTS_DIR,
    SCRIPT_NAME,
    SKILLS_DIR,
)


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
