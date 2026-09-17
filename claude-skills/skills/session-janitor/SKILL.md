---
name: session-janitor
description: >
  Machine-scoped janitor for live Claude Code sessions. Walks every
  running session on the host, resolves each to its repository, branch,
  PR and ticket, and reports which ones are safe to close because their
  work has already landed. Read-only in this release. Use when the user
  asks "which sessions can I close?", "clean up my Claude sessions",
  "why is Claude eating my RAM?", "session janitor", "quelles sessions
  je peux fermer", or "nettoyer mes sessions".
version: 0.1.0
model: haiku
---

# /session-janitor — live session janitor

Machine-scoped, unlike every other BSG skill: its unit of work is a host
process, not a repository. It therefore exposes **no `tick`**, is not in
`registry.json`, and is not fired by `/tick-all`. Recurrence is the
user's own `/loop`, which CLAUDE.md sanctions.

Specified in [`claude-skills/prds/009-session-janitor.md`](../../prds/009-session-janitor.md).

## Verbs

| Verb | Read-only? | What it does |
|---|---|---|
| `doctor` | ✓ Yes | Print a scorecard of every live session and its verdict. Signals nothing, mutates nothing. |

`reap`, `sync` and `reconcile` are specified in PRD-009 and ship in later
lots. This release diagnoses only.

## Quick start

Bootstrap the helper from the installed copy — the only path that exists
from an arbitrary cwd — then let it resolve everything else, preferring the
repo copy when you are working inside `bsg-stack`:

```bash
source "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/scripts/_bsg-script-path.sh"
RESOLVER="$(bsg_script_path session-state.sh)"

# The scorecard
bash "$RESOLVER" | jq .

# Just the sessions that could be closed
bash "$RESOLVER" | jq -r 'select(.verdict == "reapable")'
```

Never invoke this skill's scripts through a bare `claude-skills/scripts/…`
path: it is repo-relative and resolves only inside `bsg-stack`, which is the
defect PRD-009 §10 records.

Under `/loop 30m /session-janitor`, stay silent unless a silence-breaker
in `references/doctor.md` fires.

## How to improve this skill

The shared catalog under `claude-skills/skills/session-janitor/` is
cached into every developer's `~/.claude/` on session start. **Edits to
the cached copy are wiped on the next sync** — always PR back to
`claude-skills/skills/session-janitor/SKILL.md` in this repo.

1. Edit the file in this repo's `claude-skills/skills/session-janitor/`.
2. Run `python3 claude-skills/tests/test_skills.py` and
   `bash claude-skills/tests/test_session_state.sh`.
3. Open a PR — your local cached copy will pick up the new content
   on the next `SessionStart`.
