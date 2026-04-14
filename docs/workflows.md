# Workflows Reference

Complete reference for all reusable GitHub Actions workflows in this repository.

---

## Build & Test

### `scala_test.yaml`

Compiles and runs Scala tests with optional code coverage reporting (scoverage).

| Input | Type | Required | Default | Description |
|-------|------|----------|---------|-------------|
| `jdk` | string | No | `"21"` | JDK version |
| `sbt_cmd` | string | No | `"compile test"` | sbt command to run |
| `coverage` | boolean | No | `true` | Enable coverage reporting |
| `report_artifact` | string | No | `"scala-coverage-report"` | Artifact name for coverage report |
| `runs_on` | string | No | `"ubuntu-latest"` | Runner to use |
| `working_directory` | string | No | `"."` | Working directory |
| `timeout` | number | No | `15` | Job timeout in minutes |
| `java_distribution` | string | No | `"temurin"` | Java distribution |

**Secrets:** None

```yaml
jobs:
  test:
    uses: beyond-scale-group/bsg-stack/.github/workflows/scala_test.yaml@v1
    with:
      jdk: "21"
      working_directory: apps/backend/my-app
```

---

### `react_vite_test.yaml`

Builds and lints a React/Vite project with optional testing.

| Input | Type | Required | Default | Description |
|-------|------|----------|---------|-------------|
| `node_version` | string | No | `"22"` | Node.js version |
| `working_directory` | string | No | `"."` | Working directory |
| `build_cmd` | string | No | `"npm run build"` | Build command |
| `lint_cmd` | string | No | `"npm run lint"` | Lint command |
| `test_cmd` | string | No | `""` | Test command (empty to skip) |
| `runs_on` | string | No | `"ubuntu-latest"` | Runner to use |
| `timeout` | number | No | `10` | Job timeout in minutes |

**Secrets:** None

```yaml
jobs:
  test:
    uses: beyond-scale-group/bsg-stack/.github/workflows/react_vite_test.yaml@v1
    with:
      node_version: "22"
      working_directory: apps/frontend
```

---

## Coverage & Reports

### `cobertura_report.yaml`

Publishes Cobertura XML coverage reports with diff analysis against a base branch.

| Input | Type | Required | Default | Description |
|-------|------|----------|---------|-------------|
| `report_path` | string | No | `"coverage.xml"` | Path to Cobertura XML report |
| `min_coverage` | number | No | `0` | Minimum coverage threshold (%) |
| `diff_branch` | string | No | `"main"` | Branch to diff coverage against |
| `runs_on` | string | No | `"ubuntu-latest"` | Runner to use |
| `report_artifact` | string | No | `"scala-coverage-report"` | Artifact name to download |

**Secrets:** None

---

### `junit_report.yaml`

Publishes JUnit XML test reports as GitHub check annotations.

| Input | Type | Required | Default | Description |
|-------|------|----------|---------|-------------|
| `report_name` | string | No | `"Test Results"` | Name of the report check |
| `report_path` | string | No | `"**/target/test-reports/**/*.xml"` | Path to JUnit XML report(s) |
| `runs_on` | string | No | `"ubuntu-latest"` | Runner to use |
| `report_artifact` | string | No | `"scala-coverage-report"` | Artifact name to download |

**Secrets:** None

---

## Release & Versioning

### `semantic_release.yaml`

Automated semantic versioning and changelog generation from commit history.

| Input | Type | Required | Default | Description |
|-------|------|----------|---------|-------------|
| `semantic_version` | string | No | `"24.1.2"` | semantic-release version |
| `extra_plugins` | string | No | `""` | Extra plugins (space-separated) |
| `runs_on` | string | No | `"ubuntu-latest"` | Runner to use |
| `working_directory` | string | No | `"."` | Working directory |

**Secrets:**
- `token` (required) — GitHub token with push and release permissions

---

### `semantic_pull_request.yaml`

Validates that PR titles follow conventional commit message conventions.

| Input | Type | Required | Default | Description |
|-------|------|----------|---------|-------------|
| `scopes` | string | No | `""` | Allowed scopes (newline-separated) |
| `runs_on` | string | No | `"ubuntu-latest"` | Runner to use |

