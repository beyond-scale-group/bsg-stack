# IMAP providers — host/port reference

The scripts auto-detect the IMAP host from the email domain (see
`HOST_BY_DOMAIN` at the top of each script). Override with `IMAP_HOST`
when needed.

## Auto-detected

| Domain                                  | Host                         | Port | SSL  |
|---|---|---|---|
| `gmail.com`, `googlemail.com`           | `imap.gmail.com`             | 993  | yes  |
| Any Google Workspace custom domain (`*.com` with MX to Google) | `imap.gmail.com` | 993 | yes |
| `outlook.com`, `hotmail.com`, `live.com`, `office365.com` | `outlook.office365.com` | 993 | yes |
| `icloud.com`, `me.com`, `mac.com`       | `imap.mail.me.com`           | 993  | yes  |
| `yahoo.com`                             | `imap.mail.yahoo.com`        | 993  | yes  |
| `fastmail.com`                          | `imap.fastmail.com`          | 993  | yes  |

For a Google Workspace custom domain (`grenoble@prizoners.com`), set
`IMAP_HOST=imap.gmail.com` manually — auto-detection only matches the
literal `gmail.com` / `googlemail.com` domains.

## Other providers (set manually)

| Provider             | Host                            | Port | SSL  |
|---|---|---|---|
| Proton Mail Bridge   | `127.0.0.1` (local bridge)      | 1143 | STARTTLS |
| GMX                  | `imap.gmx.com`                  | 993  | yes  |
| Mail.ru              | `imap.mail.ru`                  | 993  | yes  |
| Zoho                 | `imap.zoho.com`                 | 993  | yes  |
| Yandex               | `imap.yandex.com`               | 993  | yes  |
| Mailbox.org          | `imap.mailbox.org`              | 993  | yes  |
| Tutanota             | not supported (no IMAP API)     | —    | —    |
| Custom (cPanel, etc.)| usually `mail.<your-domain>`    | 993  | yes  |

Set both in the credentials file:

```env
IMAP_USER=you@example.com
IMAP_APP_PASSWORD=…
IMAP_HOST=mail.example.com
IMAP_PORT=993
```

## STARTTLS (port 143) vs implicit SSL (port 993)

These scripts use **implicit SSL on port 993** (`imaplib.IMAP4_SSL`).
Pure-IMAP-over-port-143-with-STARTTLS isn't supported out of the box —
swap `IMAP4_SSL` for `IMAP4` + `starttls()` if you need it. Note that
all major providers above support 993 directly; STARTTLS is only needed
for legacy / self-hosted setups.

## Proton Mail

Proton doesn't expose IMAP directly — it requires running
[Proton Mail Bridge](https://proton.me/mail/bridge) locally, which
proxies the encrypted Proton API to a localhost IMAP server. Once the
bridge is running, configure with:

```env
IMAP_USER=you@protonmail.com
IMAP_APP_PASSWORD=<bridge password, NOT your Proton password>
IMAP_HOST=127.0.0.1
IMAP_PORT=1143
```

The bridge uses STARTTLS on 1143, not implicit SSL — these scripts would
need a small patch (`imaplib.IMAP4` instead of `IMAP4_SSL`, then
`.starttls()`).

## Verifying a provider's IMAP settings

When in doubt:

```bash
# Discover via DNS:
dig +short MX example.com
# (the MX target's domain often gives away the provider)

# Probe:
nc -zv imap.candidate.com 993
# (succeeds if the port is open)
```
