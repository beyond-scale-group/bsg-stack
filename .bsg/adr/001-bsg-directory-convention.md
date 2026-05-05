# ADR-001: Unified `.bsg/` directory convention

- **Status:** Accepted
- **Date:** 2026-05-05
- **Resolves:** #237 (block-A1, A2), #555
- **Supersedes:** none

## Context

BSG agents and skills produce per-repo artifacts (PLAN.md, NARRATIVE.md,
KEYWORDS.md, ANNOUNCED.md, ADRs, dated reports, autopilot config). Today
they live under eight separate top-level folders:

```
po/        brand/       seo/        marketing/
comms/     qa/          tech/       adr/
.bsg-autopilot.yml      .securityignore
```

Three problems:

1. **Discovery cost.** A new contributor lands on the repo and sees 8+
   sibling folders that look like product code but are agent
   infrastructure. There is no single path to inspect for "what BSG
   things does this repo have configured?"
2. **Cross-cutting tooling.** A `/doctor` skill (#237 deliverable #4)
   has to special-case nine different paths to assess repo health.
   Same problem for `/bsg-stack init`.
3. **No clear signal that these are infra, not product.** Top-level
   `po/`, `seo/`, `marketing/` clash with product naming in domain
   repos. A dot-prefixed folder makes the distinction obvious — same
   convention as `.github/`, `.vscode/`.

#555 frames this as block-A1 (the directory commitment) and A2 (the
`AUTOPILOT.yml` rename, which is mechanically the same migration).

## Decision

Adopt a single `.bsg/` directory at repo root that owns every BSG
agent artifact:

```
.bsg/
├── PLAN.md             # po-manager
├── NARRATIVE.md        # storytelling
├── DESIGN.md           # md-to-office (see ADR-003)
├── KEYWORDS.md         # seo
├── CALENDAR.md         # marketing
├── ANNOUNCED.md        # pr-comms
├── SECURITYIGNORE      # security
├── AUTOPILOT.yml       # autopilot config (renames .bsg-autopilot.yml)
├── adr/                # tech-lead — multi-file justified
├── brand/              # md-to-office templates
│   ├── tokens.json     # derived from DESIGN.md
│   └── templates/
└── reports/            # ALL agent dated reports, one subfolder per agent
    ├── po/
    ├── qa/
    ├── security/
    ├── tech/
    ├── seo/
    ├── marketing/
    ├── storytelling/
    ├── comms/
    └── cleaner/
```

### Rules

- **Flat files** when a single doc per agent suffices (PLAN, NARRATIVE,
  KEYWORDS, CALENDAR, ANNOUNCED, SECURITYIGNORE).
- **Subfolders** only when multi-file is intrinsic (`adr/`, `brand/`,
  `reports/`).
- **UPPER_CASE.md** for the canonical "what does this agent know about
  this repo" file (matches `CLAUDE.md`, `DESIGN.md`, `README.md`).
- **One unified `reports/` tree**, one subfolder per agent. No more
  `po/reports/`, `qa/reports/`, `comms/reports/` siblings.

### Migration strategy

Backwards-compatible cutover:

1. **This ADR + the `.bsg/` skeleton land first.** No file movement yet
   — the agent frontmatter (`custom-doc: .bsg/PLAN.md`) is already in
   place from a prior change.
2. **Path resolvers add `.bsg/` fallback.** `open-report-pr.sh`,
   `file-issue.sh`, and the per-agent report scripts read
   `.bsg/<doc>` if it exists, otherwise fall back to the legacy
   path. New writes go to `.bsg/`.
3. **One agent at a time** moves its docs and reports into `.bsg/`
   (separate PRs, one per agent, sized for the autopilot budget).
4. **Drop legacy fallback** once all agents have migrated and one
   release window has passed (cached `claude-skills/` installs need a
   chance to pull the new `update-bsg-skills.py`).

### `AUTOPILOT.yml` rename (A2)

`.bsg-autopilot.yml` → `.bsg/AUTOPILOT.yml`. The reader script (used by
`list-pilot-candidates.sh` and `pilot-circuit-breaker.sh`) prefers
`.bsg/AUTOPILOT.yml` and falls back to the dotfile during the migration
window. Same backwards-compatible cutover as above.

### What this ADR does NOT decide

- File-by-file migration order (lands as separate PRs per agent).
- Whether the legacy paths get redirect symlinks or hard-cutover
  removal at the end of the window. Default: hard cutover, since
  agents are the only readers and they all support the fallback.
- The new `/bsg-stack` skill's verb set — that's ADR-002.
- The `DESIGN.md` schema — that's ADR-003.

## Consequences

**Positive**

- Single directory to inspect / archive / `.gitignore` / inspect via
  `/bsg-stack doctor`.
- Aligns with the dotfile-as-infra convention used by `.github/`,
  `.vscode/`, `.cursor/`.
- One unified `reports/` tree makes "what did the agents say last
  week?" a single `find` instead of nine.
- Future agents need zero new top-level folders.

**Negative / Risks**

- One-time migration cost: ~9 PRs to move existing reports under
  `.bsg/reports/<agent>/`. Each PR is small (mechanical move +
  path-fallback toggle), but it's spread across all agents.
- Cached `claude-skills/` installs in consumer repos must pull the
  new `update-bsg-skills.py` before they see the convention. The
  fallback readers buy us a release window.
- Tools outside the BSG catalog (CI workflows that grep `po/PLAN.md`,
  bookmark links to `comms/ANNOUNCED.md`) will break. We accept
  that — the legacy paths weren't a stable API.

**Neutral**

- Agent frontmatter (`custom-doc: .bsg/PLAN.md`) is already updated
  to point at `.bsg/`. Tests for `custom-doc:` and `init:` enforce
  presence; this ADR makes them load-bearing.

## Alternatives considered

| Alternative | Why rejected |
|---|---|
| Status quo (8+ root folders) | Discovery cost, cross-cutting tooling friction, signal-vs-product confusion. |
| `bsg/` (no dot prefix) | Reads as product code in domain repos. Loses the `.github/`-style "infra" signal. |
| One folder per agent (`.po/`, `.seo/`, …) | Multiplies the discovery problem. `/doctor` still has to enumerate. |
| Keep flat + add a top-level `BSG.md` index | Does not solve the cross-cutting tooling case; reports still scattered. |

## References

- #237 — feat: mandatory --init on all agents/skills + /doctor skill
- #555 — plan: decompose #237 into auto-implementable subtasks
- CLAUDE.md → "Reporting agents output via auto-merge PRs"
- claude-skills/agents/tech-lead.md frontmatter (`custom-doc: .bsg/adr/`)
