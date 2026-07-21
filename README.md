<div align="center">

<img src="assets/logo-bsg-holding.png" alt="Beyond Scale Group" height="96">

# Beyond Scale Group

**BSG Stack** — the shared Claude Code skills, CI/CD workflows, and autonomous
agents every company in the portfolio inherits. One repo, one source of truth.

</div>

---

## The stack

| Component | What it is |
|---|---|
| [**claude-skills/**](claude-skills/) | Claude Code skills, slash commands & subagents |
| [**renovate/**](renovate/) | Shared Renovate dependency-update presets |
| [**deploy/**](deploy/) | One-command deployment configs |
| [**docs/**](docs/) | Workflows, migration guides & reference |

## Get started

- **[INSTALL.md](INSTALL.md)** — install every component of the stack
- **[docs/workflows.md](docs/workflows.md)** — the reusable GitHub Actions workflows
- **[claude-skills/INSTALL.md](claude-skills/INSTALL.md)** — the skills & agents catalog

Reference a workflow from any repo in the group — no fork, no copy, no drift:

```yaml
jobs:
  test:
    uses: beyond-scale-group/bsg-stack/.github/workflows/test-scala.yaml@v2
    with:
      jdk: "21"
```

Versioning: `@v2` (current), `@v1` (frozen), `@vX.Y.Z` (exact). Migrating from
v1? See [docs/migration-v2.md](docs/migration-v2.md).

---

<div align="center"><sub><a href="https://bsg-holding.fr">Beyond Scale Group</a> — 50 companies, one stack.</sub></div>
