# Technical SEO Audit

Sitemap + robots + canonical consistency checks.

## What `technical.sh` checks

1. **sitemap.xml presence** at the repo root or under `public/`,
   `static/`, `dist/`.
2. **sitemap coverage** — every page detected by `collect.sh`
   should appear in the sitemap (if one exists).
3. **robots.txt presence** — same discovery paths.
4. **robots.txt sanity** — not blanket-disallowing `/`.
5. **Canonical URL consistency** — all `<link rel="canonical">`
   values share a consistent host.

## How to run

```bash
bash scripts/technical.sh                          # fresh
bash scripts/technical.sh --snapshot /tmp/*.json   # reuse snapshot
```

## Output schema

```json
{
  "sitemapFound": true,
  "sitemapPath": "public/sitemap.xml",
  "sitemapUrlCount": 38,
  "robotsFound": true,
  "robotsPath": "public/robots.txt",
  "robotsBlanketDisallow": false,
  "pagesNotInSitemap": [
    { "page": "/legal/dpa", "path": "src/pages/legal/dpa.tsx" }
  ],
  "canonicalHosts": [
    { "host": "https://example.com", "count": 38 },
    { "host": "https://staging.example.com", "count": 1 }
  ],
  "canonicalInconsistent": true
}
```

## How to interpret

- **`sitemapFound: false`** → silence-breaker. Even a minimal
  sitemap helps crawlers.
- **`robotsFound: false`** → silence-breaker. Default to
  `User-agent: *\nAllow: /` if the site should be indexed.
- **`robotsBlanketDisallow: true`** → critical silence-breaker.
  Someone accidentally disallowed everything.
- **`pagesNotInSitemap[] length > 3`** → silence-breaker. New pages
  ship without sitemap updates; suggest regenerating.
- **`canonicalInconsistent: true`** → surface in report; likely a
  staging URL leaked into production config.

## Pitfalls

- **Generated sitemaps.** Many repos generate `sitemap.xml` at
  build time. If the file isn't committed, `sitemapFound` will be
  `false` — add a note in the report explaining how to check the
  build output directly (e.g. `dist/sitemap.xml`).
- **Wildcard canonical hosts.** Some frameworks template
  canonical URLs with the production host at build time; the
  template source may show a placeholder like `{{SITE_URL}}`.
  Skip canonical consistency when the host looks like a
  template literal.

## What NOT to do

- Don't auto-generate or auto-edit `sitemap.xml` / `robots.txt`.
- Don't hit `https://example.com/sitemap.xml` to validate against
  the live site — out of scope for this repo-at-rest auditor.
