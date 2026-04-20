# Communication Plan

How the agent frames the next-N-weeks view of comms work.

## Scope

The skill does not ship a script for plan generation — the plan is
**LLM-driven** on top of `events.sh` + `press-kit.sh` output plus
any upcoming milestones (those with a `dueOn` date in the snapshot).

## When to use

| Trigger                                              | Response                                                                                        |
| ---------------------------------------------------- | ----------------------------------------------------------------------------------------------- |
| "what's our comms plan for the next 4 weeks"         | Combine unannounced events + upcoming milestones into a week-by-week timeline                  |
| "prep a comms plan around release X"                 | Focus on one release: pre-announcement prep, release-day assets, post-release follow-up         |
| "what should comms work on next"                     | Prioritize unannounced events by priority + draft availability                                  |

## Output shape (narrative)

```markdown
## Next 4 weeks — Communication Plan

### Week of Apr 21
- v2.4.0 (minor release, Apr 18) — draft headline, pull quote from founder
- Fact sheet refresh (stale 127 days)

### Week of Apr 28
- Milestone "API v2" closure (Apr 15) — write longer-form announcement
- 50th contributor milestone — social post

### Week of May 5
- Expected release v2.5 (per "Q2 Roadmap" milestone due May 9)

### Week of May 12
- Post-launch follow-up: blog, customer story
```

## Hard rules

1. **Don't schedule events that don't exist.** Every item comes from
   the snapshot or from an explicitly declared upcoming milestone.
2. **Don't prescribe tone.** Draft availability is the output; tone
   is the \`@storytelling\` agent's beat.
3. **Be realistic about dates.** Releases slip. Prefer "week of"
   framing over calendar precision; note "estimated" for milestone
   due-dates.
4. **Cite sources.** Every entry should be traceable to a release
   tag, milestone number, or press-kit file.

## Pitfalls

- **Milestones without dates.** Many milestones don't have `due_on`
  set. Exclude them from the forward-looking plan; only mention them
  in the "backlog" section if present.
- **Stacked releases.** If three minor releases shipped in 10 days,
  bundle them into a single narrative beat rather than drafting
  three separate press releases.
- **The comms team's actual calendar.** This skill doesn't know
  about external commitments (conferences, customer-case studies in
  flight, partner co-announcements). The narrative should
  acknowledge this and invite the comms lead to layer them in.

## What NOT to do

- Don't generate a calendar integration (ICS, Google Calendar) —
  out of scope.
- Don't auto-email the plan. Like every other output of this skill,
  it's a file on disk for humans to act on.
