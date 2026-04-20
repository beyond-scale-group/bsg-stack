# Talking Point Generation

How to auto-draft a talking-point file for a release that doesn't
have one yet.

## Inputs

For each release returned by `gh release list`:

- `tag`, `name`, `publishedAt`
- `body` (release notes)
- The voice target from the narrative bible (`voice.md` scoring)
- The list of existing files under `brand/talking-points/`

If a talking-points file already exists for the release (by tag in
the filename or frontmatter), the release is considered "narrated"
and skipped.

## Output location

```
brand/talking-points/YYYY-MM-DD-<tag>-<slug>.md
```

## Template

```markdown
---
release: v2.4.0
publishedAt: 2026-04-18T15:00:00Z
status: draft
---

# Talking Points — v2.4.0 Webhook Retry

## Headline
_(One line the team leads with in any announcement. Lead with user
benefit, not technical mechanism.)_

## Core message
_(One paragraph the team uses verbatim in changelogs, blog openers,
support replies.)_

## Key quotes
- _(Quote 1, for founder / CEO)_
- _(Quote 2, for engineering lead)_

## Voice notes
- Tone target: 7.0 (confident, accessible)
- Banned terms in this context: _(inherit from bible)_
- Preferred framing: user value first, mechanism second

## Distribution
- [ ] Changelog entry
- [ ] Release blog post
- [ ] Landing-page update (if applicable)
- [ ] Social post(s)

---

*Auto-drafted by @storytelling on 2026-04-20 from release v2.4.0
notes. Human review required before any asset ships.*
```

## How to run

```bash
# Plan only — no files written
bash scripts/talking-points.sh                          # fresh
bash scripts/talking-points.sh --snapshot /tmp/*.json

# Actually generate stubs
bash scripts/talking-points.sh --write
```

## Output schema

```json
{
  "plan": [
    { "release": "v2.4.0", "title": "Webhook Retry",
      "path": "brand/talking-points/2026-04-18-v2.4.0-webhook-retry.md" }
  ],
  "generated": [],
  "existing": [
    { "release": "v2.3.0", "path": "...", "status": "published" }
  ],
  "unnarratedReleases": [
    { "release": "v2.4.0", "daysSinceRelease": 2 }
  ]
}
```

## How to interpret

- **`unnarratedReleases[]` non-empty** → silence-breaker. The agent
  surfaces it; the user decides whether to run with `--write`.
- **`plan[]` is the same as `unnarratedReleases[]`** but keyed by
  the file path it would create. Shown in the report for visibility.

## What NOT to do

- **Don't fill in the placeholder prose.** Drafting structure is the
  ceiling; real quotes, framing, and voice decisions are human work.
- **Don't publish the draft anywhere.** The file lands in
  `brand/talking-points/` as a working file for the marketing team.
- **Don't auto-update `status: draft` to `published`** in
  subsequent ticks. Only a human can decide a draft is ready.
