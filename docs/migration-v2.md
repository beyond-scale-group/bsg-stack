# Migration to `v2`

`v2` reorganises the repo as `bsg-stack` with category-prefixed workflow
filenames and dash-separated Renovate preset names. `v1` is frozen on
the old filenames; nothing breaks until you opt in to `v2` by bumping
your `uses:` and `extends:` references.

See [`docs/reorganisation-plan.md`](reorganisation-plan.md) for the full
rationale.

---

## Workflow renames

All 17 reusable workflows were renamed via `git mv` (history preserved):

| Old (`@v1`) | New (`@v2`) | Category |
|-------------|-------------|----------|
| `scala_test.yaml` | `test-scala.yaml` | test |
| `react_vite_test.yaml` | `test-react-vite.yaml` | test |
| `cobertura_report.yaml` | `report-cobertura.yaml` | report |
| `junit_report.yaml` | `report-junit.yaml` | report |
| `semantic_release.yaml` | `release-semantic.yaml` | release |
| `semantic_pull_request.yaml` | `release-pr-lint.yaml` | release |
| `create_release_branch.yaml` | `release-branch-create.yaml` | release |
| `clever_cloud_deploy.yaml` | `deploy-clever-cloud.yaml` | deploy |
| `docker_build_and_push.yaml` | `deploy-docker.yaml` | deploy |
| `review_app_deploy.yaml` | `deploy-review-app.yaml` | deploy |
| `sync_branches.yaml` | `auto-sync-branches.yaml` | auto |
| `sync_branches_with_ai.yaml` | `auto-sync-branches-ai.yaml` | auto |
| `github_pull_request.yaml` | `auto-pr-create.yaml` | auto |
| `pr_auto_add_project.yaml` | `auto-pr-add-project.yaml` | auto |
| `discord_notifier.yaml` | `auto-notify-discord.yaml` | auto |
| `cleanup_artifacts.yaml` | `maint-cleanup-artifacts.yaml` | maint |
| `claude_skills_test.yaml` | `ci-claude-skills-test.yaml` | ci (internal) |

Category prefixes (`test-`, `report-`, `release-`, `deploy-`, `auto-`,
`maint-`, `ci-`) give you grouping via alphabetical sort without
leaving the flat `.github/workflows/` dir that GitHub mandates.

## Renovate preset renames

| Old (`@v1`) | New (`@v2`) |
|-------------|-------------|
| `renovate/scala_config.json` | `renovate/scala.json` |
| `renovate/react_config.json` | `renovate/react.json` |

Compat stubs at the old paths shipped in `v2.0.0` and were removed in
`v2.1.0`. If your `renovate.json` currently extends
`…//renovate/scala_config`, update it to `…//renovate/scala` before
upgrading past `v2.0.x`.

---

## Consumer find/replace recipe

Run these against your repo (macOS `sed`; drop the `''` after `-i` on
GNU sed):

```bash
# The repo rename — GitHub redirects @v1 anyway, but clean it up:
sed -i '' 's|beyond-scale-group/bsg-workflows|beyond-scale-group/bsg-stack|g' .github/workflows/*.yml .github/workflows/*.yaml 2>/dev/null

# Workflow renames (and the @v1 → @v2 tag bump):
sed -i '' \
  -e 's|/scala_test\.yaml@v1|/test-scala.yaml@v2|g' \
  -e 's|/react_vite_test\.yaml@v1|/test-react-vite.yaml@v2|g' \
  -e 's|/cobertura_report\.yaml@v1|/report-cobertura.yaml@v2|g' \
  -e 's|/junit_report\.yaml@v1|/report-junit.yaml@v2|g' \
  -e 's|/semantic_release\.yaml@v1|/release-semantic.yaml@v2|g' \
  -e 's|/semantic_pull_request\.yaml@v1|/release-pr-lint.yaml@v2|g' \
  -e 's|/create_release_branch\.yaml@v1|/release-branch-create.yaml@v2|g' \
  -e 's|/clever_cloud_deploy\.yaml@v1|/deploy-clever-cloud.yaml@v2|g' \
  -e 's|/docker_build_and_push\.yaml@v1|/deploy-docker.yaml@v2|g' \
  -e 's|/review_app_deploy\.yaml@v1|/deploy-review-app.yaml@v2|g' \
  -e 's|/sync_branches_with_ai\.yaml@v1|/auto-sync-branches-ai.yaml@v2|g' \
  -e 's|/sync_branches\.yaml@v1|/auto-sync-branches.yaml@v2|g' \
  -e 's|/github_pull_request\.yaml@v1|/auto-pr-create.yaml@v2|g' \
  -e 's|/pr_auto_add_project\.yaml@v1|/auto-pr-add-project.yaml@v2|g' \
  -e 's|/discord_notifier\.yaml@v1|/auto-notify-discord.yaml@v2|g' \
  -e 's|/cleanup_artifacts\.yaml@v1|/maint-cleanup-artifacts.yaml@v2|g' \
  .github/workflows/*.yml .github/workflows/*.yaml 2>/dev/null

# Renovate preset rename (if you use bsg presets):
sed -i '' \
  -e 's|//renovate/scala_config|//renovate/scala|g' \
  -e 's|//renovate/react_config|//renovate/react|g' \
  renovate.json 2>/dev/null
```

Run `git diff` to verify, then commit as a single `chore(ci): migrate to bsg-stack v2` PR.

---

## Why

- **Category prefixes** surface "what kind of workflow is this?" at a glance in the flat `.github/workflows/` dir GitHub forces on us.
- **Dashes over underscores** matches the GitHub / marketplace convention.
- **`_config` dropped from preset names** — redundant inside `renovate/`.
- **Single `v2` cut** over drip-fed renames — one migration, one PR per consumer, done.

## What hasn't changed

- Workflow inputs, outputs, secrets, and behaviour are unchanged — this is a rename-only break.
- `@v1` keeps working on the old filenames for as long as you need to stay there.
- GitHub's repo-rename redirect means `beyond-scale-group/bsg-workflows` still resolves.

## Need help?

Open an issue on [beyond-scale-group/bsg-stack](https://github.com/beyond-scale-group/bsg-stack) — migration PRs welcome.
