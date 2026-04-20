# Positioning Audit

How the skill checks that the narrative bible's positioning still
matches the product.

## Scope

Narrow by design — positioning drift is qualitative and usually
requires human judgement. The skill surfaces two objective signals:

1. **Feature anchors that no longer exist.** If the bible's
   positioning lists "webhook retry" as a differentiator but the
   corresponding code / docs / release no longer mention it, the
   anchor is stale.
2. **Category or target-audience language drift.** If the bible
   says "Category: API tooling" but every landing asset calls it
   a "developer platform," there's a mismatch.

Deeper positioning work (message testing, persona research) is
out of scope.

## Output schema (composed in `alignment.sh`)

```json
{
  "positioning": {
    "category": "API tooling",
    "targetAudience": "B2B developers shipping integrations",
    "differentiators": ["Webhook retry", "API versioning policy"],
    "featureAnchors": ["webhook retry", "api versioning"]
  },
  "stalePositioning": [
    {
      "anchor": "webhook retry",
      "reason": "no release or doc in the last 30 days references this phrase"
    }
  ],
  "categoryMentionInAssets": 0,
  "audienceMentionInAssets": 2
}
```

## How to interpret

- **`stalePositioning[]` non-empty** → silence-breaker. An anchor
  the bible relies on is invisible in the current product surface.
- **`categoryMentionInAssets == 0`** → surface in the narrative.
  The category language is theoretical if no asset uses it.
- **`differentiators` count vs `featureAnchors` count mismatch** →
  the bible lists more differentiators than concrete anchors; flag
  for review.

## Hard rules

1. **Substring matching only.** "API versioning" matches "API
   versioning" — it won't match "we version the API." Keep bible
   anchors concrete.
2. **Don't judge the positioning.** Surface what the bible claims
   vs. what the assets say. Whether the positioning is correct is
   a human call.
3. **Case-insensitive, whitespace-insensitive.** Minor formatting
   differences shouldn't trigger staleness.

## What NOT to do

- Don't auto-edit positioning. It's the highest-level identity
  claim the company makes; software doesn't get to rewrite it.
- Don't infer new positioning from the assets. If the product has
  evolved past the bible, surface the gap — don't draft replacement
  positioning.
- Don't compare positioning across repos. Each repo has its own
  audience and scope.
