# X skill — one-time setup (X developer app + OAuth token)

Two ways to authenticate — pick one:

- **OAuth 2.0 (sections 1–5)** on a personal machine: the access token lasts 2 hours, the CLI
  refreshes it and re-saves the rotated tokens to `~/.env`.
- **OAuth 1.0a ([section 6](#6-oauth-10a-mode-server-agents))** for an agent on a server whose
  secrets come from a read-only vault (e.g. Donna): four keys that do not expire, nothing to
  rewrite. Bookmarks are not available in this mode, and X retires OAuth 1.0a on 2027-01-31.

Do this once per X account. Everything is done by the account owner in their **own browser**:
X blocks cloud/automated browsers with a "confirm you are human" check, and the owner must
accept the developer terms and any plan/payment themselves. Never log in for them, never ask
for their password.

*Last checked: 2026-11-23. The X developer portal changes often — labels may differ slightly.
Plans and prices have changed several times: check the plan page and which endpoints it unlocks
before paying.*

## 1. Create the app

1. Open **developer.x.com** (may redirect to **console.x.com**) and sign in with the account the
   skill will act as.
2. First visit: accept the developer agreement and describe the use in one line
   (e.g. "personal assistant: read my likes/bookmarks, post and DM on my own account").
3. Create a **Project**, then an **App** inside it (e.g. `x-skill`).
4. Check the **plan**. The bookmarks, likes, DM and write endpoints must be included. If a plan
   blocks them or is paid, stop and decide with the owner before paying.

   What the official docs say (docs.x.com, read 2026-11-23): the **pay-per-usage** plan is the
   only one documented on the pricing page, capped at 3 million post reads per billing cycle;
   more volume means Enterprise. Indicative prices, **to confirm in the Developer Console**:

   | Action | Price |
   |---|---|
   | Read own bookmarks / own liked posts | $0.001 per resource returned |
   | Read DM events | $0.010 per resource |
   | Send a DM | $0.015 per request |
   | Create a post | $0.015 per request ($0.200 if it contains a URL) |
   | Bookmark / unbookmark | $0.005 per request |
   | Like / follow | $0.015 per request (inferred, not stated explicitly) |

   Owned reads (bookmarks, likes) are priced as such only for the authenticated user's own ID
   on their own app. Quote-posts need Enterprise. Free / Basic / Pro tiers are not documented
   on that page — do not assume they exist or what they include.

## 2. User authentication settings

In the app, **User authentication settings → Set up**:

| Field | Value |
|---|---|
| App permissions | **Read and write and Direct message** |
| Type of app | **Native App** (public client, PKCE — no secret needed) |
| Callback / Redirect URI | `http://127.0.0.1:8765/callback` |
| Website URL | any valid URL (not verified), e.g. `https://example.com` |

Save. If permissions were changed **after** a token was issued, the old token keeps the old
scopes: run `authorize.mjs` again.

Token facts from the docs: the authorisation code is valid **30 seconds** (the script exchanges
it immediately — approve promptly); the access token lasts **2 hours**, and the CLI renews it
with the refresh token (issued because of `offline.access`; refresh tokens rotate and are
re-saved to `~/.env`). A public client (Native App) sends `client_id` in the body; a
confidential client authenticates with its secret.

## 3. Credentials into `~/.env`

From **Keys and tokens**, copy the **OAuth 2.0 Client ID** and add it to `~/.env`:

```
X_CLIENT_ID=...
```

- The Client ID is not a secret. The **Client Secret** (only shown for confidential apps),
  API keys and tokens are: put them in `~/.env` only, never in chat, a repo or a commit.
- `X_CLIENT_SECRET` is optional and only needed if the app was created as a confidential client.

## 4. Authorise (get the token)

On the owner's machine, with their browser logged in to X:

```bash
node ~/.claude/skills/x/scripts/authorize.mjs
```

It opens the consent page, receives the callback on `127.0.0.1:8765` and writes
`X_ACCESS_TOKEN` and `X_REFRESH_TOKEN` to `~/.env` (mode 600). Nothing is printed. Scopes asked:

`tweet.read tweet.write users.read bookmark.read bookmark.write like.read like.write
follows.read follows.write dm.read dm.write offline.access`

## 5. Check

```bash
node ~/.claude/skills/x/scripts/x.mjs me
```

Must print the account's own profile. Then try `bookmarks --max 5`.

## 6. OAuth 1.0a mode (server agents)

For an agent whose secrets are injected as environment variables from a read-only vault: the
OAuth 2.0 refresh token rotates on every refresh and could not be saved there, so access would
die after 2 hours. OAuth 1.0a keys do not expire.

1. Same app as in section 1. In **User authentication settings**, set App permissions to
   **Read and write and Direct message** and save — **before** generating the tokens below.
2. **Keys and tokens** tab:
   - **API Key and Secret** (consumer keys): generate or regenerate, copy both.
   - **Access Token and Secret**: generate them **after** step 1, otherwise they keep the old
     permissions (regenerate them if permissions changed). They act as the account that owns
     the app.

   Each value is shown once; regenerating invalidates the previous one.
3. Put the four values in the vault (or the process environment, or `~/.env`):

   ```
   X_API_KEY=...
   X_API_SECRET=...
   X_OAUTH1_ACCESS_TOKEN=...
   X_OAUTH1_ACCESS_SECRET=...
   ```

4. Check: `node ~/.claude/skills/x/scripts/x.mjs auth` must say `"mode": "oauth1"`, then
   `x.mjs me`.

Environment variables win over `~/.env`, which may be absent. When all four are set, the CLI signs
requests with OAuth 1.0a (HMAC-SHA1) and never refreshes anything; otherwise it uses OAuth 2.0.

What X accepts with OAuth 1.0a (docs.x.com OpenAPI spec 2.175 and guides, checked 2026-11-26):

| Command | OAuth 1.0a |
|---|---|
| `me`, `user`, `likes`, `timeline`, `mentions`, `search`, `following`, `dms`, `post`, `like`, `unlike`, `follow`, `unfollow`, `dm` | Accepted |
| `bookmark`, `unbookmark` | **No** — OAuth 2.0 only; the CLI refuses them before sending anything |
| `bookmarks` | Listed for OAuth 1.0a in the spec, but the guides document OAuth 2.0 PKCE and the `bookmark.read` scope is not covered by OAuth 1.0a permissions: expect a refusal, which the CLI reports explicitly |

**Deadline:** X retires OAuth 1.0a user authentication on **2027-01-31** ("Migrate from OAuth
1.0a to OAuth 2.0" on docs.x.com). After that date every OAuth 1.0a request fails; the server
agent then needs OAuth 2.0 with a writable place for the rotating refresh token.

## Troubleshooting

| Symptom | Cause / fix |
|---|---|
| `X_CLIENT_ID is missing` | Step 3 not done |
| `x.mjs auth` shows `oauth1Incomplete` | One of the four OAuth 1.0a variables is missing — the CLI fell back to OAuth 2.0 |
| `cannot be refreshed: ... process environment` / `not writable` | OAuth 2.0 tokens come from read-only storage: use the OAuth 1.0a mode (section 6) |
| `HTTP 401 with OAuth 1.0a keys` | Keys regenerated, revoked or mistyped — copy the current four from Keys and tokens |
| `HTTP 403` on DMs in OAuth 1.0a mode | Access Token generated before the permission was set to Read and write and Direct message — regenerate it |
| Consent page says redirect URI mismatch | The callback in the app must be exactly `http://127.0.0.1:8765/callback` |
| `HTTP 403` on an endpoint | The plan does not include it, or the app lacks the permission/scope — fix in the portal, then re-run `authorize.mjs` |
| `HTTP 401` after refresh | Refresh token revoked or expired — re-run `authorize.mjs` |
| `Rate limited` | Wait until the reset time printed in `resetAt` |
| Port 8765 already used | Free the port; if changed in the script, change the callback URI in the app too |
