# CHANGELOG gaps

How `changelog.sh` compares git tags with CHANGELOG headings.

## Scope

Extracts version-like tokens from every heading line (`#`, `##`,
`###`) in `CHANGELOG.md` — anything matching the semver-ish regex
`v?[0-9]+\.[0-9]+\.[0-9]+[a-zA-Z0-9.-]*`. Normalizes by stripping a
leading `v`. Compares against the normalized set of `git tag --list`.

Any tag whose normalized form is not in the logged set is reported in
`missingTags[]` (with the original tag string preserved).

## How to run

```bash
bash scripts/changelog.sh
bash scripts/changelog.sh --snapshot /tmp/docs-snap.json
```

## Output schema

```json
{
  "summary": {
    "changelogFound": true,
    "loggedVersions": 12,
    "missingTags": 2
  },
  "changelogFound": true,
  "changelogPath": "CHANGELOG.md",
  "loggedVersions": ["0.1.0", "0.2.0", "1.0.0"],
  "missingTags": ["v1.1.0", "v1.2.0"]
}
```

When the repo has no CHANGELOG, `changelogFound` is `false` and the
full tag list is returned as `missingTags` (the gap is "everything").

## Silence-breaker

Any missing tag → break silence. Each missing tag is eligible for
`audit-to-issue`: the agent appends a stub under the canonical
"Unreleased" or tag heading, but never invents commit-level narrative.
