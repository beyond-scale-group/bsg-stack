# BSG STACK — THE INFRASTRUCTURE THAT RUNS THE EMPIRE

*"You don't scale an empire with copy-paste. You scale it with a stack."*

---

## The Story

It started with a simple problem: every new software company acquired by BSG came with its own CI/CD workflows, its own conventions, its own duct tape. Three acquisitions in, we had three different Scala pipelines, two ways to deploy on Clever Cloud, and zero consistency.

We did what any engineer would do: we centralized. One repo, reusable workflows, shared conventions. But we didn't stop there.

Because BSG isn't a fund that buys and flips. It's a **forever hold**. Every piece of software we acquire, we keep. Forever. And when you're holding 50 software companies forever, you need a **shared stack** — not just workflows, but the entire connective tissue that ties the portfolio together: CI/CD, Renovate configs, Claude Code skills, release conventions, review apps, notifications.

**bsg-stack** is BSG's `gstack`. The shared technical foundation for every company in the group. One repo, one source of truth, zero duplication.

---

## What's in the Box

### GitHub Actions Workflows

Reusable workflows, ready to plug into any repo in the portfolio.

#### Build & Test

| Workflow | Description | Stack |
|----------|-------------|-------|
| `scala_test.yaml` | Compile, test, coverage (scoverage) | Scala 3 / sbt |
| `react_vite_test.yaml` | Build, lint, test | React / Vite / TypeScript |

#### Coverage & Reports

| Workflow | Description |
|----------|-------------|
| `cobertura_report.yaml` | Publish Cobertura coverage on PR |
| `junit_report.yaml` | Publish JUnit test results on PR checks |

#### Release & Versioning

| Workflow | Description |
|----------|-------------|
| `semantic_release.yaml` | Automated semantic versioning + changelog |
| `semantic_pull_request.yaml` | Enforce conventional commit PR titles |
| `create_release_branch.yaml` | Create release branches from tags, clean up old RCs |

#### Deployment

| Workflow | Description |
|----------|-------------|
| `clever_cloud_deploy.yaml` | Deploy to Clever Cloud PaaS |
| `docker_build_and_push.yaml` | Build multi-platform Docker images, push to registry |
| `review_app_deploy.yaml` | Terraform-based review apps for PRs on Clever Cloud |

#### Automation

| Workflow | Description |
|----------|-------------|
| `sync_branches.yaml` | Sync branches (e.g. main -> staging) |
| `sync_branches_with_ai.yaml` | Sync branches with AI-powered conflict resolution |
| `github_pull_request.yaml` | Create PRs with auto-merge and auto-approval |
| `pr_auto_add_project.yaml` | Auto-add PRs to GitHub Projects |
| `discord_notifier.yaml` | Send Discord notifications |

#### Maintenance

| Workflow | Description |
|----------|-------------|
| `cleanup_artifacts.yaml` | Delete old GitHub Actions artifacts |

For detailed inputs, secrets, and usage examples for each workflow, see
**[docs/workflows.md](docs/workflows.md)**.

### Renovate Configs

Shareable dependency management presets in [`renovate/`](renovate/) — see
[`renovate/README.md`](renovate/README.md) for details:

- `scala.json` — sbt projects (automerge patch/minor, manual major)
- `react.json` — npm projects (automerge patch/minor, manual major)

> The old paths `scala_config.json` / `react_config.json` remain as
> compatibility stubs and will be removed in `v2`.

### Claude Code Skills

Shared [Claude Code](https://claude.com/claude-code) slash commands,
skills, and subagents live under [`claude-skills/`](claude-skills/) — see
[`claude-skills/README.md`](claude-skills/README.md) for the component
overview and [`claude-skills/INSTALL.md`](claude-skills/INSTALL.md) for
the Claude-driven installer and current catalog.

---

## Quick Start

See [`INSTALL.md`](INSTALL.md) for the install guide covering every
component of the stack. For workflows specifically, reference them from
any repo in the group:

```yaml
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

That's it. No fork, no copy, no drift.

---

## The Philosophy

Every BSG software company inherits the stack automatically. New acquisition? Plug in the workflows, activate Renovate, install the Claude skills. Within an hour, the repo meets group standards.

This is the **BSG effect** applied to infrastructure: centralize to accelerate, standardize to scale, automate to free up human time.

50 software companies, one stack. That's how you build an empire.

---

## Versioning

This repo uses [semantic-release](https://github.com/semantic-release/semantic-release).
Reference workflows via tags: `@v1`, `@v1.0.0`, or `@main`.
