# Internal Link Analysis

## What `links.sh` does

Walks the adjacency list built by `collect.sh` (pages → linked
pages via `<a href>` in templates) to compute:

1. **Orphan pages** — pages with zero inbound internal links.
2. **Broken links** — `<a href>` targets that don't resolve to a
   page known in the snapshot.
3. **Per-page inbound count** — surfaced in the report to highlight
   under-linked content.

External links (`http://`, `https://`, `mailto:`, `tel:`) are
excluded.

## How to run

```bash
bash scripts/links.sh                          # fresh
bash scripts/links.sh --snapshot /tmp/*.json   # reuse snapshot
```

## Output schema

```json
{
  "summary": {
    "totalPages": 42,
    "orphanCount": 2,
    "brokenCount": 1,
    "avgInboundLinks": 3.4
  },
  "orphanPages": [
    { "page": "/docs/advanced-config", "path": "src/pages/docs/advanced-config.tsx" }
  ],
  "brokenLinks": [
    { "from": "src/pages/pricing.tsx", "target": "/features/compare-plans",
      "line": 47 }
  ],
  "underLinked": [
    { "page": "/docs/faq", "inbound": 1 }
  ]
}
```

`underLinked[]` is any page with ≤ 1 inbound link — informational,
not a silence-breaker.

## How to interpret

- **`orphanPages[]` non-empty** → silence-breaker. An orphan is
  invisible to the site's own navigation; it will be hard to
  discover through search too.
- **`brokenLinks[]` non-empty** → silence-breaker. Broken internal
  links waste crawl budget and frustrate users.
- **`avgInboundLinks < 2`** → surface; may indicate flat site
  architecture.

## Route-resolution heuristic

- **Next.js (`src/pages/` or `app/`)** — filenames become routes
  (`pages/pricing.tsx` → `/pricing`). Dynamic segments
  (`[slug].tsx`) resolve as-is.
- **Astro / Nuxt / SvelteKit** — similar file-system routing.
- **Plain HTML** — `<a href>` targets are matched against file
  paths verbatim.
- **Vue Router config** — not currently parsed. Flag as
  "route table not parsed; link resolution approximate" and skip
  broken-link detection.

## What NOT to do

- Don't fetch external URLs to check them — out of scope.
- Don't auto-add links to orphan pages. Reporting only.
- Don't resolve `#anchor` links as broken — they're scoped to
  the page itself.
