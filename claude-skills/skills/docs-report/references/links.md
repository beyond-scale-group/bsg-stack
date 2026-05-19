# Broken links

How `links.sh` detects dead targets in tracked markdown.

## Scope

Every link extracted by `collect.sh` from a tracked `*.md` file is
inspected. A link is "broken" when:

1. Its target is a **relative path** (not `http://`, `https://`,
   `mailto:`, `tel:`).
2. The resolved target — interpreted relative to the source file's
   directory, or relative to the repo root for `/`-prefixed paths —
   does **not** exist on disk.

Fragments (`#anchor`) and query strings (`?ref=x`) are stripped before
the existence check. Anchors inside an existing file are *not*
verified — that would require parsing the target's headings.

## How to run

```bash
bash scripts/links.sh                              # fresh snapshot
bash scripts/links.sh --snapshot /tmp/docs-snap.json  # reuse
```

## Output schema

```json
{
  "summary": { "brokenLinks": 3 },
  "brokenLinks": [
    { "source": "README.md", "target": "./docs/quickstart.md" },
    { "source": "docs/architecture.md", "target": "../moved-elsewhere.md" }
  ]
}
```

## Silence-breaker

`brokenLinks[]` non-empty → break silence. Each broken link is a
candidate for `audit-to-issue` if and only if a 1:1 replacement
target exists in the current tree (same basename, different path).
The agent's `auto-implements` clause guards this.