**Secrets:** None (uses `GITHUB_TOKEN`)

---

### `create_release_branch.yaml`

Creates release branches from tags and cleans up older release candidate branches.

| Input | Type | Required | Default | Description |
|-------|------|----------|---------|-------------|
| `tag` | string | Yes | — | Tag to create the release branch from (e.g. `v1.2.0`) |
| `dry_run` | boolean | No | `false` | If true, only print what would happen |
| `cleanup_rc` | boolean | No | `true` | Delete older release candidate branches |
| `runs_on` | string | No | `"ubuntu-latest"` | Runner to use |

**Secrets:** None

---

## Deployment

### `clever_cloud_deploy.yaml`

Deploys an application to Clever Cloud with branch guards and optional self-hosted runner detection.

| Input | Type | Required | Default | Description |
|-------|------|----------|---------|-------------|
| `app_id` | string | Yes | — | Clever Cloud application ID |
| `environment` | string | No | `""` | Environment label (PROD, STG, etc.) |
| `service_name` | string | No | `""` | Service name for display in logs |
| `expected_branch` | string | No | `""` | Branch allowed to deploy (empty to skip check) |
| `same_commit_policy` | string | No | `""` | Policy when same commit is already deployed (`restart`, `ignore`, `error`) |
| `runs_on` | string | No | `"ubuntu-latest"` | Runner to use |
| `timeout` | number | No | `20` | Job timeout in minutes |
| `auto_detect_runner` | boolean | No | `false` | Auto-detect self-hosted runner availability |

**Secrets:**
- `clever_token` (required) — Clever Cloud API token
- `clever_secret` (required) — Clever Cloud API secret
- `runner_check_token` (optional) — GitHub token to check self-hosted runner availability

---

### `docker_build_and_push.yaml`

Builds multi-platform Docker images and pushes to a container registry (defaults to GHCR).

| Input | Type | Required | Default | Description |
|-------|------|----------|---------|-------------|
| `runs_on` | string | No | `"ubuntu-latest"` | Runner to use |
| `working_directory` | string | No | `"."` | Working directory |
| `registry` | string | No | `"ghcr.io"` | Container registry |
| `image_name` | string | No | `""` | Docker image name (defaults to repository name) |
| `image_tag` | string | No | `""` | Docker image tag (defaults to git ref name) |
| `platforms` | string | No | `"linux/amd64,linux/arm64"` | Docker build platforms |
| `build_args` | string | No | `""` | Build arguments (newline-separated `KEY=VALUE`) |

**Secrets:**
- `registry_username` (optional) — Registry username (defaults to `github.actor` for GHCR)
- `registry_password` (optional) — Registry password/token (defaults to `GITHUB_TOKEN` for GHCR)

---

### `review_app_deploy.yaml`

Deploys temporary review apps for PRs using Terraform and Clever Cloud, with optional AI conflict resolution.

| Input | Type | Required | Default | Description |
|-------|------|----------|---------|-------------|
| `app_name` | string | Yes | — | App identifier |
| `terraform_dir` | string | Yes | — | Path to Terraform config |
| `deploy_path` | string | Yes | — | Path to deploy (monorepo subfolder) |
| `state_prefix` | string | Yes | — | Terraform state prefix |
| `organization_id` | string | Yes | — | Clever Cloud organization ID |
| `backend_url_var` | string | No | `""` | Env var name for backend URL |
| `backend_check_path` | string | No | `""` | Path to check for backend changes |
| `staging_backend_url` | string | No | `""` | Staging backend URL (fallback) |
| `pr_number` | string | Yes | — | PR number |
| `head_sha` | string | Yes | — | Commit SHA to deploy |
| `head_ref` | string | No | `""` | Branch name |
| `base_ref` | string | No | `"staging"` | Base branch |
| `action` | string | No | `"deploy"` | `deploy` or `cleanup` |
| `s3_cleanup_prefix` | string | No | `""` | S3 prefix for cleanup (`{pr}` replaced by PR number) |
| `tf_var_postgresql_addon_id` | string | No | `""` | PostgreSQL addon ID |
| `tf_var_cellar_addon_id` | string | No | `""` | Cellar addon ID |
| `tf_var_s3_bucket` | string | No | `""` | S3 bucket name |
| `tf_var_backend_url_internal` | string | No | `""` | Scala backend URL for server-side calls |
| `runs_on` | string | No | `"ubuntu-latest"` | Runner to use |
| `timeout` | number | No | `30` | Job timeout in minutes |

