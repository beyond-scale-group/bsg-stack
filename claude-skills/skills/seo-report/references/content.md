# Content Coverage

How to check that every target keyword in `seo/KEYWORDS.md` has a
matching page.

## `seo/KEYWORDS.md` format

Simple markdown list — one keyword per bullet. Optional category
sections with H2 headers:

```markdown
# Target Keywords

## Product
- API authentication
- webhook security
- rate limiting

## Marketing
- pricing plans
- enterprise features

## Documentation
- migration guide
- quickstart
```

If the file doesn't exist, `content.sh` returns
`{"keywordsFound": false}` and the reporter skips the section.

## How to run

```bash
bash scripts/content.sh                          # fresh
bash scripts/content.sh --snapshot /tmp/*.json   # reuse snapshot
```

## Output schema

```json
{
  "keywordsFound": true,
  "summary": {
    "total": 8,
    "covered": 6,
    "uncovered": 2
  },
  "coverage": [
    { "keyword": "API authentication", "status": "covered", "page": "/docs/auth" },
    { "keyword": "pricing plans", "status": "uncovered" }
  ],
  "uncoveredKeywords": [
    { "keyword": "pricing plans" }
  ]
}
```

## Coverage heuristic

A keyword is **covered** when at least one page has the keyword in
one of:

1. The `<title>` tag (case-insensitive substring).
2. The first H1 (`# Keyword` in Markdown, `<h1>Keyword</h1>` in HTML).
3. The meta description.

Matching is substring + case-insensitive. A keyword "webhook" matches
a title "Webhook retry logic."

## How to interpret

- **`uncoveredKeywords[]` non-empty** → silence-breaker. Surface the
  gap list; the marketing lead decides whether to plan content.
- **Stable coverage tick-over-tick** → healthy; no alert.

## Pitfalls

- **Multi-word keywords** are matched as full substrings. "webhook
  retry" doesn't match "webhook" alone — add each as a separate
  entry if you want separate matches.
- **Page aliases** — if `/pricing` and `/plans` both serve the same
  content, the keyword is marked covered by the first match.
- **Singular vs plural** — not normalized. Add both if needed.

## What NOT to do

- Don't auto-create pages for uncovered keywords. Reporting only.
- Don't suggest page copy — that's a content-team decision, not the
  agent's.
- Don't fetch external keyword-difficulty metrics. Out of scope.
