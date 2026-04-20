# Architecture Decision Records (ADR) Management

How to index ADRs and detect decisions that shipped without one.

## Scope

- **Index** every ADR under `adr/`, `docs/adr/`, or `architecture/`
  (first existing dir wins).
- **Detect gaps**: top-level dependencies added to `package.json` or
  `requirements.txt` in the last 30 days that don't have a matching
  ADR.

The gap detector is deliberately narrow — false positives (a library
was swapped for an equivalent) are more costly than false negatives
(a real decision slipped through). A dependency is flagged only when
it's a *new* top-level entry (not a version bump).

## How to run

```bash
bash scripts/adr.sh                          # fresh
bash scripts/adr.sh --snapshot /tmp/*.json   # reuse snapshot
```

## Output schema

```json
{
  "dir": "adr/",
  "index": [
    { "id": "0001", "title": "Use Clever Cloud for hosting", "status": "accepted", "date": "2025-06-10", "path": "adr/0001-clever-cloud.md" }
  ],
  "undocumentedDecisions": [
    { "dependency": "prisma", "ecosystem": "npm", "addedOn": "2026-04-03",
      "addedInCommit": "abc1234", "reason": "new top-level dep in package.json" }
  ]
}
```

## Conventions

ADR files are expected to follow either form:

1. **MADR / Nygard** — filename `NNNN-title.md`, frontmatter with
   `status:` and `date:`.
2. **Anything with a `# ADR-NNNN: ...` H1** — the script extracts the
   ID from the heading if frontmatter is missing.

If neither convention is present, the file is still listed in
`index` but with `title: "?"` and `status: "unknown"`.

## How to interpret

- **`undocumentedDecisions[]` non-empty** → silence-breaker. List
  each with a suggested ADR ID (next integer after the highest
  existing one).
- **`dir: null`** → repo has no ADR directory yet. Surface once, on
  the first tick, with a suggestion to create `adr/0001-start.md`.
  After that, silent (the first-tick rule).

## What NOT to do

- Don't auto-create ADR stubs. Creating an ADR is a human decision —
  it's the whole point.
- Don't treat every new library as a gap. The 30-day window and
  "top-level only" filter exist specifically to avoid noise.
- Don't infer the content of an undocumented decision. Flag the
  gap; the human writes the ADR.
