# BSG Stack — Install Guide

This is the entry point for installing any component of the **BSG Stack**
into a repo or a developer machine.

The stack is modular — install only the components you need. Each component
has its own install path; this file is the index that points to the
component-specific `INSTALL.md` or install snippet.

---

## Components at a glance

| Component | What it's for | Install path |
|-----------|---------------|--------------|
| [GitHub Actions workflows](#1-github-actions-workflows) | Reusable CI/CD workflows (test, deploy, release, automation) | Inline — reference by `uses:` in caller repos |
| [Renovate presets](#2-renovate-presets) | Shared dependency-update configuration for sbt and npm projects | Inline — `extends` in a `renovate.json` |
| [Claude Code skills](#3-claude-code-skills) | Shared slash commands, skills, and subagents for Claude Code | Full installer — see [`claude-skills/INSTALL.md`](claude-skills/INSTALL.md) |

---

## 1. GitHub Actions workflows

**No installation.** Reference workflows directly from any repo in the
portfolio via `uses:`:

```yaml
# .github/workflows/ci.yaml in your repo
jobs:
  test:
    uses: beyond-scale-group/bsg-stack/.github/workflows/scala_test.yaml@v1
    with:
      jdk: "21"
      working_directory: apps/backend/my-scala-app

  semantic-pr:
    uses: beyond-scale-group/bsg-stack/.github/workflows/semantic_pull_request.yaml@v1
    with:
      scopes: "backend, frontend, ci, docs"
```

Pin with a tag:

- `@v1` — latest major (recommended for most callers).
- `@v1.2.3` — exact version (for reproducibility-sensitive pipelines).
- `@main` — bleeding edge (not recommended outside this repo).

The full reference for every workflow — inputs, secrets, examples — lives
in [`docs/workflows.md`](docs/workflows.md).

---

## 2. Renovate presets

**No installation.** Reference a preset from your repo's `renovate.json`
using Renovate's cross-repo preset syntax:

```json
{
  "$schema": "https://docs.renovatebot.com/renovate-schema.json",
  "extends": [
    "github>beyond-scale-group/bsg-stack//renovate/scala_config"
  ]
}
```

Available presets (pick whichever matches your project):

| Preset | Use for |
|--------|---------|
| `github>beyond-scale-group/bsg-stack//renovate/scala_config` | sbt / Scala projects |
| `github>beyond-scale-group/bsg-stack//renovate/react_config` | npm / React projects |

Both presets automerge patch and minor updates and hold major updates for
human review. Override any rule in your own `renovate.json` — `extends` is
merged, not replaced.

---

## 3. Claude Code skills

This component has a **full install flow** because it writes files into
your `~/.claude/` directory on your machine.

### Quick install

In any Claude Code session, ask:

> Install the BSG Claude skills by following
> https://raw.githubusercontent.com/beyond-scale-group/bsg-stack/main/claude-skills/INSTALL.md

Claude will fetch that file, drop an updater script into
`~/.claude/scripts/`, run it once, and register a `SessionStart` hook so
every new Claude Code session pulls the latest skills automatically.

### What gets installed

- **Slash commands** → `~/.claude/commands/` (e.g. `/babysit`)
- **Skills** → `~/.claude/skills/` (e.g. `po-report`)
- **Subagents** → `~/.claude/agents/` (e.g. `po-manager`)

The updater only overwrites files it owns (tracked in a local manifest),
so files you've added yourself are never clobbered.

### To update

Ask the same question again in any Claude Code session — or just start a
new session and let the hook run. Either way, the latest versions from
`main` land in `~/.claude/`.

Full details, catalog, and contribution guidelines:
**[`claude-skills/INSTALL.md`](claude-skills/INSTALL.md)**.

---

## Contributing a new component

If the stack grows a new component (e.g. shared Dockerfiles, shared
Terraform modules), follow the same pattern:

1. Add a top-level directory for the component.
2. Add a `<component>/INSTALL.md` if the install flow is non-trivial,
   otherwise an install snippet inline in this file is enough.
3. Link it from the "Components at a glance" table above.
4. Document it in the root [`README.md`](README.md).

---

## Questions

- Workflow doesn't cover your use case → open an issue or PR in
  [beyond-scale-group/bsg-stack](https://github.com/beyond-scale-group/bsg-stack).
- Bug in a Claude skill → see "How to improve this skill" at the bottom
  of each skill file, or open a PR against `claude-skills/`.
- Want a new preset or workflow → PR welcome; keep it generic enough to
  serve more than one repo in the portfolio.
