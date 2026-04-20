# Security Headers & Config Hardening

How to audit HTTP security headers and related config for web-serving
repos.

## Scope

The check only runs when the repo looks like it serves HTTP — detected
via any of:

- `nginx.conf` / `**/nginx/*.conf`
- `apache2.conf` / `httpd.conf` / `.htaccess`
- `app.js` / `server.js` / `main.ts` importing `express`, `fastify`, `koa`, `hono`
- `wsgi.py` / `asgi.py` / Django `settings.py` / Flask `app.py`
- `Caddyfile`
- `vercel.json` / `netlify.toml` (headers stanza)
- Clever Cloud `clevercloud.json` with a `http` section

Non-HTTP repos (libraries, CLI tools) return `{"applicable": false}`
and the agent skips this section in the report.

## Required headers

Default enforcement list (codified in `scripts/headers.sh`):

| Header                         | Severity   | Notes                                          |
| ------------------------------ | ---------- | ---------------------------------------------- |
| `Content-Security-Policy`      | critical   | Fail if absent or set to `*` / `unsafe-inline` unconditionally |
| `Strict-Transport-Security`    | critical   | Fail if absent on HTTPS-serving configs; `max-age` ≥ 31536000 |
| `X-Content-Type-Options`       | high       | Must be `nosniff`                              |
| `X-Frame-Options`              | high       | Must be `DENY` or `SAMEORIGIN` (unless CSP `frame-ancestors` present) |
| `Referrer-Policy`              | moderate   | Must be set to a non-`unsafe-url` value        |
| `Permissions-Policy`           | moderate   | Must restrict geolocation/camera/microphone by default |

## How to run

```bash
bash scripts/headers.sh                          # fresh
bash scripts/headers.sh --snapshot /tmp/*.json   # snapshot reuse
```

## Output schema

```json
{
  "applicable": true,
  "serverKind": "express",
  "found": ["X-Content-Type-Options", "X-Frame-Options"],
  "missing": [
    { "header": "Content-Security-Policy", "severity": "critical" },
    { "header": "Strict-Transport-Security", "severity": "critical" }
  ],
  "weak": [
    { "header": "Permissions-Policy", "severity": "moderate",
      "reason": "allows microphone by default" }
  ]
}
```

## How to interpret

- **`missing[]` contains any critical header** → silence-breaker.
- **`weak[]` non-empty** → surface in the report; not a silence-breaker.
- **`applicable == false`** → skip the section entirely. Do not
  fabricate "N/A" entries for a CLI-only repo.

## What NOT to do

- Don't auto-write a CSP. Generating a correct CSP requires knowing
  every inline script and third-party origin the site loads — out
  of scope for the audit.
- Don't trust reverse-proxy-only headers without verifying the
  upstream config is reachable. If the repo only contains app code,
  note that headers may be set at the proxy layer (`serverKind:
  "unknown"` is legitimate).
