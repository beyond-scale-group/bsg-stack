# Migration guide: legacy paths → `.bsg/`

ADR-001 consolidates every per-repo BSG agent custom doc under a single
`.bsg/` directory at the repo root, replacing the ~9 sibling folders
(`po/`, `brand/`, `seo/`, `marketing/`, `comms/`, `adr/`, `qa/`, plus
the dotfile `.bsg-autopilot.yml` and `.securityignore`).

This guide documents what moves, when, and how to migrate a consumer
repo without breaking cached `claude-skills/` installs.

## Why migrate

- One folder to inspect, archive, `.gitignore`, or pass to `/bsg-stack
  doctor` instead of nine
- Dot-prefix matches the `.github/`-style "infra, not product" signal
- Future agents stop adding new top-level folders
- Cross-cutting tooling (`/bsg-stack`, `_bsg-paths.sh`) only has to
  enumerate one tree

## What moves

| Legacy path                      | New path                        | Doc kind          |
|----------------------------------|---------------------------------|-------------------|
| `po/PLAN.md`                     | `.bsg/PLAN.md`                  | `plan`            |
| `po/reports/<date>-*.md`         | `.bsg/reports/po/<date>-*.md`   | `reports`         |
| `brand/NARRATIVE.md`             | `.bsg/NARRATIVE.md`             | `narrative`       |
| `brand/templates/`               | `.bsg/brand/templates/`         | `brand`           |
| `brand/tokens.json`              | `.bsg/brand/tokens.json`        | `brand`           |
| `seo/KEYWORDS.md`                | `.bsg/KEYWORDS.md`              | `keywords`        |
| `seo/reports/`                   | `.bsg/reports/seo/`             | `reports`         |
| `marketing/CALENDAR.md`          | `.bsg/CALENDAR.md`              | `calendar`        |
| `marketing/reports/`             | `.bsg/reports/marketing/`       | `reports`         |
| `comms/ANNOUNCED.md`             | `.bsg/ANNOUNCED.md`             | `announced`       |
| `comms/reports/`                 | `.bsg/reports/comms/`           | `reports`         |
| `adr/`                           | `.bsg/adr/`                     | `adr`             |
| `qa/reports/`                    | `.bsg/reports/qa/`              | `reports`         |
| `.securityignore`                | `.bsg/SECURITYIGNORE`           | `securityignore`  |
| `.bsg-autopilot.yml`             | `.bsg/AUTOPILOT.yml`            | `autopilot`       |
| _(new — ADR-003)_                | `.bsg/DESIGN.md`                | `design`          |

## How resolution works during the migration

`claude-skills/scripts/_bsg-paths.sh` exposes:

```bash
# shellcheck source=_bsg-paths.sh disable=SC1091
source "$(dirname "$0")/_bsg-paths.sh"

plan="$(bsg_doc_path plan)"          # → ".bsg/PLAN.md" if it exists,
                                     #   else "po/PLAN.md"
auto="$BSG_AUTOPILOT_FILE"           # same idea, pre-resolved
```

The resolver:

1. Returns the `.bsg/` path when it exists on disk
2. Otherwise returns the legacy path (so `[[ -f "$path" ]]` still
   doubles as a presence test)
3. Returns the `.bsg/` path when neither exists, so first writes go
   into the new tree

**Hard rule for new code: never hardcode either path.** Always go
through `bsg_doc_path` or `BSG_AUTOPILOT_FILE`. Adding a new doc kind
is a one-line addition to the `case` block in `_bsg-paths.sh`.

## Migrating a consumer repo

The fallback is intentional — every consumer repo can migrate at its
own pace without breaking cached installs. The recommended sequence:

1. **Update your cache.** `update-bsg-skills.py` (run automatically on
   `SessionStart`) refreshes `~/.claude/skills/` with the resolver-aware
   scripts. No-op if you've session-started since `_bsg-paths.sh`
   landed.

2. **Bootstrap `.bsg/`** if it doesn't exist:

   ```bash
   mkdir -p .bsg/{adr,brand/templates,reports/{po,qa,tech,seo,marketing,security,storytelling,comms}}
   ```

3. **Move docs one at a time** (each is a one-PR move; agents keep
   working through the resolver during the move):

   ```bash
   git mv po/PLAN.md          .bsg/PLAN.md
   git mv brand/NARRATIVE.md  .bsg/NARRATIVE.md
   git mv seo/KEYWORDS.md     .bsg/KEYWORDS.md
   git mv marketing/CALENDAR.md .bsg/CALENDAR.md
   git mv comms/ANNOUNCED.md  .bsg/ANNOUNCED.md
   git mv .bsg-autopilot.yml  .bsg/AUTOPILOT.yml
   git mv .securityignore     .bsg/SECURITYIGNORE
   git mv adr                 .bsg/adr
   ```

4. **Move dated reports** under the unified `.bsg/reports/<agent>/`
   tree:

   ```bash
   for agent in po qa tech seo marketing security storytelling comms; do
     [[ -d "$agent/reports" ]] && git mv "$agent/reports" ".bsg/reports/$agent"
   done
   ```

5. **Verify with `/bsg-stack doctor`.** Each row should show the
   `.bsg/` path with `✓ present`. Rows still showing `legacy path —
   migrate to .bsg/` mean the move missed that doc.

6. **Commit and PR.** Auto-merge the move PR. Agents on the next tick
   write into `.bsg/` because the resolver picks it up.

## Rules for catalog (this repo) vs consumer repos

`bsg-stack` itself is currently mid-migration: the resolver and tests
already prefer `.bsg/` paths, but `.bsg/PLAN.md`, `.bsg/NARRATIVE.md`,
etc. don't all exist yet because the agents that own them haven't
shipped their `--init` (#237 deliverable #2). Until they do, `doctor`
will report those agents as `✗ missing` here, which is expected.

For consumer repos the fallback is the migration path. For this repo
the fallback is mostly a holdover — once each agent's `--init` is
wired and a first run lands its `.bsg/<DOC>`, the legacy fallback
becomes dead code.

## When the fallback goes away

Per ADR-001, the legacy fallback in `_bsg-paths.sh` is dropped one
release window after every `output: pr` agent has been observed
writing to `.bsg/` in production. There is no flag day; the dead
fallback branch in the resolver is removed in a separate PR with a
visible deprecation notice in `update-bsg-skills.py` for the prior
release.

Until then: `bsg_doc_path` and `$BSG_AUTOPILOT_FILE` are the only
correct way to reference any of the docs in the table above.
