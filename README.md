# bsg-workflows

Reusable GitHub Actions workflows for BSG projects.

## Available Workflows

### Build & Test

| Workflow | Description | Stack |
|----------|-------------|-------|
| `scala_test.yaml` | Compile, test, coverage (scoverage) | Scala 3 / sbt |
| `react_vite_test.yaml` | Build, lint, test | React / Vite / TypeScript |

### Coverage & Reports

| Workflow | Description |
|----------|-------------|
| `cobertura_report.yaml` | Publish Cobertura coverage on PR |
| `junit_report.yaml` | Publish JUnit test results on PR checks |

### Release & Versioning

| Workflow | Description |
|----------|-------------|
| `semantic_release.yaml` | Automated semantic versioning + changelog |
| `semantic_pull_request.yaml` | Enforce conventional commit PR titles |

### Deployment

| Workflow | Description |
|----------|-------------|
| `clever_cloud_deploy.yaml` | Deploy to Clever Cloud PaaS |

### Automation

| Workflow | Description |
|----------|-------------|
| `sync_branches.yaml` | Sync branches (e.g. main → staging) |
| `pr_auto_add_project.yaml` | Auto-add PRs to GitHub Projects |
| `discord_notifier.yaml` | Send Discord notifications |

## Usage

Reference workflows from your repo:

```yaml
jobs:
  test:
    uses: beyond-scale-group/bsg-workflows/.github/workflows/scala_test.yaml@v1
    with:
      jdk: "21"
      working_directory: apps/backend/my-scala-app

  semantic-pr:
    uses: beyond-scale-group/bsg-workflows/.github/workflows/semantic_pull_request.yaml@v1
    with:
      scopes: "backend, frontend, ci, docs"
```

## Renovate Configs

Shareable Renovate presets in `renovate/`:

- `scala_config.json` — sbt projects (automerge patch/minor, manual major)
- `react_config.json` — npm projects (automerge patch/minor, manual major)

## Versioning

This repo uses [semantic-release](https://github.com/semantic-release/semantic-release).
Reference workflows via tags: `@v1`, `@v1.0.0`, or `@main`.
