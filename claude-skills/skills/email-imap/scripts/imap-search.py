#!/usr/bin/env python3
"""
imap-search.py — run an IMAP-query search on a folder, print matching headers.
No body download — fast probe before deciding what to fetch.

Auth via env vars (same as imap-fetch.py):
    IMAP_USER, IMAP_APP_PASSWORD, IMAP_HOST (optional), IMAP_PORT (optional)

Usage:
    python3 imap-search.py --folder INBOX --query 'UNSEEN'
    python3 imap-search.py --query 'FROM "client@x.com" SINCE 01-Jun-2026'
    python3 imap-search.py --query 'SUBJECT "réservation"' --format json
    python3 imap-search.py --folder '[Gmail]/Sent Mail' --query 'SINCE 01-May-2026'

IMAP search syntax (most useful operators):
    SINCE dd-Mon-yyyy       BEFORE dd-Mon-yyyy
    FROM "addr"             TO "addr"           CC "addr"
    SUBJECT "text"          BODY "text"         TEXT "text"
    UNSEEN | SEEN           ANSWERED | UNANSWERED
    FLAGGED | UNFLAGGED     LARGER N | SMALLER N
    Combine in parens: (FROM "x" SINCE 01-Jun-2026 UNSEEN)

Pure stdlib.
"""

import argparse
import email
import imaplib
import json
import os
import sys
from email.header import decode_header

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


def decode_mime(value):
    if not value:
        return ""
    parts = decode_header(value)
    out = []
    for text, enc in parts:
        if isinstance(text, bytes):
            try:
                out.append(text.decode(enc or "utf-8", errors="replace"))
            except (LookupError, UnicodeDecodeError):
                out.append(text.decode("utf-8", errors="replace"))
        else:
            out.append(text)
    return "".join(out)


def detect_host(user):
    domain = user.split("@", 1)[1].lower() if "@" in user else ""
    return HOST_BY_DOMAIN.get(domain)


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--folder", default="INBOX")
    ap.add_argument("--query", required=True,
                    help="IMAP search query (see operators above)")
    ap.add_argument("--format", choices=["table", "json"], default="table")
    ap.add_argument("--limit", type=int, default=200,
                    help="cap on header fetches (default: 200)")
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
        typ, _ = M.select(f'"{args.folder}"', readonly=True)
        if typ != "OK":
            sys.exit(f"❌ impossible de sélectionner '{args.folder}'")

        # IMAP search expects the query wrapped in parens or as a bare list.
        query = args.query.strip()
        if not (query.startswith("(") and query.endswith(")")):
            query = f"({query})"
        typ, data = M.search(None, query)
        if typ != "OK":
            sys.exit(f"❌ SEARCH a échoué : {data!r}")

        ids = data[0].split()
        total = len(ids)
        if total > args.limit:
            print(f"ℹ {total} matches — fetch headers des {args.limit} derniers (override --limit)", file=sys.stderr)
            ids = ids[-args.limit:]

        rows = []
        for msg_id in ids:
            typ, msg_data = M.fetch(msg_id, "(BODY.PEEK[HEADER.FIELDS (DATE FROM TO SUBJECT)])")
            if typ != "OK" or not msg_data or not msg_data[0]:
                continue
            raw = msg_data[0][1]
            msg = email.message_from_bytes(raw)
            rows.append({
                "id": msg_id.decode(),
                "date": msg.get("Date", ""),
                "from": decode_mime(msg.get("From", "")),
                "to": decode_mime(msg.get("To", "")),
                "subject": decode_mime(msg.get("Subject", "")),
            })

        if args.format == "json":
            print(json.dumps({"folder": args.folder, "query": args.query,
                              "total_matches": total, "returned": len(rows),
                              "messages": rows}, indent=2, ensure_ascii=False))
        else:
            print(f"folder : {args.folder}")
            print(f"query  : {args.query}")
            print(f"matches: {total} (showing {len(rows)})")
            print("-" * 100)
            for r in rows:
                date_s = (r["date"] or "")[:25]
                from_s = (r["from"] or "")[:35]
                subj_s = (r["subject"] or "")[:60]
                print(f"{date_s:<25}  {from_s:<35}  {subj_s}")
    finally:
        try:
            M.logout()
        except Exception:
            pass


if __name__ == "__main__":
    main()
