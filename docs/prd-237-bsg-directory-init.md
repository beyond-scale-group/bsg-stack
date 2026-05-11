# PRD: Unified `.bsg/` Directory & Mandatory Agent `--init`

**Issue:** #237  
**Status:** In Progress (~25% complete)  
**Date:** 2026-05-05  
**Owner:** @g-dumas

## Problem Statement

BSG agents produce per-repo artifacts (PLAN.md, NARRATIVE.md, KEYWORDS.md,
reports, ADRs) scattered across 8+ top-level folders. Setting up a new repo
for BSG agents requires manually creating 6-8 custom documents. There is no
single command to bootstrap agent infrastructure, and no enforcement that
agents expose self-setup capability.

This creates:
1. **High onboarding friction** — manual creation of per-agent docs
2. **Discovery cost** — no single place to look for "what BSG things exist here?"
3. **No enforcement** — nothing validates agents can bootstrap themselves

## Success Criteria

| # | Criterion | Verification |
|---|---|---|
| 1 | All agent artifacts live under `.bsg/` with legacy fallback | `doctor.sh` reports all docs at new paths |
| 2 | Every agent has a working `--init` that generates its custom doc | Run `/bsg-stack init` on a bare repo → all docs created |
| 3 | `/bsg-stack init` bootstraps a fresh repo end-to-end | Single command creates `.bsg/`, labels, docs, opens PR |
| 4 | `/bsg-stack update` refreshes stale docs | Docs older than 90 days get regenerated |
| 5 | `/bsg-stack status` shows one-line agent state | Quick summary without the full scorecard |
| 6 | `DESIGN.md` follows Google Stitch spec | Parseable by md-to-office, produces valid tokens.json |
| 7 | Path migration is backward-compatible | Legacy paths still work during transition window |
| 8 | Tests enforce all conventions | `test_skills.py` fails if init script missing |

## What's Already Delivered

| Deliverable | PR | Date |
|---|---|---|
| `custom-doc:` + `init:` frontmatter enforcement | #240 | 2026-04-30 |
| `/bsg-stack doctor` skill | #580 | 2026-05-05 |
| ADR-001: `.bsg/` directory convention | #577 | 2026-05-05 |
| ADR-002: Doctor skill contract (read-only) | #577 | 2026-05-05 |
| ADR-003: DESIGN.md schema (Google Stitch) | #577 | 2026-05-05 |
| `_bsg-paths.sh` (AUTOPILOT path resolver) | #580 | 2026-05-05 |

## What Remains

### Deliverable 1: Universal Path Resolution Layer

Extend `_bsg-paths.sh` from single-path (AUTOPILOT only) to all BSG
artifacts. Every script that reads/writes a BSG file sources this and uses
the exported variable instead of a hardcoded path.

### Deliverable 2: Per-Agent `--init` Scripts (8 agents)

Each agent gets a bash script that scans the target repo and emits a
first-draft custom document to stdout. The orchestrator (`/bsg-stack init`)
captures output and opens a PR.

| Agent | Script | Output | Scan Sources |
|---|---|---|---|
| po-manager | `init-plan.sh` | `.bsg/PLAN.md` | Milestones, issues, labels, README |
| storytelling | `init-narrative.sh` | `.bsg/NARRATIVE.md` | README, landing page, existing copy |
| md-to-office | `init-design.sh` | `.bsg/DESIGN.md` | CSS vars, Tailwind config, logos |
| marketing | `init-calendar.sh` | `.bsg/CALENDAR.md` | Releases, blog posts, PR history |
| seo | `init-keywords.sh` | `.bsg/KEYWORDS.md` | README, docs/, meta tags |
| security | `init-securityignore.sh` | `.bsg/SECURITYIGNORE` | Test fixtures, CI config |
| pr-comms | `init-announced.sh` | `.bsg/ANNOUNCED.md` | Releases, CHANGELOG |
| tech-lead | `init-adr.sh` | `.bsg/adr/000-*.md` | Major deps, CI, architecture signals |
| qa | `init-qa.sh` | `.bsg/reports/qa/.gitkeep` | Test framework, coverage tool |

### Deliverable 3: `/bsg-stack` Subcommands

| Verb | Behavior |
|---|---|
| `init` | Create `.bsg/` skeleton, run all agent inits, create labels, open PR |
| `update` | Re-run init for docs stale >90 days, open PR with refreshed content |
| `status` | One-line summary (delegates to `doctor.sh --status`) |

### Deliverable 4: DESIGN.md Generation (Google Stitch)

Extend `scan-brand.py` with `--emit design-md` to produce `.bsg/DESIGN.md`
in Stitch format. Add `tokens-from-design.py` to derive `tokens.json` from
DESIGN.md for backward compatibility with md-to-office.

### Deliverable 5: Report Path Migration

Migrate each agent's report output from `<agent>/reports/` to
`.bsg/reports/<agent>/`. One PR per agent, using the resolution layer for
backward compat.

## Out of Scope

- CI automation for agent ticks (remains human-initiated)
- Cross-repo sweeps
- Removing legacy path support (deferred to a future "cutover" PR)
- Changes to the autopilot budget or circuit-breaker behavior
- New agents

## Risks & Mitigations

| Risk | Mitigation |
|---|---|
| Breaking cached `~/.claude/` installs | Resolution layer checks both paths; legacy fallback persists during window |
| Multiple PRs in flight during migration | One agent at a time; worktree isolation |
| Init scripts produce low-quality drafts | All init output goes through a PR for human review before landing |
| Path resolver adds runtime cost | Pure bash string checks; negligible vs. `gh` API calls in every tick |

## Dependencies

- ADR-001, ADR-002, ADR-003 (all merged)
- `_bsg-paths.sh` pattern (merged, needs extension)
- `bootstrap-plan.sh` (exists for po-manager, proves the pattern)
- `init-brand.sh` / `scan-brand.py` (exists for md-to-office)
