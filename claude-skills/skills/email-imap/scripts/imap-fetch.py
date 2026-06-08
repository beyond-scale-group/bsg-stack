#!/usr/bin/env python3
"""
imap-fetch.py — download a date range of IMAP messages to local .eml files
plus a JSON index and a CSV summary, for any IMAP server.

Auth via env vars OR a credentials file (auto-loaded):
    IMAP_USER='you@example.com'
    IMAP_APP_PASSWORD='xxxx xxxx xxxx xxxx'    # spaces ok, stripped
    IMAP_HOST='imap.gmail.com'                 # optional, auto-detected
                                               # from user domain
    IMAP_PORT='993'                            # optional, default 993

Credentials file (chmod 600) — auto-loaded in this order:
    1. $IMAP_ENV_FILE
    2. ~/.config/email-imap/credentials.env
    3. ./.env (only if present in cwd)
Set up the file interactively with: bash scripts/env-setup.sh

Usage:
    python3 imap-fetch.py --since-days 60
    python3 imap-fetch.py --since-days 30 --folders inbox
    python3 imap-fetch.py --folders 'INBOX,[Gmail]/Sent Mail' --max-per-folder 50
    python3 imap-fetch.py --out ~/clients/acme/email-audit

Output layout (default):
    ~/email-exports/<user>/<YYYY-MM-DD_HHMMSS>/
        inbox/  *.eml
        sent/   *.eml
        index.json
        summary.csv

Pure stdlib — no pip install needed.
"""

import argparse
import email
import imaplib
import json
import os
import re
import sys
from datetime import datetime, timedelta, timezone
from email.header import decode_header
from email.utils import parsedate_to_datetime
from pathlib import Path

DEFAULT_PORT = 993


