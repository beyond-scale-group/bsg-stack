# PRD-003: Tech Lead Agent

**Status:** Draft
**Author:** Guillaume Badin
**Date:** 2026-04-20
**Priority:** P1 — Phase 2

---

## 1. Problem Statement

Technical debt, architecture decisions, and dependency health are managed
informally across BSG repositories. Architecture decisions are made in Slack
threads and forgotten. Dependency upgrades lag months behind, accumulating risk.
Tech debt is acknowledged in TODO comments but never triaged, prioritized, or
tracked against business impact. There is no single view that tells a tech lead
"here is the health of this codebase, and here is what needs attention."

## 2. Goal

Provide a Claude Code subagent that acts as a virtual CTO/senior developer,
maintaining architecture decision records, tracking dependency health, measuring
code quality signals, and surfacing tech debt — giving the tech lead an
actionable, data-driven view of codebase health on every `tick`.

## 3. Non-Goals

- **Making architecture decisions.** The agent records decisions and flags when
  they're missing; it does not choose between PostgreSQL and MongoDB.
- **Refactoring code.** The agent identifies debt; the developer remediates.
- **Replacing code review.** The agent provides static analysis signals, not
  PR-level review feedback.
- **Performance profiling.** Runtime performance is out of scope; this agent
  works on source code and metadata at rest.

## 4. User Stories

| # | As a… | I want to… | So that… |
|---|-------|-----------|----------|
| T1 | Tech lead | Run `@tech-lead tick` and see architecture health at a glance | I can decide where to invest engineering time |
| T2 | Developer | Run `@tech-lead deps` to see outdated and vulnerable dependencies | I can plan upgrade sprints |
| T3 | Tech lead | Maintain ADRs in `adr/` with an auto-generated index | New team members can understand past decisions |
| T4 | Developer | Run `@tech-lead debt` to see the tech debt backlog | I can attach debt items to sprint planning |
| T5 | Tech lead | Track code quality metrics over time | I can demonstrate improvement (or justify investment) |
| T6 | Developer | Run `@tech-lead complexity` to find the most complex files | I know what to break apart next |

## 5. Agent Design

### 5.1 Frontmatter

```yaml
---
name: tech-lead
description: >
  Senior developer / CTO agent for the current GitHub repository. Maintains
  architecture decision records, tracks dependency health, measures code
  quality signals (complexity, duplication, TODO density), and surfaces tech
  debt. Use when the user asks for "architecture review", "dependency health",
  "tech debt", "code quality", "ADR", "complexity analysis", "dette technique",
  "santé du code", or "revue d'architecture".
tools: Read, Glob, Grep, Bash, Write
model: sonnet
skills: [tech-report]
color: blue
output: chat
tick: >
  Run the full architecture health check (deps + quality + debt), produce
  a summary in chat with key findings. Land detailed report as
  tech/reports/YYYY-MM-DD-health.md for the record. Stay silent if all
  metrics are stable.
---
```

### 5.2 Routing Table

| User intent | Action |
|---|---|
| "architecture health", "tech health", "full review" | Run all scripts, produce full report |
| "dependencies", "outdated", "upgrades needed" | `tech-report` -> `references/deps.md` |
| "tech debt", "TODOs", "debt backlog" | `tech-report` -> `references/debt.md` |
| "complexity", "big files", "code smell" | `tech-report` -> `references/quality.md` |
| "ADR", "architecture decision", "why did we choose X" | `tech-report` -> `references/adr.md` |
| "refactor X", "upgrade dependency Y" | Decline; hand back to main agent |

### 5.3 Tick Action

**Steps:**

1. Run `collect.sh` to gather a tech health snapshot (`/tmp/tech-snap.json`):
   - `npm outdated --json` / `pip list --outdated --format=json`
   - `gh api /repos/{owner}/{repo}/dependabot/alerts` (if enabled)
   - File size and line count analysis (`wc -l` on source files)
   - TODO/FIXME/HACK grep with file and line context
   - Circular dependency detection (language-aware)
   - ADR inventory from `adr/` or `docs/adr/`

2. Run individual reporters:
   - `deps.sh --snapshot /tmp/tech-snap.json` — outdated + major version gaps
   - `quality.sh --snapshot /tmp/tech-snap.json` — file size outliers, complexity
   - `debt.sh --snapshot /tmp/tech-snap.json` — TODO inventory + age analysis
   - `adr.sh --snapshot /tmp/tech-snap.json` — ADR index + gap detection

