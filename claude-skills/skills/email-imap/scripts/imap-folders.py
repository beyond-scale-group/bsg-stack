#!/usr/bin/env python3
"""
imap-folders.py — list every IMAP folder on the server, with message counts.

Auth via env vars (same as imap-fetch.py):
    IMAP_USER, IMAP_APP_PASSWORD, IMAP_HOST (optional), IMAP_PORT (optional)

Usage:
    python3 imap-folders.py                 # table view (default)
    python3 imap-folders.py --format json   # machine-readable
    python3 imap-folders.py --no-counts     # skip the EXAMINE for each folder
                                            # (much faster on large accounts)

Pure stdlib.
"""

import argparse
import imaplib
import json
import os
import re
import sys

DEFAULT_PORT = 993


def load_env_file(explicit_path=None):
    """KEY=VALUE loader — see imap-fetch.py for the full docstring.
    Search order: --env-file → $IMAP_ENV_FILE → ~/.config/email-imap/credentials.env → ./.env
    Never overrides variables already in os.environ.
    """
    candidates = []
    if explicit_path:
        candidates.append(explicit_path)
    if os.environ.get("IMAP_ENV_FILE"):
        candidates.append(os.environ["IMAP_ENV_FILE"])
    candidates.append(os.path.expanduser("~/.config/email-imap/credentials.env"))
    candidates.append(".env")
    for path in candidates:
        if not path or not os.path.isfile(path):
            continue
        with open(path, "r", encoding="utf-8") as fp:
            for raw_line in fp:
                line = raw_line.strip()
                if not line or line.startswith("#") or "=" not in line:
                    continue
                key, value = line.split("=", 1)
                key = key.strip()
                value = value.strip()
                if len(value) >= 2 and value[0] == value[-1] and value[0] in ('"', "'"):
                    value = value[1:-1]
                if key and key not in os.environ:
                    os.environ[key] = value
        return path
    return None


HOST_BY_DOMAIN = {
    "gmail.com": "imap.gmail.com",
    "googlemail.com": "imap.gmail.com",
    "outlook.com": "outlook.office365.com",
    "hotmail.com": "outlook.office365.com",
    "live.com": "outlook.office365.com",
    "office365.com": "outlook.office365.com",
    "icloud.com": "imap.mail.me.com",
    "me.com": "imap.mail.me.com",
    "mac.com": "imap.mail.me.com",
    "yahoo.com": "imap.mail.yahoo.com",
    "fastmail.com": "imap.fastmail.com",
}

# IMAP LIST response: ( flags ) "delimiter" "name"
LIST_RE = re.compile(rb'\((?P<flags>[^)]*)\)\s+"(?P<delim>[^"]*)"\s+(?P<name>.+)$')


def parse_list_line(raw):
    m = LIST_RE.match(raw)
    if not m:
        return None
    flags = m.group("flags").decode("utf-8", errors="replace").split()
    name = m.group("name").decode("utf-8", errors="replace").strip()
    # Names may be quoted or as literal {N} — strip outer quotes if present
    if name.startswith('"') and name.endswith('"'):
        name = name[1:-1]
    return {"flags": flags, "name": name}


def detect_host(user):
    domain = user.split("@", 1)[1].lower() if "@" in user else ""
    return HOST_BY_DOMAIN.get(domain)


def folder_count(M, name):
    typ, data = M.select(f'"{name}"', readonly=True)
    if typ != "OK" or not data or not data[0]:
        return None
    try:
        return int(data[0])
    except (ValueError, TypeError):
        return None


def folder_recent(M):
    typ, data = M.search(None, "RECENT")
    if typ != "OK" or not data or not data[0]:
        return 0
    return len(data[0].split())


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--format", choices=["table", "json"], default="table")
    ap.add_argument("--no-counts", action="store_true",
                    help="skip message counts (faster)")
    ap.add_argument("--env-file", default=None,
                    help="credentials.env explicite")
    args = ap.parse_args()

    loaded = load_env_file(args.env_file)
    if loaded:
        print(f"🔐 .env chargé : {loaded}", file=sys.stderr)

    user = os.environ.get("IMAP_USER", "").strip()
    pwd = os.environ.get("IMAP_APP_PASSWORD", "").replace(" ", "")
    if not user or not pwd:
        sys.exit("❌ IMAP_USER et IMAP_APP_PASSWORD doivent être définis")

    host = os.environ.get("IMAP_HOST") or detect_host(user)
    if not host:
        sys.exit(f"❌ pas d'IMAP host par défaut pour '{user}', définis IMAP_HOST")
    port = int(os.environ.get("IMAP_PORT", DEFAULT_PORT))

    M = imaplib.IMAP4_SSL(host, port)
    try:
        M.login(user, pwd)
    except imaplib.IMAP4.error as e:
        sys.exit(f"❌ login IMAP refusé : {e}")

    try:
        typ, raw_lines = M.list()
        if typ != "OK":
            sys.exit("❌ LIST a échoué")

        folders = []
        for line in raw_lines:
            if not line:
                continue
            entry = parse_list_line(line)
            if not entry:
                continue
            # Skip \Noselect folders (Gmail's [Gmail] root, etc.)
            if "\\Noselect" in entry["flags"]:
                continue
            folders.append(entry)

        if not args.no_counts:
            for f in folders:
                f["messages"] = folder_count(M, f["name"])
                f["recent"] = folder_recent(M) if f.get("messages") else 0

        if args.format == "json":
            print(json.dumps(folders, indent=2, ensure_ascii=False))
        else:
            if args.no_counts:
                print(f"{'FOLDER':<50} FLAGS")
                print("-" * 70)
                for f in folders:
                    print(f"{f['name']:<50} {' '.join(f['flags'])}")
            else:
                print(f"{'FOLDER':<50} {'MESSAGES':>10} {'RECENT':>8}")
                print("-" * 72)
                for f in folders:
                    msgs = f.get("messages")
                    rec = f.get("recent", 0)
                    msgs_s = str(msgs) if msgs is not None else "?"
                    print(f"{f['name']:<50} {msgs_s:>10} {rec:>8}")
    finally:
        try:
            M.logout()
        except Exception:
            pass


if __name__ == "__main__":
    main()
