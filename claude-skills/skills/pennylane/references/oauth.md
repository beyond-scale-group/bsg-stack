# Pennylane OAuth 2.0 — firm-level (multi-company) connector

Firm tokens are the right grant for "connect to all our structures": a single
OAuth authorization, granted by a user with firm-wide permissions, exposes
every connected company through the same token. Company tokens see exactly one
company — use those only for single-entity integrations.

## Endpoints

| Purpose | URL |
|---|---|
| Authorize | `https://app.pennylane.com/oauth/authorize` |
| Token (exchange + refresh) | `https://app.pennylane.com/oauth/token` |
| Revoke | `https://app.pennylane.com/oauth/revoke` |
| API base (v2) | `https://app.pennylane.com/api/external/v2` |

## Register the app

Partner/integration OAuth apps are provisioned by Pennylane's partnerships team
(no self-serve app registration for the External API). You receive a
`client_id`, `client_secret`, and register one or more `redirect_uri`s. Request
a **sandbox** for development. Set credentials as environment variables; never
commit them:

```bash
export PENNYLANE_CLIENT_ID=...
export PENNYLANE_CLIENT_SECRET=...
export PENNYLANE_REDIRECT_URI=https://your.app/callback
```

## Authorization-code flow

1. Build the consent URL and have the firm admin open it:
   ```bash
   scripts/pennylane.py auth-url --state "$(openssl rand -hex 16)"
   ```
   Params sent: `client_id`, `redirect_uri`, `response_type=code`, `scope`
   (space-separated), `state` (CSRF — validate it on return).
2. The user approves; Pennylane redirects to `redirect_uri?code=...&state=...`.
3. Exchange the code server-side (the script stores tokens):
   ```bash
   scripts/pennylane.py exchange "<authorization_code>"
   ```

## Token lifetimes & rotation — the critical bit

- **Access token: ~24 h.** Sent as `Authorization: Bearer <token>`.
- **Refresh token: ~90 days, single-use with rotation.** Every refresh
  *immediately invalidates* the refresh token used and returns a brand-new one.
  If you fire two concurrent refreshes, or fail to persist the new refresh
  token, the integration is locked out and must re-authorize.

`scripts/pennylane.py` handles this safely: tokens live in a JSON store
(default `~/.config/pennylane/tokens.json`, override with
`PENNYLANE_TOKEN_STORE`), written atomically with `0600` perms. `get`/`post`/
`token` auto-refresh when the access token is within 60 s of expiry. Do not run
parallel processes against the same token store.

```bash
scripts/pennylane.py token     # prints a valid access token (refreshes if needed)
scripts/pennylane.py refresh   # force a rotation
scripts/pennylane.py revoke    # end access
```

## Scopes

Request least privilege. Granular v2 scopes follow `<resource>:<access>` where
access is `read`/`readonly` or `all` (read+write). Common ones:

```
companies:read
customer_invoices:all   customer_invoices:readonly
supplier_invoices:all   supplier_invoices:readonly
customers:all  suppliers:all
ledger_entries:read  ledger_accounts:read
products:all  categories:all
```

Set the set you need via `PENNYLANE_SCOPES` or `auth-url --scopes "..."`. The
exact catalog of scope names lives in the Pennylane docs — confirm there before
going to production; the script's default is a broad starter set.
