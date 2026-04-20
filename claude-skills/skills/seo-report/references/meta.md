# Meta Tag Auditing

Every indexable page should carry a unique `<title>`, meta
description, canonical URL, and a sensible Open Graph set.

## What `meta.sh` checks

| Tag                              | Required         | Check                                    |
| -------------------------------- | ---------------- | ---------------------------------------- |
| `<title>`                        | Always           | Non-empty, ≤ 70 characters                |
| `<meta name="description">`      | Always           | Non-empty, 50–160 characters              |
| `<link rel="canonical">`         | If not SPA-only  | Present, absolute URL                     |
| `<meta property="og:title">`     | For shareable pages | Present                                |
| `<meta property="og:description">`| For shareable pages | Present                                |
| `<meta property="og:image">`     | For shareable pages | Present                                |

SPA entry-points without static meta are flagged with
`kind: "dynamic"` and excluded from the silence-breaker — the
agent surfaces them in the narrative so a human can verify that
client-side meta injection actually runs.

## How to run

```bash
bash scripts/meta.sh                          # fresh
bash scripts/meta.sh --snapshot /tmp/*.json   # reuse snapshot
```

## Output schema

```json
{
  "summary": {
    "pagesScanned": 42,
    "missingTitle": 1,
    "missingDescription": 3,
    "missingCanonical": 4,
    "ogCoverage": { "full": 30, "partial": 8, "none": 4 }
  },
  "missingTitle": [
    { "page": "src/pages/legal/dpa.tsx", "kind": "static" }
  ],
  "missingDescription": [ ... ],
  "missingCanonical": [ ... ],
  "ogPartial": [
    { "page": "src/pages/blog/[slug].tsx", "have": ["title"], "missing": ["description", "image"] }
  ]
}
```

## How to interpret

- **`missingTitle[]` non-empty** → silence-breaker. A title is
  non-negotiable for indexable pages.
- **`missingDescription[]` non-empty** → silence-breaker, same logic.
- **`missingCanonical[]` non-empty** → soft; surface in the report
  but don't alert unless duplicate-content risk is known.
- **`ogPartial[]`** → soft; note in the report. Full OG coverage is
  a lift, not a blocker.

## Pitfalls

- **Template inheritance.** If meta is set in a parent template and
  a child page inherits, the script may flag the child incorrectly.
  Use `.seoignore` with a `pattern: missingDescription in <path>`
  directive to suppress known-fine cases.
- **i18n variants.** A page with multiple locale variants should
  have a `hreflang` set. Out of scope for the MVP; flag manually.

## What NOT to do

- Don't auto-write meta tags. Reporting only.
- Don't cite title or description length without verifying the
  template's runtime-rendered output — SSR pipelines can shorten
  or expand content.
