"""GitHub Contents API GET helper + auth-token discovery.

The unauthenticated api.github.com limit is 60/hr per IP and easy to
exhaust on a shared-egress machine. Any token bumps it to 5000/hr — env
vars first (explicit > implicit) then a fall-back to the already-
authenticated ``gh`` CLI, so nothing is required from the user when gh
is installed and logged in.
"""

from __future__ import annotations

import json
import os
import shutil
import subprocess
import urllib.error
import urllib.request

from bsg_updater.log_setup import log

API_HEADERS = {
    "Accept": "application/vnd.github+json",
    "X-GitHub-Api-Version": "2022-11-28",
    "User-Agent": "bsg-skills-updater",
}


def _discover_github_token() -> str | None:
    """Return a GitHub token from env vars or ``gh auth token``, else None."""
    for var in ("GH_TOKEN", "GITHUB_TOKEN"):
        token = os.environ.get(var, "").strip()
        if token:
            return token
    if not shutil.which("gh"):
        return None
    try:
        result = subprocess.run(
            ["gh", "auth", "token"],
            capture_output=True,
            text=True,
            timeout=5,
            check=False,
        )
    except (OSError, subprocess.SubprocessError):
        return None
    if result.returncode != 0:
        return None
    token = result.stdout.strip()
    return token or None


def apply_token() -> None:
    """Attach a bearer token to API_HEADERS if one is discoverable.

    Called once at run() start-up. Kept out of module import so tests can
    load the package without triggering a subprocess.
    """
    token = _discover_github_token()
    if token:
        API_HEADERS["Authorization"] = f"Bearer {token}"


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