3. `generate-report.sh` composes the full report:
   ```
   tech/reports/2026-04-20-health.md
   ```

4. Evaluate silence-breakers. If any fire, present the 3-bullet summary in
   chat. Otherwise, one-line receipt.

### 5.4 Silence-Breakers

| Signal | Source | Threshold |
|---|---|---|
| Dependency with major version lag | `deps.sh` -> `majorBehind[]` | Any dependency > 2 major versions behind |
| Circular dependency detected | `quality.sh` -> `circularDeps[]` | Non-empty |
| File exceeding complexity threshold | `quality.sh` -> `oversizedFiles[]` | Any file > 500 lines or > 20 functions |
| TODO/FIXME older than 90 days | `debt.sh` -> `staleTodos[]` | > 5 items |
| Architecture decision without ADR | `adr.sh` -> `undocumentedDecisions[]` | Non-empty (heuristic: new framework/library added without ADR) |
| Tech debt score regression | `debt.sh` -> `debtScore` vs previous | > 10% increase |

## 6. Skill Structure

```
skills/tech-report/
├── SKILL.md                    # Intent routing + hard rules
├── references/
│   ├── deps.md                 # Dependency health analysis guide
│   ├── debt.md                 # Tech debt tracking methodology
│   ├── quality.md              # Code quality metrics guide
│   └── adr.md                  # ADR management guide
└── scripts/
    ├── collect.sh              # Snapshot collector
    ├── deps.sh                 # Dependency health reporter
    ├── quality.sh              # Code quality metrics (size, complexity, duplication)
    ├── debt.sh                 # Tech debt inventory (TODOs, age, scoring)
    ├── adr.sh                  # ADR index generator + gap detector
    └── generate-report.sh      # Full report composer
```

## 7. Report Format

```markdown
# Tech Health — 2026-04-20

## Dependency Health
| Package | Current | Latest | Gap | Risk |
|---------|---------|--------|-----|------|
| react | 17.0.2 | 19.1.0 | 2 major | HIGH |
| express | 4.18.2 | 4.21.0 | minor | LOW |

**Summary:** 3 major-behind, 12 minor-behind, 45 up-to-date

## Code Quality
| Metric | Value | Trend |
|--------|-------|-------|
| Files > 500 lines | 4 | +1 |
| Avg file length | 142 lines | stable |
| Circular deps | 0 | stable |

### Largest Files
| File | Lines | Functions |
|------|-------|-----------|
| src/legacy/processor.ts | 823 | 34 |

## Tech Debt Inventory
| Category | Count | Oldest |
|----------|-------|--------|
| TODO | 23 | 2025-08-12 |
| FIXME | 7 | 2025-11-03 |
| HACK | 2 | 2026-01-15 |

**Debt score:** 32 (previous: 28, delta: +4)

## Architecture Decision Records
- 3 ADRs documented in `adr/`
- 1 gap detected: new ORM introduced without ADR
```

## 8. Dependencies

- `npm` or `pip` (language-detected per repo)
- `gh` CLI (authenticated)
- `jq` for JSON processing
- `git` for blame/age analysis on TODOs
- `wc`, `grep` (standard Unix tools)

## 9. Success Metrics

| Metric | Target |
|---|---|
| Major-version dependency lag detection | 100% of deps > 2 major behind flagged |
| TODO/FIXME staleness visibility | All items > 90 days surfaced |
| ADR coverage for major decisions | Teams create ADRs for flagged gaps within 2 weeks |
| Report generation time | < 15s for repos with < 1000 files |

## 10. Risks & Mitigations

| Risk | Mitigation |
|---|---|
| Language detection ambiguity (polyglot repos) | `collect.sh` scans for all known lockfiles, reports per-ecosystem |
| Circular dependency detection is language-specific | Start with JS/TS (import analysis), add Python later |
| TODO age requires git blame (slow on large repos) | Cache blame results, only re-blame changed files |
| ADR gap detection is heuristic | Conservative: only flag when a new top-level dependency appears in package.json/requirements.txt |
| `output: chat` means no PR trail for reports | Reports still written to `tech/reports/` and committed; `chat` just means tick results go to chat not PR |
