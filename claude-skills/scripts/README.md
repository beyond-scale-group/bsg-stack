<a href="../../README.md"><img src="../../assets/logo-bsg-holding.png" alt="Beyond Scale Group" height="40"></a>

**[Beyond Scale Group](../../README.md)** · [BSG Stack](../../README.md) · [Claude Skills](../README.md)

---

# `scripts/` — helper scripts & functions

Deterministic bash + Python helpers that the BSG agents and slash commands
call under the hood. Per the **"scripts before LLM"** principle
([CLAUDE.md](../../CLAUDE.md)), every count, tree-walk, and state transition
lives here — the agents only narrate the output.

You rarely call these directly (the agents do it for you), but they're all
runnable standalone. Most support `--help` or print a usage block on bad
input, and most accept `--repo OWNER/NAME` to target a repo other than the
current working directory.

## Two kinds of files

| Kind | How to run | Examples |
|---|---|---|
| **Executable** (`bash <script>.sh …`) | Run it | `file-issue.sh`, `open-report-pr.sh` |
| **Sourced** (`source <script>.sh`) | Provides shell functions, don't execute | `_bsg-paths.sh`, `github-bus.sh` |

## Path & config resolution

| Script | What it does |
|---|---|
| `_bsg-paths.sh` | **Sourced.** Resolves every `.bsg/` custom doc + autopilot config to the new path or its legacy fallback (ADR-001). Exposes `bsg_doc_path <kind>` and `$BSG_AUTOPILOT_FILE`. Any script reading a custom doc must source this. |
| `read-intent-file.sh` | Read a per-repo intent file (`ROADMAP.md`, …) from the repo root; prints contents, empty output if absent. |

## Issue routing & labels

| Script | What it does |
|---|---|
| `file-issue.sh` | Wrap `gh issue create` with the BSG review-label convention (auto-adds `needs-human-review` outside autopilot; `--filed-by` traceability inside). Use this instead of raw `gh issue create`. |
| `normalize-issue-labels.sh` | Auto-route open issues into the pilot pipeline by adding missing type/bus labels (PO tick step 1.4). |
| `audit-labels.sh` | Verify label-convention compliance: exactly one bus label per open item. |
| `migrate-epics-to-milestones.sh` | One-shot idempotent migration of `epic:E*` labels → GitHub milestones (`--dry-run` / `--apply`). |
| `decompose-issue.sh` | Mechanical executor that splits one oversized issue into child sub-issues (`--child "<title>"`), inheriting bus label + milestone. |
| `po-decompose-oversized.sh` | Flag open issues whose estimated LOC exceeds `max_loc_per_issue` so the PO can decompose them. |
| `detect-stuck-issues.sh` | Flag & escalate eligible-but-unimplemented issues (two-tier: nudge → escalate). |

## Coordination bus (GitHub labels as queues)

| Script | What it does |
|---|---|
| `github-bus.sh` | **Sourced.** Primitives `bus_claim` / `bus_lock` / `bus_handoff` / `bus_unlock` over `needs:*` / `agent:lock:*` / `agent:done` labels. |
| `bus-handler.sh` | Per-agent claim handler — processes `needs:<agent>` inbox items at tick step 0 (`--agent`, `--action acknowledge\|log`). |

## Autopilot / `output: commit` pilot

| Script | What it does |
|---|---|
| `list-pilot-candidates.sh` | Enumerate issues eligible for auto-implementation (bus + type + milestone, no open PR). Honors the `needs:<agent>` PO inbox. |
| `pilot-circuit-breaker.sh` | Daily cap: exit 1 when PRs opened today reach `max_prs_per_day`. Skips phase B. |
| `pilot-status.sh` | Pilot health report over a window (attempts / merged / closed / open / reverts) — the #181 go/no-go metric. |
| `tick-idle-check.sh` | Pre-flight idle check: skip the whole tick when there are no candidates and the fingerprint is unchanged. |
| `tick-fingerprint.sh` | **Eval'd.** SHA-256 of repo input state (`issues,prs,head` by default) for same-day tick short-circuit. |

## Review, PRs & merge

| Script | What it does |
|---|---|
| `open-report-pr.sh` | Wrap a report file in an auto-merge PR on branch `reports/<agent>/<slug>`. The canonical `output: pr` path. |
| `mark-reviewed.sh` | Atomically merge a PR + add `human-reviewed` + remove `needs-human-review`. The human-review helper. |
| `auto-merge-or-flag.sh` | Finalize an implementation PR: flag `needs-human-review` by default, or squash-merge + stamp `human-reviewed` when the repo sets `auto_merge: true`. |
| `peer-review-candidates.sh` | List pilot PRs awaiting peer review from a given `--reviewer`, per the `.bsg/AUTOPILOT.yml` review matrix. |

## Plan, worktrees & housekeeping

| Script | What it does |
|---|---|
| `validate-plan.sh` | Validate `PLAN.md` exists and carries binding tags; non-zero exit + diagnostic otherwise. |
| `prune-agent-worktrees.sh` | Remove stale `.claude/worktrees/agent-*` worktrees left behind by `/tick-all`. |

## Installer & session capture (Python)

| Script | What it does |
|---|---|
| `update-bsg-skills.py` | The installer. Refreshes cached commands/skills/agents from `bsg-stack@main` into `~/.claude/`, self-registers the `SessionStart` hook, manages the manifest. Run by the SessionStart hook every session. |
| `bsg_updater/` | The installer's Python package (config, http_client, installer, manifest, reconcile, settings, walker) — imported by `update-bsg-skills.py`. |
| `upload-session-to-gbrain.py` | Opt-in `SessionEnd` hook: renders + redacts the transcript and POSTs it to a personal gbrain. Silent unless `GBRAIN_INGEST_URL` + `GBRAIN_MCP_TOKEN` are set. |

## Tests

`test/` holds pipeline / invariant test harnesses (`run-pipeline-test.sh`,
`assert-invariants.sh`, `seed-test-backlog.sh`) — see
[`test/README.md`](test/README.md). Unit tests for these scripts live in
[`../tests/`](../tests/).

---

<sub>Source of truth — edit here and PR back, never edit the cached copies in
`~/.claude/scripts/`. See [`../INSTALL.md`](../INSTALL.md).</sub>
