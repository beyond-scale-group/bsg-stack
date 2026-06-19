---
name: email-imap
description: >-
  IMAP toolkit for reading, searching, downloading, and triaging emails from
  any IMAP server (Gmail, Google Workspace, Outlook/Microsoft 365, iCloud,
  Fastmail, custom servers). Use this when you need read access to a mailbox
  but OAuth (the `google-workspace` skill) is impractical — typically: client
  mailboxes where you don't own the GCP project, "internal-only" OAuth apps
  with test-user caps, accounts where the admin hasn't whitelisted your
  app, or non-Google providers. The skill ships pure-stdlib Python scripts
  (no external deps): `imap-fetch.py` to download a date range of messages
  as .eml + index.json, `imap-search.py` for IMAP-query searches, and
  `imap-folders.py` to enumerate folders. Auth is via app password (Gmail,
  iCloud, Fastmail) or basic auth (custom servers); credentials live in
  env vars, never on disk. Triggers include "récupérer des emails", "fetch
  inbox", "download mailbox", "export Gmail without OAuth", "IMAP
  Outlook/iCloud", "analyser une boîte mail client", "audit mailbox",
  "extraire les emails", "scan a mailbox", "client email analysis".
  Not for sending — pair with SMTP or the `google-workspace` skill for
  send flows. Not for OAuth-friendly accounts where you control the
  GCP project — `google-workspace` gives you a richer surface there.
model: haiku
---

# email-imap

Read-only IMAP toolkit for cases where OAuth (`google-workspace`) won't fly:
client mailboxes, non-Google providers, OAuth apps stuck in Testing mode,
admin-restricted domains. Auth uses an app password (recommended) or basic
auth (custom servers). Pure-stdlib Python — no `pip install` needed.

## When to use this vs `google-workspace`

| Case | Use |
|---|---|
| Your own Google Workspace account, GCP project under your control | `google-workspace` (richer API, send + read, MCP-friendly) |
| Client Gmail account where you have the password but not GCP ownership | **`email-imap`** |
| Internal-only OAuth app, target user not in test-users list | **`email-imap`** |
| Outlook / iCloud / Fastmail / self-hosted IMAP | **`email-imap`** |
| Send email | `google-workspace` (or SMTP — out of scope here) |
| One-off offline analysis: dump → grep → done | **`email-imap`** |

## Preflight (every session)

```bash
# 1. Doctor — verifies python3, env vars, IMAP reachability.
bash scripts/imap-doctor.sh

# 2. Required env vars (never store on disk):
export IMAP_USER='grenoble@prizoners.com'
export IMAP_APP_PASSWORD='xxxx xxxx xxxx xxxx'     # spaces are fine, stripped
export IMAP_HOST='imap.gmail.com'                  # optional, defaults below
export IMAP_PORT='993'                             # optional, defaults to 993
```

Default IMAP host depends on the address domain — see `references/providers.md`
for the full table. Gmail / Google Workspace → `imap.gmail.com:993`.

## Decision tree

```
Setup help?           → references/<provider>.md          §References
List folders?         → bash scripts/imap-folders.py      §Folders
Search messages?      → bash scripts/imap-search.py       §Search
Download a range?     → bash scripts/imap-fetch.py        §Fetch
Doctor / smoke test?  → bash scripts/imap-doctor.sh       §Preflight
```

## Folders → `scripts/imap-folders.py`

List every IMAP folder on the server with message counts:

```bash
python3 scripts/imap-folders.py
# Table:  FOLDER                          MESSAGES  RECENT
# INBOX                                        1287      12
# [Gmail]/Sent Mail                             934       0
# [Gmail]/All Mail                             4521       0
# [Gmail]/Drafts                                  3       0
# ...
```

Use this first when you don't know the localized folder name (Gmail keeps
`Sent Mail` in English, but admin can rename, and other providers vary).

## Fetch → `scripts/imap-fetch.py`

Download messages from one or more folders into a timestamped output
directory, with a JSON index and a CSV summary for fast scanning:

```bash
# Default: INBOX + Sent, last 60 days, ~/email-exports/<user>/<ts>/
python3 scripts/imap-fetch.py --since-days 60

# Narrow scope:
python3 scripts/imap-fetch.py --since-days 30 --folders inbox
python3 scripts/imap-fetch.py --folders 'INBOX,[Gmail]/Sent Mail,Archive'

# Cap per folder (smoke test before a big run):
python3 scripts/imap-fetch.py --max-per-folder 10

# Custom output dir (otherwise: ~/email-exports/<user>/<timestamp>):
python3 scripts/imap-fetch.py --out ~/clients/prizoners/email-audit
```

Output layout:

