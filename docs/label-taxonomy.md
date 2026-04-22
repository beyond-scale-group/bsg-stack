# GitHub Bus — Label Taxonomy

Labels are the only routing and state primitive for the BSG agent
coordination bus. Every label that an agent reads or writes must appear
in this document. No agent may invent labels outside this schema.

## Routing labels — `needs:<agent>`

Signal that an issue or PR is waiting for a specific agent to process it.
Exactly one `needs:*` label should be present at any time during the
pipeline (the bus is a hand-off chain, not a fan-out).

| Label | Owner agent | Meaning |
|-------|-------------|---------|
| `needs:po` | `po-manager` | Needs PO triage / plan alignment check |
| `needs:security` | `security` | Needs security or dependency audit |
| `needs:qa` | `qa` | Needs QA / coverage or regression review |
| `needs:tech` | `tech-lead` | Needs architecture / tech-debt review |
| `needs:seo` | `seo` | Needs SEO / meta / content audit |
| `needs:marketing` | `marketing` | Needs marketing content review |
| `needs:storytelling` | `storytelling` | Needs brand / voice audit |
| `needs:pr-comms` | `pr-comms` | Needs press release or announcement draft |

## Mutex labels — `agent:lock:<agent>`

Applied by `bus_lock` at the start of a tick, removed by `bus_unlock`
when the agent finishes (or errors). Prevents two concurrent tick sweeps
from racing on the same issue.

| Label | Set by | Released by |
|-------|--------|-------------|
| `agent:lock:po` | `po-manager tick` | `po-manager tick` (always) |
| `agent:lock:security` | `security tick` | `security tick` |
| `agent:lock:qa` | `qa tick` | `qa tick` |
| `agent:lock:tech` | `tech-lead tick` | `tech-lead tick` |
| `agent:lock:seo` | `seo tick` | `seo tick` |
| `agent:lock:marketing` | `marketing tick` | `marketing tick` |
| `agent:lock:storytelling` | `storytelling tick` | `storytelling tick` |
| `agent:lock:pr-comms` | `pr-comms tick` | `pr-comms tick` |

> **Rule:** an agent MUST release its lock even on error. Use a Bash
> `trap 'bus_unlock "$num" "$AGENT"' EXIT` pattern.

## Terminal labels

| Label | Meaning |
|-------|---------|
| `agent:done` | All agent hops complete; no further routing needed. Applied by `bus_handoff <num> <from> done`. |
| `agent:blocked` | Human intervention required. Applied manually or by an agent that cannot proceed. Should always be accompanied by a `bus_post_marker` comment explaining the blocker. |

## Structured comment markers

Agents post machine-readable comments using `bus_post_marker`. Format:

```
<!-- agent:<name> v1 kind:<kind> -->
<YAML body>
<!-- /agent:<name> -->
```

Standard `kind` values:

| Kind | When used |
|------|-----------|
| `handoff` | Agent finished its work and routed to the next agent |
| `blocked` | Agent could not complete; explains why |
| `result` | Agent completed a terminal step (no next agent) |
| `note` | Informational; does not change routing |

Example handoff marker:
```
<!-- agent:seo v1 kind:handoff -->
to: marketing
reason: keyword audit complete, 3 pages updated
artifact: seo/reports/2026-04-22-audit.md
<!-- /agent:seo -->
```

## Issue body manifest — `agents-state` block

A fenced code block at the bottom of the issue body, managed by
`bus_set_manifest` / `bus_get_manifest`. Holds shared JSON state:

```
```agents-state
{
  "phase":    "marketing",
  "owner":    "marketing",
  "blockers": [],
  "history":  ["po", "seo"]
}
```
```

Fields:

| Field | Type | Meaning |
|-------|------|---------|
| `phase` | string | Current routing target (mirrors the active `needs:*` label) |
| `owner` | string | Agent currently holding the lock, or `null` |
| `blockers` | array | Human-readable blocker descriptions |
| `history` | array | Ordered list of agents that have already processed this issue |

## Label creation

Labels are not auto-created by `github-bus.sh`. Run this once per repo
to seed all bus labels:

```bash
# routing
for agent in po security qa tech seo marketing storytelling pr-comms; do
  gh label create "needs:${agent}" --color "0075ca" --force
done

# locks
for agent in po security qa tech seo marketing storytelling pr-comms; do
  gh label create "agent:lock:${agent}" --color "e4e669" --force
done

# terminal
gh label create "agent:done"    --color "0e8a16" --force
gh label create "agent:blocked" --color "d93f0b" --force
```

Keep label colors consistent across repos so the board is visually
scannable without opening individual issues.
