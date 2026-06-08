# Outlook / Microsoft 365 — IMAP setup

## Constraints

- **Microsoft is deprecating basic auth for IMAP** on enterprise tenants
  (Microsoft 365 Business / Enterprise). On those accounts, IMAP basic
  auth is disabled by default — you'd need OAuth2 over IMAP, which these
  scripts don't yet implement. If `imap-doctor.sh` returns
  `AUTHENTICATIONFAILED` despite a correct app password, this is the
  likely cause.
- **Consumer Outlook/Hotmail accounts** (personal `@outlook.com`,
  `@hotmail.com`, `@live.com`) still support IMAP with an app password.
- **Tenant admin can re-enable basic IMAP** per-mailbox via the Exchange
  admin center — escalate to the client's IT contact if needed.

## Setup (consumer account)

1. **Enable 2FA**: https://account.microsoft.com/security → Advanced
   security options → Two-step verification → Turn on.

2. **Generate an app password**:
   https://account.microsoft.com/security → Advanced security options →
   App passwords → Create a new app password → copy.

3. **Wire up credentials**:
   ```bash
   bash scripts/env-setup.sh
   # email : you@outlook.com
   # host  : outlook.office365.com   (auto-detected)
   # port  : 993
   # pwd   : (paste app password)
   ```

4. **Smoke test**: `bash scripts/imap-doctor.sh`

## Folder names

| Logical | Outlook IMAP folder            |
|---|---|
| Inbox   | `Inbox`                        |
| Sent    | `Sent Items`                   |
| Drafts  | `Drafts`                       |
| Trash   | `Deleted Items`                |
| Spam    | `Junk Email`                   |
| Archive | `Archive`                      |

The `sent`/`drafts`/`trash` shorthands in `imap-fetch.py` include
these candidates.

## Enterprise (M365 Business / Enterprise)

If basic auth is disabled at the tenant level, options are:

1. **Ask the admin to re-enable IMAP basic auth** for the target mailbox
   (per-user, can be scoped to a single account):
   ```powershell
   Set-CASMailbox -Identity user@tenant.com -ImapEnabled $true
   ```

2. **Export via Outlook desktop** (PST file) — outside the scope of this
   skill, but useful for one-off audits.

3. **Use Microsoft Graph API** — equivalent to OAuth, but on the MS side.
   The `google-workspace` skill doesn't cover MS — a future
   `microsoft-graph` skill would.
