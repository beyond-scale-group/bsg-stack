<a href="../../README.md"><img src="../../assets/logo-bsg-holding.png" alt="Beyond Scale Group" height="40"></a>

**[Beyond Scale Group](../../README.md)** · [BSG Stack](../../README.md) · [Claude Skills](../README.md)

---

# `agents/` — BSG subagents

Role-scoped Claude Code subagents. Each is a single Markdown file with
frontmatter (tools, `output` mode, scope contract) and a system prompt.
Invoke one from inside any repo with a mention or its `tick` verb:

```
@po-manager give me the full status
@tech-lead tick
```

Run all of them in one sweep with [`/tick-all`](../commands/tick-all.md), or a
single one in an isolated worktree with `/tick-one <agent>`.

## Output modes

- **`output: pr`** — audits only; writes a dated report and opens an
  auto-merge PR. Never touches source code.
- **`output: commit`** — may auto-implement one scoped fix per tick
  (≤ 200 LOC / ≤ 8 files) when the repo opts in via `.bsg/AUTOPILOT.yml`.

## The catalog

| Agent | Bus label | Output | Domain |
|---|---|---|---|
| `po-manager` | `po` | pr | Product owner: plan adherence, backlog triage, milestones, PR flow, task routing (`delegates-to: tech, qa, seo`). |
| `tech-lead` | `tech` | commit | Architecture (ADRs), dependency health, code-quality signals, tech debt. |
| `qa` | `qa` | commit | Test coverage trends, regression-risk hotspots, flaky-test detection. |
| `seo` | `seo` | commit | Meta tags, sitemap, internal links, structured data, keyword coverage. |
| `docs-keeper` | `docs-keeper` | commit | README / CHANGELOG / `.bsg/` doc staleness, dead links, drifted commands. |
| `security` | `security` | pr | Dependency vulns, committed secrets, OWASP top-10 gaps. |
| `marketing` | `marketing` | pr | Content calendar, feature↔marketing alignment, campaign briefs. |
| `storytelling` | `storytelling` | pr | Brand narrative bible, voice consistency, talking points. |
| `pr-comms` | `pr-comms` | pr | Newsworthy events, press releases, press kit. |
| `cleaner` | `cleaner` | pr | Backlog hygiene: orphaned locks, stale labels, duplicate issues. |

`registry.json` is the machine-readable version of this table — the list of
agents that participate in `/tick-all` sweeps and the coordination bus. See
[`../../CLAUDE.md`](../../CLAUDE.md) for the full tick / autopilot / peer-review
contract, and [`../INSTALL.md`](../INSTALL.md) for the install catalog.

## Reporting skills vs. agents

Most agents pair with a `*-report` skill in [`../skills/`](../skills/) that does
the deterministic aggregation (e.g. `tech-lead` ↔ `tech-report`,
`qa` ↔ `qa-report`). The agent orchestrates; the skill's scripts count.

---

<sub>Source of truth — edit here and PR back, never edit the cached copies in
`~/.claude/agents/`. See [`../INSTALL.md`](../INSTALL.md).</sub>
