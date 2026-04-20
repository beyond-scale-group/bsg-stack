# Dependency Health

How to run and interpret the dependency-lag scan.

## Scope

Two complementary signals:

1. **Version lag** from `npm outdated --json` / `pip list --outdated
   --format=json` — per-package current vs. latest, bucketed by major
   / minor / patch gap.
2. **Security alerts** from `gh api /repos/.../dependabot/alerts` —
   cross-referenced with the lag data to prioritize major upgrades
   that also close known vulnerabilities.

Unlike `/security-report/deps.sh` (which focuses on CVEs), this
reporter focuses on **upgrade strategy**: what should we upgrade
next, at what risk.

## How to run

```bash
bash scripts/deps.sh                          # fresh
bash scripts/deps.sh --snapshot /tmp/*.json   # reuse snapshot
```

## Output schema

```json
{
  "summary": {
    "total": 60,
    "upToDate": 45,
    "patchBehind": 3,
    "minorBehind": 9,
    "majorBehind": 3
  },
  "findings": [
    {
      "package": "react",
      "current": "17.0.2",
      "latest": "19.1.0",
      "gap": "major",
      "majorsBehind": 2,
      "hasAlert": false,
      "ecosystem": "npm"
    }
  ],
  "majorBehind": [
    { "package": "react", "majorsBehind": 2, "current": "17.0.2", "latest": "19.1.0" }
  ]
}
```

## How to interpret

- **`majorBehind[]` non-empty** (majorsBehind >= 2) → silence-breaker.
  These are the most expensive to defer.
- **`minorBehind` count stable** is healthy — churn without drift.
- **`findings[].hasAlert == true`** → cross-reference with
  `@security tick` output; prioritize upgrades that close CVEs.

## Common pitfalls

- **`npm outdated` returns non-zero** when there *are* outdated
  packages. `collect.sh` swallows that — it's not an error.
- **Package pinned by policy** (e.g. `"react": "17.x"` intentionally)
  still shows as major-behind. Add the package to `.techignore` with
  a `reason:` comment to suppress the alert.
- **Private registries** — `npm outdated` reads the same registry as
  install. If `.npmrc` is missing, packages may be reported as
  "latest unknown" — the reporter tags them `gap: "unknown"`.

## What NOT to do

- Don't auto-upgrade. Reporting only.
- Don't cite "breaking changes in react 19" unless you've actually
  read the upstream changelog — the reporter has no awareness of
  breaking-change content.
