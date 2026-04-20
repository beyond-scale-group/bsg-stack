# Code Quality Signals

How to surface structural smells without running a full linter.

## Scope

Three cheap heuristics:

1. **File size outliers** — any tracked source file > 500 lines.
2. **Function-count outliers** — any file with > 20 top-level
   function-like declarations (grep-based, language-aware
   approximation).
3. **Circular imports** — JS/TS only in the MVP. Walks `import` /
   `require` statements and detects cycles. Non-JS repos report
   `circularDeps: []`.

These are **not** replacements for a real linter (ESLint, ruff,
scalafix, clippy). They're cheap signals the `@tech-lead` agent
surfaces when nothing else fires.

## How to run

```bash
bash scripts/quality.sh                          # fresh
bash scripts/quality.sh --snapshot /tmp/*.json   # reuse snapshot
```

## Output schema

```json
{
  "summary": {
    "filesAnalyzed": 145,
    "oversized": 4,
    "functionDense": 2,
    "circularDeps": 0
  },
  "oversizedFiles": [
    { "file": "src/legacy/processor.ts", "lines": 823, "functions": 34 }
  ],
  "circularDeps": []
}
```

## Function heuristic

Language-approximate patterns:

| Language      | Regex                                          |
| ------------- | ---------------------------------------------- |
| JS / TS       | `^\s*(export\s+)?(async\s+)?function\s+\w+`    |
| JS / TS class | `^\s*(public|private|protected)?\s*\w+\s*\(`   |
| Python        | `^\s*(async\s+)?def\s+\w+`                     |
| Go            | `^func\s+(\([^)]+\)\s+)?\w+`                   |
| Rust          | `^\s*pub(\([^)]+\))?\s*(async\s+)?fn\s+\w+`    |
| Scala         | `^\s*(def|private\s+def|protected\s+def)\s+\w+` |

Functions are never counted precisely (grep can't parse ASTs) — the
numbers are directional.

## How to interpret

- **`oversizedFiles[]` non-empty** → silence-breaker. List the
  largest 3 with a one-line recommendation.
- **`circularDeps[]` non-empty** → silence-breaker (hard one; cycles
  almost never have a legitimate reason in application code).
- **`functionDense` stable** → healthy; no alert.
- **`summary.filesAnalyzed == 0`** → scan failed or repo is empty;
  investigate.

## What NOT to do

- Don't promote file-length findings without context — a
  configuration file can legitimately be 800 lines.
- Don't use the function count as a quality metric in isolation.
- Don't attempt a real cyclomatic complexity calculation — the
  grep-based approach is intentionally coarse. Escalate to a
  dedicated tool if the user wants precision.