```
~/email-exports/grenoble@prizoners.com/2026-06-08_173042/
  inbox/
    20260606-093412_42_RE-r-servation-anniversaire.eml
    20260606-110205_43_devis-team-building.eml
    ...
  sent/
    ...
  index.json   # one entry per message — id, file, date, from, to, subject, size
  summary.csv  # tab-separated, sorted by date — easy to grep / open in Excel
```

Each `.eml` is the raw RFC822 message — re-openable in any mail client,
parseable by Python's `email` module, ready for analysis without touching
the server again.

⚠ **`--folders` accepts both shorthand and raw IMAP names:**

| Shorthand     | Tries (in order)                                        |
|---|---|
| `inbox`       | `INBOX`                                                 |
| `sent`        | `[Gmail]/Sent Mail`, `[Gmail]/Messages envoyés`, `Sent Items`, `Sent` |
| `drafts`      | `[Gmail]/Drafts`, `Drafts`                              |
| `trash`       | `[Gmail]/Trash`, `Deleted Items`, `Trash`               |
| `all`         | `[Gmail]/All Mail`, `Archive`, `[Gmail]/Tous les messages` |

Raw names pass through unchanged (`--folders 'INBOX,Archive/2025'`).

## Search → `scripts/imap-search.py`

Run an IMAP-query search on one folder, print matching message headers
(no body download — fast):

```bash
# All unread from the last week:
python3 scripts/imap-search.py --folder INBOX --query 'UNSEEN SINCE 01-Jun-2026'

# From a specific sender:
python3 scripts/imap-search.py --query 'FROM "client@example.com"'

# Subject keyword:
python3 scripts/imap-search.py --query 'SUBJECT "réservation"'

# JSON output for scripting:
python3 scripts/imap-search.py --query 'UNSEEN' --format json
```

IMAP search syntax: `SINCE dd-Mon-yyyy`, `BEFORE dd-Mon-yyyy`, `FROM`,
`TO`, `CC`, `SUBJECT`, `BODY`, `TEXT` (header+body), `UNSEEN`, `SEEN`,
`ANSWERED`, `FLAGGED`. Combine with parens: `'(FROM "x" UNSEEN SINCE 01-Jun-2026)'`.

Full operator list: see `references/imap-query.md`.

## Doctor → `scripts/imap-doctor.sh`

Pre-flight check used before any task, and as a smoke test after setup:

```bash
bash scripts/imap-doctor.sh
# ✓ python3 found
# ✓ IMAP_USER set
# ✓ IMAP_APP_PASSWORD set
# ✓ TCP reachable: imap.gmail.com:993
# ✓ IMAP login successful
# ✓ INBOX selectable (1287 messages)
```

Exit codes: `0` healthy, `1` warning, `2` login/connection failed.

## Auth setup (one-time, per account)

The setup ritual depends on the provider — see `references/<provider>.md`
for the click-through. Universal pattern:

1. **Enable 2FA** on the target account (mandatory for app passwords).
2. **Generate an app password** in the provider's account-security page.
3. **Activate IMAP** in the mail-app settings (Gmail/Workspace require this).
4. **Export env vars** in the shell that will run the scripts:
   ```bash
   export IMAP_USER='you@example.com'
   export IMAP_APP_PASSWORD='xxxx xxxx xxxx xxxx'
   ```
5. **Smoke-test**: `bash scripts/imap-doctor.sh`

App passwords are revokable per-app. When the engagement ends, revoke from
the same page where you created it.

## Storage & safety

- **Output dir defaults to `~/email-exports/`** — outside any repo, so
  accidental commits are impossible. Override with `--out` for explicit
  control.
- **App passwords live in env vars only** — never written to disk by these
  scripts. Use a `.envrc` (direnv) or paste-into-shell pattern, but don't
  commit them.
- **Outputs contain PII** (customer addresses, phone numbers, names, sometimes
  payment refs). Treat the output directory as `chmod 700` and clean up
  with `rm -rf` when the analysis is done.
- **For analysis in the repo**, copy *derived* artifacts only (counts,
  anonymized samples, themes) — never the raw .eml files.

## References

- [`references/gmail.md`](references/gmail.md) — Gmail / Google Workspace setup,
  folder names, IMAP toggle, admin gotchas
- [`references/outlook.md`](references/outlook.md) — Outlook / Microsoft 365 setup
- [`references/icloud.md`](references/icloud.md) — iCloud Mail setup
- [`references/providers.md`](references/providers.md) — host/port table for common providers
- [`references/imap-query.md`](references/imap-query.md) — full IMAP search-query syntax

## How to improve this skill

This file is a cached copy of `claude-skills/skills/email-imap/SKILL.md` in
[beyond-scale-group/bsg-stack](https://github.com/beyond-scale-group/bsg-stack).
That repo is the single source of truth — local copies are overwritten by
the BSG install flow. To improve the skill: clone bsg-stack, edit on a
branch, open a PR against `main`.
