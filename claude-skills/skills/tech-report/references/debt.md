# Tech Debt Inventory

How to surface, age, and score the TODO/FIXME/HACK backlog.

## Scope

Counts and ages three markers in tracked source files:

| Marker  | Convention         |
| ------- | ------------------ |
| `TODO`  | Known work deferred |
| `FIXME` | Known defect, deferred fix |
| `HACK`  | Intentional shortcut |

Age is computed via `git blame --porcelain` — the line's last-modified
commit date is the debt's "age." This overcounts: if a TODO was moved
one line up in a refactor, its blame date resets. Treat the counts as
a directional signal, not a precise audit.

## How to run

```bash
bash scripts/debt.sh                          # fresh
bash scripts/debt.sh --snapshot /tmp/*.json   # reuse snapshot
```

## Output schema

```json
{
  "summary": {
    "todo": 23,
    "fixme": 7,
    "hack": 2,
    "total": 32,
    "oldestDate": "2025-08-12"
  },
  "byFile": [
    { "file": "src/legacy/processor.ts", "count": 8, "oldest": "2025-08-12" }
  ],
  "staleTodos": [
    { "file": "src/legacy/processor.ts", "line": 142, "kind": "TODO",
      "text": "handle empty payload", "age": 251 }
  ],
  "debtScore": 32,
  "previousDebtScore": 28,
  "debtScoreDelta": 4
}
```

## Debt score

Simple additive score:

```
score = Σ (kind_weight × age_bucket)
```

| Marker | Weight |
| ------ | ------ |
| TODO   | 1      |
| FIXME  | 2      |
| HACK   | 3      |

| Age bucket | Multiplier |
| ---------- | ---------- |
| < 30 days  | 1          |
| 30–90 days | 2          |
| > 90 days  | 4          |

A `TODO` less than 30 days old counts as 1. A `HACK` older than 90
days counts as 12. The score has no absolute meaning — compare to
the previous snapshot via `debtScoreDelta`.

## How to interpret

- **`staleTodos[]` > 5** (items > 90 days) → silence-breaker. List
  the oldest 3 with file + line.
- **`debtScoreDelta / previousDebtScore > 0.1`** → silence-breaker.
  The team is accumulating debt faster than it's retiring it.
- **`byFile[]` top entry has disproportionate count** (> 20% of
  total) → candidate for a focused refactor.

## What NOT to do

- Don't auto-resolve TODOs by editing them out. Reporting only.
- Don't treat the score as a KPI in isolation — it's only
  meaningful as a delta against previous ticks.
- Don't count markers in generated or vendored files — `.techignore`
  and `.gitignore` apply.
