---
name: learn
description: >
  End-of-session learning and improvement proposer. Use when the user says "/learn",
  "learn from this session", "what did we learn", "propose improvements", or asks for
  a retrospective on the conversation. Reviews the session to surface concrete, actionable
  improvement proposals: skill updates, new skills to create, CLAUDE.md updates, memory
  entries, file reorganization, workflow improvements. Presents a numbered menu and
  applies whichever items the user selects. Short-circuits with a one-line receipt when
  no new signal is detected vs. recent prior iterations (dedup check, #104).
---

# Learn

Review the current session and propose improvements the user can apply with one command.

## Dedup short-circuit (#104)

Before generating proposals, check whether the session's findings are already
captured. When this skill runs in a tight recurring loop (`/loop 5m /learn all and
create tickets`), successive iterations waste tokens re-analyzing unchanged state.

### Short-circuit procedure

1. Fetch open issues labeled `bug` or `enhancement` created in the **last 2 hours**
   by the current GitHub user:

   ```bash
   gh issue list --state open --author "@me" \
     --json number,title,createdAt,labels \
     --jq '[.[] | select(.createdAt > (now - 7200 | todate))]'
   ```

2. Build a proposal list from the session as normal (step 1 of the Process below),
   but **do not present it yet**.

3. Compute overlap: what fraction of the new proposals are covered by the titles or
   bodies of the recently-created issues? Use semantic similarity — a proposal about
   "missing context in `/learn`" matches an issue titled "learn skill missing context
   signal" at > 80 % overlap.

4. **If overlap >= 80 %**, short-circuit:

   ```
   /learn: no new signal since #<issue-number> (<title>) — skipping this iteration
   ```

   Cite all recently-created issues that together cover the proposals. Do not present
   the numbered menu. Do not create new issues.

5. **If overlap < 80 %**, proceed normally with only the non-overlapping proposals.
   Label the skip reason next to any item that is already covered (e.g. `[covered by #84]`).

### What counts as "covered"

- The issue title or body explicitly names the same pain point or discovery.
- A linked PR implements the proposed change.
- A CLAUDE.md or memory entry already contains the proposed content.

Stale issues (closed, > 2 hours old) do not count — if the fix didn't land, it is
still signal worth re-surfacing.

---

## Process

1. **Scan the session** for:
   - Pain points: repeated corrections, missing context, failed first attempts, 404s on docs
   - Discoveries: new tools, patterns, conventions, integrations found
   - Validated approaches: things the user confirmed or accepted without pushback
   - Gaps: information looked up that should be persisted for next time

2. **Categorize each finding** into one of:
   - `[MEMORY]` — save a user/feedback/project/reference memory entry
   - `[SKILL UPDATE]` — improve an existing skill (name it)
   - `[NEW SKILL]` — create a new skill that would have helped
   - `[CLAUDE.md]` — add or update a project or global CLAUDE.md
   - `[REORG]` — rename, move, or restructure files/directories

3. **Present a numbered proposal list**, concise and scannable:

```
Session learnings — pick what to apply:

1. [MEMORY/feedback]     Don't summarize completed work at end of responses
2. [MEMORY/project]      Donna is the Hermes chief-of-staff agent at AIDC
3. [SKILL UPDATE] gh-pr  Add step: load linked issues before proposing action plan
4. [NEW SKILL] hermes    Workflow for configuring Hermes gateway + messaging platforms
5. [CLAUDE.md] aidc      Document DONNA_HOME and Hermes startup convention

Enter numbers to apply (e.g. 1 3 5), "all", or "none":
```

4. **Apply selected items immediately** — write files, create memory entries, edit skills.
   For memory entries, use the format and file conventions in `~/.claude/projects/*/memory/`.
   If the user answers **"all"**: apply every item silently without further prompts, then open a pull request via `gh pr create`. Do not ask for confirmation at any step.

## Guidelines

- Present 3–8 proposals per session. Fewer, higher-signal items beat a long list.
- Skip things already covered in CLAUDE.md or existing memory.
- For `[SKILL UPDATE]`: quote the exact line or section to change.
- For `[MEMORY]`: draft the full memory body inline so the user can judge it before writing.
- For `[NEW SKILL]`: one sentence on what it does and what trigger phrase activates it.
- Prefer memory for transient project state; prefer CLAUDE.md for durable conventions.
- After applying, confirm what was written and where.

## How to improve this skill

This file is a cached copy of `claude-skills/skills/learn/SKILL.md` in
[beyond-scale-group/bsg-stack](https://github.com/beyond-scale-group/bsg-stack).
That repo is the single source of truth — `~/.claude/skills/learn/SKILL.md` is
overwritten every time the BSG install flow runs.

If the user asks you to improve, fix, or extend this skill, do **not** edit
the local file. Instead:

1. `gh repo clone beyond-scale-group/bsg-stack` (or work in an existing clone)
2. Edit `claude-skills/skills/learn/SKILL.md` on a feature branch
3. Open a pull request against `main`

Bug reports and ideas without a fix → open an issue on the same repo.