**Secrets:**
- `clever_token` (required), `clever_secret` (required) — Clever Cloud credentials
- `s3_access_key` (required), `s3_secret_key` (required) — S3 credentials
- `anthropic_api_key` (optional) — Anthropic API key for AI features
- `mistral_api_key` (optional), `backend_api_key` (optional), `google_api_key` (optional), `jwt_secret` (optional)

---

## Automation

### `sync_branches.yaml`

Merges a source branch into a target branch automatically.

| Input | Type | Required | Default | Description |
|-------|------|----------|---------|-------------|
| `from` | string | No | `"main"` | Source branch |
| `to` | string | No | `"staging"` | Target branch |
| `runs_on` | string | No | `"ubuntu-latest"` | Runner to use |

**Secrets:** None

---

### `sync_branches_with_ai.yaml`

Syncs branches with AI-powered merge conflict resolution and optional PR creation.

| Input | Type | Required | Default | Description |
|-------|------|----------|---------|-------------|
| `from` | string | No | `"main"` | Source branch |
| `to` | string | No | `"staging"` | Target branch |
| `ai_resolve` | boolean | No | `false` | Use AI to resolve merge conflicts |
| `ai_resolve_script` | string | No | `".github/scripts/resolve-conflicts-with-claude.sh"` | Path to AI conflict resolution script |
| `create_pr` | boolean | No | `true` | Create a PR instead of direct push |
| `runs_on` | string | No | `"ubuntu-latest"` | Runner to use |

**Secrets:**
- `token` (required) — GitHub token with push and PR permissions
- `anthropic_api_key` (optional) — Anthropic API key for AI conflict resolution

---

### `github_pull_request.yaml`

Creates a pull request between branches with optional auto-merge and auto-approval via GitHub App authentication.

| Input | Type | Required | Default | Description |
|-------|------|----------|---------|-------------|
| `from` | string | Yes | — | Source branch |
| `base` | string | Yes | — | Target branch |
| `branch` | string | Yes | — | Intermediate branch name for the PR |
| `title` | string | Yes | — | Pull request title |
| `labels` | string | No | `""` | Comma-separated labels |
| `auto_merge` | string | No | `"true"` | Enable auto-merge on creation |
| `approve` | string | No | `"true"` | Auto-approve the PR |
| `bot_app_id` | string | Yes | — | GitHub App ID for authentication |
| `runs_on` | string | No | `"ubuntu-latest"` | Runner to use |

**Secrets:**
- `bot_private_key` (required) — GitHub App private key

---

### `pr_auto_add_project.yaml`

Automatically adds pull requests to a GitHub Project board.

| Input | Type | Required | Default | Description |
|-------|------|----------|---------|-------------|
| `project_url` | string | Yes | — | GitHub Project URL |

**Secrets:**
- `token` (optional) — GitHub token with project permissions (defaults to `github.token`)

---

### `discord_notifier.yaml`

Sends notifications to a Discord channel via webhook.

| Input | Type | Required | Default | Description |
|-------|------|----------|---------|-------------|
| `title` | string | Yes | — | Notification title |
| `description` | string | Yes | — | Notification message |
| `color` | string | No | `"0x5865F2"` | Embed color (hex) |
| `runs_on` | string | No | `"ubuntu-latest"` | Runner to use |

**Secrets:**
- `discord_webhook_url` (required) — Discord webhook URL

---

## Maintenance

### `cleanup_artifacts.yaml`

Deletes old GitHub Actions artifacts based on age and optional name pattern matching.

| Input | Type | Required | Default | Description |
|-------|------|----------|---------|-------------|
| `patterns` | string | No | `""` | Comma-separated artifact name prefixes to match |
| `max_age_hours` | number | No | `24` | Delete artifacts older than this (hours) |
| `runs_on` | string | No | `"ubuntu-latest"` | Runner to use |

**Secrets:** None
