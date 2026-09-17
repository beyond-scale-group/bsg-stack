# PRD-009: session-janitor Skill

**Status:** Draft
**Author:** Guillaume Badin
**Date:** 2026-09-17
**Priority:** P2 — machine hygiene

---

## 1. Problem Statement

Claude Code sessions accumulate on a developer machine and nothing reaps
them. Each idle session holds a resident process; none of them notices
that the work it was opened for has already landed.

The numbers below were measured on one developer machine on 2026-09-17,
not estimated:

| Measure | Value |
|---|---|
| Live `claude` processes before the sweep | 35 |
| Sessions whose branch was fully merged into `main`/`staging` | 9 |
| Memory held by those 9 | ~1.25 GB |
| Live processes after reaping them | 28 |
| Resident memory across the remaining 28 | ~5.6 GB |
| Pairs of sessions sharing one worktree | 5 |

Nine sessions were holding 1.25 GB to keep alive work that was already in
`main`. Five more pairs were doing the same job twice in the same
directory.

The reaping cannot be naive, and the same audit shows exactly why. Three
sessions looked disposable by process age and were not:

- **`nidara.ai/build+socle-v0`** — its PR (#8) was merged, but the
  worktree held ten modified files and three Vite dev servers were
  running against it. Reaping on "PR merged" alone destroys live work.
- **`bsg-lbo/worktree-clear-harbor-6a62`** — three commits
  (`legal(assurance-rc): …`), no upstream configured, never pushed.
- **`poc_decentralized_claude_build/installation_vps`** — two commits,
  no upstream, never pushed.

The published alternatives do not cover this. `/ccclean`
([YuancFeng/claude-code-cleanup](https://github.com/YuancFeng/claude-code-cleanup))
kills orphan processes with a 5-minute age floor and a confirmation
prompt, and reads no git state at all — it would have killed all three
sessions above. The worktree pruners
([`prune-worktrees`](https://mcpmarket.com/tools/skills/prune-worktrees),
[`review-worktree-cleanup`](https://mcpmarket.com/tools/skills/review-worktree-cleanup))
do read PR state, but they delete directories and never touch processes.
Upstream has the gap open and unshipped:
[anthropics/claude-code#44321](https://github.com/anthropics/claude-code/issues/44321),
[#32700](https://github.com/anthropics/claude-code/issues/32700),
[#88123](https://github.com/anthropics/claude-code/issues/88123).

A second, independent gap surfaced during the same audit. Every PR
sampled across four repos (`bsg-lbo#362`, `bsg-lbo#361`,
`digischool.com#49`, `expert-flow.ai#2816`) returned
`closingIssuesReferences: []` and `projectItems: []`. No PR is linked to
its issue; no PR is on a board — while both boards (*BSG board*,
*ExpertFlow Roadmap*) exist and the issues themselves are correctly
labelled. Nothing on the machine records which ticket a session was
opened for, so when a session ends its ticket stays open and its board
column stays wrong.

## 2. Goal

Ship a **machine-scoped** skill that walks every live Claude Code session
on the host, resolves each one to its repository, branch, PR, and ticket,
and then — under explicit verbs — reconciles GitHub, syncs the worktree,
and reaps the sessions that provably have nothing left to lose.

Diagnosis must stay free and idempotent so it can run under `/loop`.
Every form of writing is a separate, explicit verb.

## 3. Non-Goals

- **No CI automation.** Scheduling goes through `/loop` or `/schedule` on
  the developer's own machine, per CLAUDE.md → "No CI cron".
- **No `tick`.** `tick` is repo-scoped by contract and writes a report PR
  to its host repo. A machine-scoped sweep has no host repo. See §5.1.
- **No cross-repo report store.** The janitor writes no dated report into
  any repo; its output is terminal-only plus a machine-local state file.
- **No killing on inference.** A session is reaped only when every
  invariant in §5.4 holds. When state cannot be resolved, the session is
  reported and left alone.
- **No rewriting issue bodies or PR descriptions.** `reconcile` adds
  links, closes, and moves columns. It never edits prose.
- **No `SIGKILL`.** `SIGTERM` only; a session that ignores it is reported,
  not escalated.

## 4. User Stories

- *As a developer with 35 open sessions*, I run `/session-janitor` and get
  one scorecard of what each session is for and whether it is still
  needed — without anything being touched.
- *As the same developer*, I run `/session-janitor reap` and the sessions
  whose work is fully merged are closed, while the one with uncommitted
  work and three dev servers is explicitly skipped and named.
- *As a PO*, I want the ticket behind a merged session to be closed and
  moved on the board without me doing it by hand.
- *As anyone*, I run `/loop 30m /session-janitor` and get a quiet
  heartbeat that stays silent until a session becomes reapable.

## 5. Skill Design

### 5.1 Scope exception: machine-scoped, no `tick`

CLAUDE.md states that `tick` is repo-scoped and that multi-repo sweeps are
out of scope for it. `session-janitor` is the first component that is
legitimately machine-scoped: its unit of work is a host process, not a
repository.

The exception is resolved by **not implementing `tick` at all**, rather
than by bending it:

- no `tick` verb, and no entry in `claude-skills/agents/registry.json`
- not fired by `/tick-all`
- `output:` is not `pr` — there is no host repo for a report
- recurrence is the user's explicit `/loop`, which CLAUDE.md already
  endorses as the sanctioned scheduler

This keeps the repo-scoped contract intact for every agent that has one.

### 5.2 Verbs

The split follows ADR-002: diagnosis is strictly read-only, every write is
its own verb.

| Verb | Writes | Safe under `/loop` |
|---|---|---|
| `doctor` (default) | nothing | ✓ |
| `sync` | git, local + remote | ✗ |
| `reconcile` | GitHub issues, PRs, project boards | ✗ |
| `reap` | host processes (`SIGTERM`) | ✗ |

`doctor` makes `gh` read calls only. It opens no PR, mutates no label,
touches no file outside its own cache.

Each write verb accepts `--dry-run` and prints the exact mutations it
would perform. `reap` additionally accepts `--yes` to skip its
confirmation; without it, it lists the targets and waits.

### 5.3 The shared resolver

`session-state.sh` is the single source of truth for "what is this
session". It emits one JSON object per line — one line per live session:

```json
{
  "pid": 87075,
  "cwd": "/Users/gdumas/.herdr/worktrees/bsg-lbo/nidara",
  "repo": "beyond-scale-group/bsg-lbo",
  "branch": "nidara",
  "upstream": null,
  "dirty": 0,
  "unpushed": 0,
  "merged_into_base": true,
  "pr": null,
  "issue": null,
  "busy": false,
  "dev_servers": [],
  "age_seconds": 59812,
  "rss_mb": 142,
  "verdict": "reapable"
}
```

Field derivation:

| Field | Source |
|---|---|
| `cwd` | `lsof -a -p <pid> -d cwd -Fn` |
| `repo` | `git remote get-url origin`, normalised to `owner/name` |
| `unpushed` | `git rev-list --count @{u}..HEAD`; `null` upstream ⇒ treat every local commit as unpushed |
| `merged_into_base` | `git merge-base --is-ancestor HEAD origin/<base>` |
| `pr` | `gh pr view <branch>`, else `gh pr list --head <branch> --state all` |
| `issue` | registry lookup (§5.5), else `closingIssuesReferences`, else `null` |
| `busy` | session runtime state, cross-checked against transcript mtime |
| `dev_servers` | child processes of the session whose cwd is under the worktree |

`verdict` is one of `reapable`, `keep:dirty`, `keep:unpushed`,
`keep:pr-open`, `keep:busy`, `keep:dev-servers`, `keep:too-young`,
`keep:self`, `unknown`. Every consumer filters on `verdict`; none
re-derives the rules.

`sync` consumes the same lines instead of re-walking worktrees — this is
where the duplication with `/sync-worktree` is actually removed, rather
than merely relocated.

### 5.4 Reap invariants

`reap` sends `SIGTERM` to a session **only** when all of the following
hold. Each was derived from a real session in the 2026-09-17 audit that
a naive reaper would have destroyed.

1. `dirty == 0` — the worktree has no modified or staged files.
2. `unpushed == 0` **and** an upstream exists. A branch with no upstream
   is never reapable, whatever its commit count.
3. `merged_into_base == true` **or** the PR is `MERGED`/`CLOSED`.
4. No PR is `OPEN` for the branch.
5. `busy == false`.
6. `dev_servers` is empty.
7. `age_seconds >= 300`.
8. The PID is not this session's own, and not its parent.

Failing any invariant yields a `keep:*` verdict, and the session is named
in the output with its reason. Silence about a skip is a bug.

### 5.5 Session → ticket registry

Nothing currently records the link (§1), so the janitor maintains it.

`${CLAUDE_CONFIG_DIR:-$HOME/.claude}/bsg-sessions.json` maps
`worktree path → { repo, branch, pr, issue, opened_at }`. It is written by
`/ship` and `/merge`, which already hold that context at the moment a
branch is pushed and a PR opened. The janitor reads it and never invents
an entry.

Two consequences, both accepted:

- **The registry is not authoritative for history.** It is a cache keyed
  on a path; a deleted worktree's entry is garbage-collected by `doctor`.
  The durable record stays on GitHub, which is what `reconcile` writes.
- **Pre-existing sessions are orphans.** The 28 sessions live at the time
  of writing predate the registry and will resolve `issue: null`. A
  one-shot `adopt` verb proposes a candidate ticket per orphan by title
  similarity against open issues — the same Levenshtein approach the
  `cleaner` agent already uses for duplicate detection — and writes the
  registry only on explicit confirmation, one session at a time. `adopt`
  is out of scope for lot 1.

### 5.6 Path resolution

The resolver's **source of truth is this repo**:
`claude-skills/scripts/session-state.sh`. It is versioned, reviewed, and
tested here like every other script.

Its **runtime path is the installed copy**, because a machine-scoped tool
runs from `$HOME` or from an arbitrary repo, and the repo copy is exactly
the one that is not reachable from there. Measured on 2026-09-17:
`~/.claude/scripts/github-bus.sh` exists; `<any target
repo>/claude-skills/scripts/github-bus.sh` does not — no target repo
vendors `claude-skills/`, and the updater mirrors into
`$CLAUDE_CONFIG_DIR` (default `~/.claude`).

A helper, `_bsg-script-path.sh`, resolves a script name to a path,
preferring the repo copy when one exists so that hacking on the script
inside `bsg-stack` takes effect immediately, and falling back to the
installed copy everywhere else:

```sh
bsg_script_path() {
  local name="$1" root
  root="$(git rev-parse --show-toplevel 2>/dev/null)" || root=""
  if [ -n "$root" ] && [ -f "$root/claude-skills/scripts/$name" ]; then
    printf '%s\n' "$root/claude-skills/scripts/$name"
  else
    printf '%s\n' "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/scripts/$name"
  fi
}
```

This helper is deliberately general. It is the mechanism a follow-up can
use to repair the 63 existing `bash claude-skills/scripts/…` references
(§10), but this PRD does not change them.

## 6. Directory Layout

```
claude-skills/
├── skills/session-janitor/
│   ├── SKILL.md
│   └── references/
│       ├── doctor.md
│       ├── reap.md
│       ├── sync.md
│       └── reconcile.md
└── scripts/
    ├── _bsg-script-path.sh      # new, shared
    └── session-state.sh         # new, the resolver
```

State, machine-local, never committed:

```
${CLAUDE_CONFIG_DIR:-$HOME/.claude}/bsg-sessions.json
```

## 7. Dependencies

`gh` (authenticated), `jq`, `git`, `lsof`, `ps`. All already required by
the existing catalogue except `lsof`, which ships with macOS and every
mainstream Linux distribution.

macOS is the supported target. Linux is best-effort: the `lsof`-based cwd
resolution works, but the dev-server detection walks the process tree and
is untested there.

## 8. Silence-Breakers

`doctor` under `/loop` prints nothing when no session is reapable and no
state is `unknown`. It breaks silence for:

1. one or more sessions reaching `reapable`
2. a session whose PR is `MERGED` while its worktree is dirty — the
   `build+socle-v0` case, where work risks being stranded
3. a `verdict: unknown` that persists across two consecutive runs
4. total session RSS crossing a configurable ceiling (default 6 GB)

## 9. Testing

`claude-skills/tests/` with the existing bash harness:

- `test_session_state.sh` — the resolver against a fixture tree of git
  repos in known states (clean/merged, dirty, unpushed-no-upstream,
  PR-open), asserting one exact `verdict` per fixture.
- `test_reap_invariants.sh` — each of the eight invariants in §5.4 gets a
  case proving a session in that state is **not** reaped. The three real
  sessions from §1 are encoded as fixtures.
- `test_script_path.sh` — `bsg_script_path` prefers the repo copy, falls
  back to the installed copy, honours `CLAUDE_CONFIG_DIR`.

No test sends a real signal: `reap` takes an injectable kill command,
defaulting to `kill -TERM`, and the tests pass a recorder.

## 10. Out of Scope, Filed Separately

**The 63 broken script references.** Agents and commands reference `bash
claude-skills/scripts/…`, a repo-relative path that resolves only inside
`bsg-stack` itself. In any other repo those calls point at nothing. The
impact appears latent rather than active — `bsg-lbo` holds only
`.bsg/reports/qa/0000-baseline.md` and no dated tick report, suggesting
ticks run mostly from `bsg-stack` — but the convention is wrong as
documented. This PRD ships the helper that fixes it (§5.6) and changes no
call site. A separate issue should do the migration.

## 11. Delivery Plan

Four lots, ordered by rising blast radius. Each is one PR in its own
worktree.

| Lot | Contents | Writes |
|---|---|---|
| **1** | `_bsg-script-path.sh`, `session-state.sh`, `doctor`, tests | nothing |
| **2** | `reap` + the eight invariants | host processes |
| **3** | absorb `/sync-worktree` onto the shared resolver | git |
| **4** | registry writes in `/ship` and `/merge`, `reconcile`, `adopt` | GitHub |

**This PRD specifies lot 1 in full.** Lots 2–4 are scoped here only far
enough to prove the architecture holds; each gets its own spec and plan.

Lot 1 is useful on its own: it is exactly the manual audit that produced
§1, made repeatable and loopable.

Lot 3 keeps `/sync-worktree` working as a thin alias. The command is in
active use and this PRD does not break it.

## 12. Open Questions

1. **Herdr and Superconductor sessions.** Of the 28 sessions live after
   the sweep, 11 sit under `~/.herdr/worktrees/` and 2 under
   `~/.superconductor/worktrees/` — and one of those two is a wrapper
   shell around the other, so a naive walk double-counts it. Both
   runtimes may hold their own locks or expect to reap their own
   children. Lot 1 reports them like any other session and must collapse
   wrapper/child pairs into one logical session; whether lot 2 may reap
   them at all needs a decision.
2. **Board column vocabulary.** `reconcile` must know which column a
   merged ticket moves to. *BSG board* and *ExpertFlow Roadmap* may not
   share column names. Deferred to lot 4.
3. **`busy` detection.** Reading session runtime state cross-checked
   against transcript mtime is proposed; if that proves unreliable, the
   fallback is to treat every session whose transcript changed in the
   last 5 minutes as busy.

## 13. Success Metrics

- Replayed against the §1 audit encoded as fixtures, `doctor` reproduces
  its verdicts exactly: the 9 merged-and-clean sessions as `reapable`,
  `build+socle-v0` as `keep:dirty` rather than `reapable`, and the two
  no-upstream sessions as `keep:unpushed`. (The 9 live sessions were
  closed by hand on 2026-09-17, so the fixtures — not the machine — are
  the reproducible artefact.)
- `doctor` completes in under 15 s for 35 sessions.
- Zero sessions reaped with uncommitted or unpushed work, measured across
  the first month of use.
- Steady-state session count on the machine stops growing monotonically.
