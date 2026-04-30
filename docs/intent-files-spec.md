# Intent Files Specification

Per-repo domain intent files let agents adapt their behavior to the specific
context of a repository without requiring agent-specific configuration syntax.
Each file is plain markdown written for human readers — agents extract signals
from free text.

## Convention

One file per domain, placed at the repo root, with a naturally-named filename:

| Agent | File | Purpose |
|-------|------|---------|
| `@po-manager` | `ROADMAP.md` | Vision, milestones, stale threshold, disabled agents |
| `@tech-lead` | `ARCHITECTURE.md` | Stack, complexity rules, accepted tech debt, ADR directory |
| `@security` | `SECURITY.md` | Supported versions, reporting contact, scope, accepted risks |
| `@qa` | `QUALITY.md` | Testing strategy, coverage targets, definition of done |
| `@seo` | `SEO.md` | Target keywords, priority pages, canonical strategy |
| `@marketing` | `MARKETING.md` | Positioning, audience, content calendar, campaign cadence |
| `@storytelling` | `BRAND.md` | Voice guidelines, tone, key messages, positioning bible |
| `@pr-comms` | `COMMS.md` | Press contacts, announcement cadence, embargo rules |

## Design constraints

- **Files are human-first.** No agent-specific syntax. A new hire reads
  `BRAND.md` and understands the voice without knowing `@storytelling` exists.
- **Backward compatible.** Absent file = agent runs with its built-in defaults.
- **Agents declare what they read.** Each agent's catalog entry lists its
  intent file and the signals it extracts — so authors know what to write.
- **No enforcement of structure.** Agents reason about free text, not parsed
  keys. A missing section is silently skipped.

## How agents read intent files

Agents use the shared helper instead of reading files directly:

```bash
roadmap="$(bash claude-skills/scripts/read-intent-file.sh ROADMAP.md)"
if [ -n "$roadmap" ]; then
  # extract signals from $roadmap and adjust defaults
fi
```

The helper (`claude-skills/scripts/read-intent-file.sh`):
- Prints the file contents to stdout when the file exists.
- Exits 0 with empty output when the file is absent.
- Exits 1 when called without an argument.
- Respects `INTENT_FILE_BASEDIR` env var for testing.

Using the helper (rather than reading files directly) allows future
enhancements — caching, validation, fallbacks — without touching every agent.

## Scaffolding

Starter templates for all 8 intent files live in `claude-skills/templates/`.
Copy the relevant template to your repo root and fill it in:

```bash
cp claude-skills/templates/ROADMAP.md ./ROADMAP.md
# edit ROADMAP.md to match your project
```

## Tick-all integration

If `ROADMAP.md` contains a `## Disabled agents` section listing agent names,
`/tick-all` respects it as the canonical disabled-agents list and skips
those agents for the current repo.

## Related

- `CLAUDE.md` — session-context pattern; intent files follow the same philosophy
- `claude-skills/agents/registry.json` — agent catalog
- `claude-skills/scripts/read-intent-file.sh` — the shared reader helper
- `claude-skills/templates/` — starter templates for all 8 intent files
- Issue #62 — original spec
