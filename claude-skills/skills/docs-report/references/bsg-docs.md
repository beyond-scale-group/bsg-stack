# .bsg/ doc freshness

How `bsg-docs.sh` audits cross-references and staleness in `.bsg/`
flat docs.

## Scope

Walks `.bsg/*.md` — explicitly **excluding** `.bsg/adr/*.md`, which is
owned by `tech-report` and read-only here. For each doc, two checks:

1. **Dead references.** Extract backtick-wrapped tokens that look
   like file paths (contain `/` or end in a recognized extension:
   `.md`, `.sh`, `.py`, `.js`, `.ts`, `.json`, `.yml`, `.yaml`,
   `.toml`). Check each for existence. Tokens that don't resolve are
   reported.
2. **Stale since latest tag.** If the doc's most recent commit
   predates the latest annotated git tag, it's flagged as
   "unedited since latest release."

## How to run

```bash
bash scripts/bsg-docs.sh
bash scripts/bsg-docs.sh --snapshot /tmp/docs-snap.json
```

## Output schema

```json
{
  "summary": {
    "deadReferences": 1,
    "staleSinceBump": 2,
    "contradictions": 0
  },
  "deadReferences": [
    { "doc": ".bsg/PLAN.md", "reference": "old/path/file.md" }
  ],
  "staleSinceBump": [
    { "doc": ".bsg/NARRATIVE.md", "reason": "unedited since latest tag" }
  ],
  "contradictions": []
}
```

## Contradictions — current state

`contradictions[]` is reserved for future iterations. Detecting "doc
A says X, doc B says not-X" requires semantic comparison beyond what
bash + jq does well. For now the field is always an empty array;
contradictions surface only when a human notices them and files an
issue with `label:docs-keeper`.

## Silence-breaker

`deadReferences[]` non-empty → break silence and queue for the
pilot. `staleSinceBump[]` is informational only — a doc can be
correct and intentionally stable.
