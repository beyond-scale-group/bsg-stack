# Structured Data (schema.org / JSON-LD)

## Scope

The skill counts pages that ship a JSON-LD `<script>` block, groups
by `@type`, and flags obvious mismatches (e.g. a blog post page
with no `BlogPosting` type).

The MVP does not validate JSON-LD against the full schema.org
spec. For that, use Google's Rich Results Test on the rendered page
— out of scope for this repo-at-rest auditor.

## How `collect.sh` extracts structured data

Regex-matches `<script type="application/ld+json">...</script>`
blocks in each template, parses the JSON, and records the `@type`
field.

## Canonical `@type` by page category

Heuristic mapping (edit `seo/SCHEMA_HINTS.md` to override):

| Page path pattern            | Expected `@type`            |
| ---------------------------- | --------------------------- |
| `/` (homepage)               | `Organization` + `WebSite`  |
| `/blog/*` or `/posts/*`      | `BlogPosting` / `Article`   |
| `/product/*` or `/pricing`   | `Product` + `Offer`         |
| `/faq` or `**/faq.*`         | `FAQPage`                   |
| `/events/*`                  | `Event`                     |
| `/team`, `/about`            | `Organization` / `AboutPage` |
| `/docs/*`                    | `TechArticle`               |

## Output schema (composed in `generate-report.sh`)

```json
{
  "summary": {
    "pagesWithStructuredData": 5,
    "pagesTotal": 42,
    "coverage": 0.12
  },
  "byType": {
    "Organization": 1,
    "BlogPosting": 3,
    "FAQPage": 1
  },
  "missingExpected": [
    { "page": "/pricing", "expected": "Product", "present": [] },
    { "page": "/blog/first-post", "expected": "BlogPosting", "present": [] }
  ]
}
```

## How to interpret

- **`missingExpected[]`** → **not** a silence-breaker in the MVP —
  the category mapping is heuristic and will false-positive. Surface
  in the narrative so the user can decide.
- **Coverage trend** (compare tick-over-tick) → healthy signal if
  it trends up.

## What NOT to do

- Don't auto-generate JSON-LD. Even a valid block with incorrect
  `@type` is worse than nothing (rich-result penalties).
- Don't cite specific schema.org fields without reading the actual
  JSON-LD — regex-level extraction only captures `@type`.
- Don't treat JSON-LD validity as SEO certification. This is one
  signal among many.
