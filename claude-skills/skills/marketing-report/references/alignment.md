# Feature-Marketing Alignment

How to check "what shipped" vs "what marketing says shipped."

## Sources

| Side        | Signal                                                                     |
| ----------- | -------------------------------------------------------------------------- |
| Shipped     | `gh release list` (last 90 days, minor/major only) + closed milestones     |
| Marketed    | `marketing/` directory, top-level `README.md`, `docs/`, `public/` landing files |

"Shipped" ignores patch releases by default — they're rarely
campaign-worthy.

## Matching heuristic

For each shipped feature (title of a release or milestone), look for
a marketing mention in the Marketed sources. A match is a
case-insensitive substring of the release/milestone title that
appears in at least one of:

1. A file under `marketing/`.
2. A top-level `README.md` section heading.
3. A file under `docs/` whose path contains `landing`, `pricing`,
   `features`, or `product`.

Shipped features with no match go to `unmarketed[]`. Marketed
claims (keywords extracted from `marketing/` headings / READMEs) that
don't correspond to any shipped release go to `unshipped[]` — the
"we claim it but did we ship it?" check.

## How to run

```bash
bash scripts/alignment.sh                          # fresh
bash scripts/alignment.sh --snapshot /tmp/*.json   # reuse snapshot
```

## Output schema

```json
{
  "summary": {
    "shippedCount": 8,
    "marketedCount": 12,
    "unmarketed": 1,
    "unshipped": 2,
    "aligned": 7
  },
  "aligned": [
    { "feature": "OAuth2 login", "release": "v2.3.0", "releasedAt": "2026-04-10",
      "marketedIn": ["README.md", "marketing/landing-auth.md"] }
  ],
  "unmarketed": [
    { "feature": "Webhook retry", "release": "v2.4.0", "releasedAt": "2026-04-18" }
  ],
  "unshipped": [
    { "claim": "AI assistant", "foundIn": ["README.md"] }
  ]
}
```

## How to interpret

- **`unmarketed[]` non-empty** → silence-breaker. Suggest generating
  a campaign brief via `brief.sh`.
- **`unshipped[]` non-empty** → silence-breaker. Either the feature
  shipped under a different name (update the marketing copy) or
  it's premature marketing (hold the claim until release).
- **`aligned[]` matches** — narrative only.

## Pitfalls

- **Release names don't describe features.** A tag like "v2.4.0"
  with no milestone title gives the matcher nothing to work with.
  The script falls back to the milestone list; if that's also empty,
  the release is classified `unknown` and skipped.
- **Marketing lives off-repo.** If your landing page is in a CMS,
  `alignment.sh` has nothing to match against. Document this in
  the report narrative and recommend committing a snapshot
  (`marketing/copy-snapshot.md`) on each release.
- **Abbreviations.** "OAuth2" won't match "oauth"; the heuristic
  is substring, not semantic.

## What NOT to do

- Don't auto-write marketing copy for `unmarketed` features. Only
  `brief.sh` generates brief *stubs*, and even those require human
  review.
- Don't flag every patch release. The default 90-day window and
  minor/major filter exist specifically to reduce noise.
