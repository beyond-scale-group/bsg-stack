# iCloud Mail — IMAP setup

## Constraints

- **Requires 2FA on the Apple ID.** Without it, no app-specific passwords.
- **App-specific passwords are mandatory.** iCloud refuses bare Apple ID
  passwords on IMAP.
- **No custom domain support over IMAP** for free iCloud accounts. Paid
  iCloud+ accounts using a custom domain (`@yourdomain.com` aliased to
  iCloud) can use IMAP, but only with the primary `@icloud.com` address
  as `IMAP_USER`.

## Setup

1. **Enable 2FA** on the Apple ID: System Settings → Apple ID →
   Sign-In & Security → Two-Factor Authentication → Turn on.

2. **Generate an app-specific password**:
   - https://appleid.apple.com → Sign-In and Security → App-Specific
     Passwords → Generate Password
   - Label: `imap-fetch` (used only for revocation)
   - Copy the 16-character password (format: `xxxx-xxxx-xxxx-xxxx`)

3. **Wire up credentials**:
   ```bash
   bash scripts/env-setup.sh
   # email : you@icloud.com
   # host  : imap.mail.me.com        (auto-detected)
   # port  : 993
   # pwd   : (paste, dashes are stripped automatically)
   ```

4. **Smoke test**: `bash scripts/imap-doctor.sh`

## Folder names

iCloud uses standard names — no provider prefix like Gmail's `[Gmail]/`:

| Logical | iCloud IMAP folder       |
|---|---|
| Inbox   | `INBOX`                  |
| Sent    | `Sent Messages`          |
| Drafts  | `Drafts`                 |
| Trash   | `Deleted Messages`       |
| Junk    | `Junk`                   |
| Archive | `Archive`                |

The `sent` shorthand in `imap-fetch.py` includes `Sent` but **not**
`Sent Messages` — pass the raw name:

```bash
python3 scripts/imap-fetch.py --folders 'INBOX,Sent Messages'
```

## Revoke when done

https://appleid.apple.com → App-Specific Passwords → Edit → remove the
entry created in step 2.
