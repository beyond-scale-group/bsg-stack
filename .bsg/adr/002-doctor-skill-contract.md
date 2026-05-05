# ADR-002: `/bsg-stack doctor` skill contract

- **Status:** Accepted
- **Date:** 2026-05-05
- **Resolves:** #237 (block-A3), #555
- **Depends on:** ADR-001 (`.bsg/` directory convention)

## Context

#237 deliverable #4 proposes a `/bsg-stack` umbrella skill with
sub-verbs (`doctor`, `init`, `update`, `status`). The skill is the
single entry point for managing BSG agent infrastructure in any repo.

`/bsg-stack doctor` specifically is the health scorecard — it walks
the `.bsg/` tree, the GitHub label set, and the autopilot config,
then reports which agents are configured, which custom docs are
missing or stale, and which labels still need to be created.

#555 block-A3 calls out an unresolved design decision:

> Audit-only? Audit-and-patch? Read-only verbs only, or write
> verbs too?

Without a contract decision, the skill's scope is open-ended and the
boundary between `doctor` (diagnose) and `init` / `update` (write)
becomes blurred.

## Decision

`/bsg-stack doctor` is **strictly read-only.** It diagnoses; it does
not patch.

### Read-only verbs (this skill)

| Verb | What it does |
|---|---|
| `doctor` | Print health scorecard. Touches no files, opens no PRs, makes no API calls beyond `gh` reads. |
| `status` | One-line summary: which agents configured, which last-ticked when. |

### Write verbs (separate skills / verbs)

| Verb | Owned by | Behavior |
|---|---|---|
| `init` | `/bsg-stack init` | First-time bootstrap. Generates the full `.bsg/` skeleton plus per-agent custom docs by orchestrating each agent's own `--init`. Opens PR(s). |
| `update` | `/bsg-stack update` | Refresh stale docs. Re-runs `--init` for agents whose custom doc is outdated. Opens PR(s). |
| Per-agent `--init` | each agent | The actual scan + draft logic. `/bsg-stack init` is the orchestrator. |

### Rationale for the split

- **Diagnosis must be cheap and idempotent** so it can run on every
  `SessionStart` hook, in CI, in a `/loop`, etc. Mixing patch behavior
  in defeats this — a "I just want to look" call would mutate.
- **Write verbs require user consent.** The agent contract (CLAUDE.md
  → "Pure Claude-driven, per-repo, on-demand") says every run must be
  initiated by a human. `doctor` opening PRs would violate that even
  when explicitly invoked, because it could no longer be folded into
  background diagnostic loops.
- **One verb, one job.** `doctor` finds problems; `init` and
  `update` fix them. Mixing would force the skill to ask "should I
  patch this?" mid-flow, which breaks the silent-by-default principle.

### `/bsg-stack doctor` output contract

The output is a stable scorecard. Each row is one BSG concern:

```
Agent          Custom doc             Status
─────────────  ─────────────────────  ──────────────────────────
po-manager     .bsg/PLAN.md           ✓ present (3 days ago)
storytelling   .bsg/NARRATIVE.md      ✗ missing — run /bsg-stack init
seo            .bsg/KEYWORDS.md       ⚠ stale (90 days old)
…

Labels         Status
─────────────  ──────
needs-human-r  ✓ exists
human-reviewed ✗ missing — run /bsg-stack init
…

Autopilot      Status
─────────────  ──────
enabled        ✓ tech, qa, seo
auto_merge     ⚠ not set (default human-review-gated)
```

Status glyphs:

- `✓ present` — file/label/setting exists.
- `⚠` — exists but stale, mismatched, or partially configured.
- `✗ missing` — must be created. Suffix names the remediation
  command.

Exit code is `0` when there is nothing to act on, `1` when at least
one row is `✗`. `⚠` does not raise the exit code (it's a soft
warning). This makes `doctor` usable as a CI gate without forcing
zero-warning hygiene.

### Out of scope

- `doctor --fix` flag → explicitly **rejected** as a future addition.
  If you want to fix, run `init` or `update`. We will not ship a
  read-write hybrid.
- Cross-repo doctor sweeps → out of scope for v1. `doctor` is
  repo-scoped per CLAUDE.md (`tick`-style "one repo, one agent, one
  plan" principle).
- Auto-running `doctor` in CI / on every push → not this ADR's call.
  Repos opt in by adding it to their own workflow.

## Consequences

**Positive**

- The diagnose/fix split keeps each verb easy to reason about and
  trivially safe to run.
- `doctor` becomes safe to wire into `SessionStart` or `/loop`
  cadences without surprise mutations.
- Future agents add a row to the scorecard, not a new write path.

**Negative / Risks**

- Two extra verbs (`init`, `update`) that someone running
  `/bsg-stack doctor` first won't know exist until the output tells
  them. We accept this — the `✗ missing — run /bsg-stack init`
  remediation hint in each row is the discovery surface.
- `doctor` exit-code semantics (`✗` → 1, `⚠` → 0) are a small
  contract that consumers will depend on. We commit to keeping them
  stable.

## Alternatives considered

| Alternative | Why rejected |
|---|---|
| `doctor` does both audit and fix (with `--audit-only` flag) | Default-mutating violates silent-by-default principle. Hides write surface behind a verb that reads as read-only. |
| `doctor` audits + opens PRs for findings | Violates "every run initiated by a human" — diagnostic loops would generate PR noise. |
| Single `bsg-stack` verb with subcommands as flags (`--doctor`, `--init`) | Verbs as nouns are cleaner; aligns with `gh issue list` / `gh pr create` convention. |
| Skip the umbrella — separate `/bsg-doctor`, `/bsg-init` skills | More commands to discover; loses the single-entrypoint benefit. |

## References

- #237 — feat: mandatory --init on all agents/skills + /doctor skill
- #555 — plan: decompose #237 (A3)
- ADR-001 — `.bsg/` directory convention
- CLAUDE.md → "Pure Claude-driven, per-repo, on-demand"