def load_env_file(explicit_path=None):
    """Load KEY=VALUE pairs from a .env-style file without overriding
    variables already set in the environment.

    Search order:
      1. explicit_path arg (from --env-file)
      2. $IMAP_ENV_FILE
      3. ~/.config/email-imap/credentials.env
      4. ./.env in cwd

    Returns the path that was actually loaded, or None.
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
                if not line or line.startswith("#"):
                    continue
                if "=" not in line:
                    continue
                key, value = line.split("=", 1)
                key = key.strip()
                value = value.strip()
                # Strip surrounding quotes
                if len(value) >= 2 and value[0] == value[-1] and value[0] in ('"', "'"):
                    value = value[1:-1]
                if key and key not in os.environ:
                    os.environ[key] = value
        return path
    return None


# Auto-detect IMAP host from user domain. Override with $IMAP_HOST.
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

# Shorthand → list of candidate IMAP folder names (provider-localized).
# Tried in order; the first that selects OK wins.
FOLDER_CANDIDATES = {
    "inbox": ["INBOX"],
    "sent": [
        "[Gmail]/Sent Mail",
        "[Gmail]/Messages envoyés",
        "[Gmail]/Envoyés",
        "Sent Items",
        "Sent",
    ],
    "drafts": ["[Gmail]/Drafts", "Drafts", "Brouillons"],
    "trash": ["[Gmail]/Trash", "Deleted Items", "Trash", "Corbeille"],
    "spam": ["[Gmail]/Spam", "Junk Email", "Spam"],
    "all": ["[Gmail]/All Mail", "[Gmail]/Tous les messages", "Archive"],
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


def slugify(text, maxlen=60):
    s = re.sub(r"[^a-zA-Z0-9_-]+", "-", text or "").strip("-")
    return s[:maxlen] or "no-subject"


def detect_host(user):
    domain = user.split("@", 1)[1].lower() if "@" in user else ""
    return HOST_BY_DOMAIN.get(domain)


def resolve_folder_names(spec):
    """spec = comma-separated shortcuts or raw IMAP names.
    Returns list of (label, [candidate_imap_names])."""
    out = []
    for token in spec.split(","):
        t = token.strip()
        if not t:
            continue
        if t.lower() in FOLDER_CANDIDATES:
            out.append((t.lower(), FOLDER_CANDIDATES[t.lower()]))
        else:
            # Raw IMAP name — keep its case, no candidates list
            label = re.sub(r"[^a-zA-Z0-9_-]+", "_", t).strip("_").lower() or "folder"
            out.append((label, [t]))
    return out


def fetch_folder(M, candidates, since_date, out_dir, label, max_messages=None):
    selected = None
    for name in candidates:
        typ, _ = M.select(f'"{name}"', readonly=True)
        if typ == "OK":
            selected = name
            break
    if not selected:
        print(f"⚠ {label}: aucun candidat ne matche ({candidates}), on saute")
        return []

    since_str = since_date.strftime("%d-%b-%Y")
    typ, data = M.search(None, f'(SINCE "{since_str}")')
    if typ != "OK":
        print(f"⚠ {label}: SEARCH a échoué")
        return []

    ids = data[0].split()
    if max_messages is not None and len(ids) > max_messages:
        print(f"→ {label} ({selected}): {len(ids)} trouvés, cap à {max_messages}")
        ids = ids[-max_messages:]
    else:
        print(f"→ {label} ({selected}): {len(ids)} messages depuis {since_str}")

    folder_dir = out_dir / label
    folder_dir.mkdir(parents=True, exist_ok=True)
    index = []

    for n, msg_id in enumerate(ids, 1):
        typ, msg_data = M.fetch(msg_id, "(RFC822)")
        if typ != "OK" or not msg_data or not msg_data[0]:
            continue
        raw = msg_data[0][1]
        msg = email.message_from_bytes(raw)

        date_hdr = msg.get("Date", "")
        try:
            dt = parsedate_to_datetime(date_hdr)
        except Exception:
            dt = None
        date_iso = dt.isoformat() if dt else ""
        date_for_name = dt.strftime("%Y%m%d-%H%M%S") if dt else "unknown"

        subject = decode_mime(msg.get("Subject", "")).strip()
        fname = f"{date_for_name}_{msg_id.decode()}_{slugify(subject)}.eml"
        (folder_dir / fname).write_bytes(raw)

        index.append(
            {
                "id": msg_id.decode(),
                "folder": label,
                "imap_folder": selected,
                "file": str((folder_dir / fname).relative_to(out_dir)),
                "date": date_iso,
                "from": decode_mime(msg.get("From", "")),
                "to": decode_mime(msg.get("To", "")),
                "cc": decode_mime(msg.get("Cc", "")),
                "subject": subject,
                "size_bytes": len(raw),
            }
        )

        if n % 25 == 0 or n == len(ids):
            print(f"  {label}: {n}/{len(ids)}")

    return index


def main():
    ap = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    ap.add_argument("--since-days", type=int, default=60,
                    help="combien de jours en arrière (défaut: 60)")
    ap.add_argument("--out", default=None,
                    help="dossier de sortie (défaut: ~/email-exports/<user>/<ts>)")
    ap.add_argument("--folders", default="inbox,sent",
                    help="liste séparée par virgules (shorthand ou nom IMAP brut)")
    ap.add_argument("--max-per-folder", type=int, default=None,
                    help="cap de sécurité (smoke test)")
    ap.add_argument("--env-file", default=None,
                    help="credentials.env explicite (sinon: chaîne de fallback)")
    args = ap.parse_args()

    loaded = load_env_file(args.env_file)
    if loaded:
        print(f"🔐 .env chargé : {loaded}", file=sys.stderr)

    user = os.environ.get("IMAP_USER", "").strip()
    pwd = os.environ.get("IMAP_APP_PASSWORD", "").replace(" ", "")
    if not user or not pwd:
        sys.exit("❌ IMAP_USER et IMAP_APP_PASSWORD doivent être définis en env")

    host = os.environ.get("IMAP_HOST") or detect_host(user)
    if not host:
        sys.exit(
            f"❌ pas d'IMAP host par défaut pour le domaine '{user.split('@')[-1]}'.\n"
            "   Définis IMAP_HOST=… (voir references/providers.md)"
        )
    port = int(os.environ.get("IMAP_PORT", DEFAULT_PORT))

    if args.out:
        run_dir = Path(args.out).expanduser()
    else:
        ts = datetime.now().strftime("%Y-%m-%d_%H%M%S")
        run_dir = Path("~/email-exports").expanduser() / user / ts
    run_dir.mkdir(parents=True, exist_ok=True)

    since = datetime.now(timezone.utc) - timedelta(days=args.since_days)

    print(f"📬 {user} via {host}:{port} — {args.since_days}j en arrière")
    M = imaplib.IMAP4_SSL(host, port)
    try:
        M.login(user, pwd)
    except imaplib.IMAP4.error as e:
        sys.exit(
            f"❌ login IMAP refusé : {e}\n"
            "   (IMAP activé dans les paramètres ? app password correct ?)"
        )

    try:
        all_index = []
        for label, candidates in resolve_folder_names(args.folders):
            idx = fetch_folder(
                M, candidates, since, run_dir, label,
                max_messages=args.max_per_folder,
            )
            all_index.extend(idx)

        index_file = run_dir / "index.json"
        index_file.write_text(json.dumps(all_index, indent=2, ensure_ascii=False))

        summary = run_dir / "summary.csv"
        with summary.open("w") as f:
            f.write("date\tfolder\tfrom\tto\tsubject\n")
            for m in sorted(all_index, key=lambda x: x["date"]):
                f.write(
                    "\t".join(
                        [
                            m["date"][:19],
                            m["folder"],
                            m["from"][:80].replace("\t", " "),
                            m["to"][:80].replace("\t", " "),
                            m["subject"][:140].replace("\t", " "),
                        ]
                    )
                    + "\n"
                )

        print(f"\n✅ {len(all_index)} messages sauvegardés")
        print(f"   📁 {run_dir}")
        print(f"   📋 index   : {index_file}")
        print(f"   📊 résumé  : {summary}")
    finally:
        try:
            M.logout()
        except Exception:
            pass


if __name__ == "__main__":
    main()
