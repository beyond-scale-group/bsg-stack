# Gmail / Google Workspace — IMAP setup

## Why use this and not OAuth (`google-workspace`)?

- The OAuth app is stuck in **Testing** mode and the target user isn't
  in the test-users list (you'd need to add them every 7 days because
  refresh tokens expire in Testing mode).
- The OAuth client lives on a GCP project you don't own (e.g. client
  account, the project belongs to their IT team).
- The target Workspace admin has blocked the OAuth app at the org level.
- You want a one-off read of a mailbox without leaving an OAuth grant
  behind.

In all these cases, IMAP + app password is the path of least friction.

## Constraints to know

- **Requires 2FA.** Google refuses to issue app passwords on accounts
  without 2-Step Verification. Enable at https://myaccount.google.com/security.
- **IMAP must be enabled in Gmail settings** (per-mailbox, not org-level).
  Some Workspace admins disable IMAP at the org level → the per-mailbox
  toggle becomes a no-op. If `imap-doctor.sh` returns `LOGIN failed
  [AUTHENTICATIONFAILED]` after a correct app password, that's the most
  likely cause.
- **Read-only is the safe default.** All scripts open folders with
  `readonly=True` — no flags are toggled, no messages are marked read.

## Setup (5 minutes)

1. **Enable 2-Step Verification**
   - https://myaccount.google.com/security
   - "How you sign in to Google" → 2-Step Verification → On

2. **Generate an app password**
   - https://myaccount.google.com/apppasswords
   - App name: `imap-fetch` (or anything memorable — used only for revocation)
   - Click **Create** → copy the 16-char password (format: `xxxx xxxx xxxx xxxx`)

3. **Enable IMAP in Gmail**
   - In Gmail web: ⚙️ → **See all settings** → tab **Forwarding and POP/IMAP**
   - **IMAP access** → "Enable IMAP" → Save Changes

4. **Wire up credentials**
   ```bash
   bash scripts/env-setup.sh
   # → answers:
   #   email     : grenoble@prizoners.com
   #   host      : imap.gmail.com    (auto-detected)
   #   port      : 993
   #   app pwd   : (paste the 16 chars)
   ```

5. **Smoke test**
   ```bash
   bash scripts/imap-doctor.sh
   ```

## Gmail-specific folder names

Gmail surfaces its system labels as IMAP folders under a `[Gmail]/` prefix.
The exact names depend on the account's display language:

| Logical | English Gmail              | French Gmail                     |
|---|---|---|
| Inbox   | `INBOX`                    | `INBOX`                          |
| Sent    | `[Gmail]/Sent Mail`        | `[Gmail]/Messages envoyés`       |
| Drafts  | `[Gmail]/Drafts`           | `[Gmail]/Brouillons`             |
| Trash   | `[Gmail]/Trash`            | `[Gmail]/Corbeille`              |
| Spam    | `[Gmail]/Spam`             | `[Gmail]/Spam`                   |
| All     | `[Gmail]/All Mail`         | `[Gmail]/Tous les messages`      |
| Starred | `[Gmail]/Starred`          | `[Gmail]/Suivis`                 |

The shortcuts in `imap-fetch.py` (`sent`, `drafts`, `trash`, `all`)
try both English and French candidates automatically. If you've got a
non-French/English Workspace tenant, list folders first to find the
right name:

```bash
python3 scripts/imap-folders.py
```

…and pass the raw name verbatim:

```bash
python3 scripts/imap-fetch.py --folders 'INBOX,[Gmail]/Inviati'
```

## Gmail IMAP quirks

- **Labels show up as folders.** Every Gmail label gets an IMAP folder of
  the same name (top-level). A message with two labels appears under
  both folders — and also under `[Gmail]/All Mail`. Plan for
  duplicate downloads if you fetch multiple folders.
- **`UID` vs `seq`.** This skill uses sequence numbers (default). For
  long-running incremental jobs that need stable IDs across deletions,
  switch to UID-based fetch — not required for one-shot dumps.
- **Throttling.** Gmail caps simultaneous IMAP connections per account at
  15. These scripts use a single connection, so you'll never hit it from
  one process. Don't fan out 20 of these in parallel.
- **2FA-less accounts (rare legacy)** — Google removed the "less secure
  apps" toggle in 2022. There is no longer a working bypass; 2FA + app
  password is the only path.

## Revoke when done

When the engagement ends or the analysis is complete:

1. Revoke the app password: https://myaccount.google.com/apppasswords
   → click the trash icon next to the entry created in step 2 above.
2. Delete the credentials file: `rm ~/.config/email-imap/credentials.env`
3. Delete the export directory if you no longer need the raw data:
   `rm -rf ~/email-exports/<email>/`
