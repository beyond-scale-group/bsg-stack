# BSG Stack — Reorganisation Plan

Execution plan for renaming `bsg-workflows` → `bsg-stack` and reorganising
the repo to reflect the "stack of components" framing.

This plan is grouped into **phases** so each merges independently and the
breaking parts are isolated behind a `v2` tag. `v1` stays frozen on the
old names; consumers opt in to `v2` by bumping their `uses:` references.

---

## Target layout

```
bsg-stack/
├── README.md                    # Stack overview + philosophy
├── INSTALL.md                   # Install guide / index of sub-INSTALL.md
├── CHANGELOG.md
├── .releaserc
├── renovate.json                # This repo's own renovate config
├── stack.yaml                   # NEW — declarative component manifest
│
├── .github/
│   └── workflows/               # Flat (GitHub constraint) with category prefixes
│       ├── test-scala.yaml
│       ├── test-react-vite.yaml
│       ├── report-cobertura.yaml
│       ├── report-junit.yaml
│       ├── release-semantic.yaml
│       ├── release-pr-lint.yaml
│       ├── release-branch-create.yaml
│       ├── deploy-clever-cloud.yaml
│       ├── deploy-docker.yaml
│       ├── deploy-review-app.yaml
│       ├── auto-sync-branches.yaml
│       ├── auto-sync-branches-ai.yaml
│       ├── auto-pr-create.yaml
│       ├── auto-pr-add-project.yaml
│       ├── auto-notify-discord.yaml
│       ├── maint-cleanup-artifacts.yaml
│       └── ci-claude-skills-test.yaml   # internal
│
├── renovate/                    # Component: dependency presets
│   ├── README.md                        # NEW
│   ├── scala.json                       # was: scala_config.json
│   └── react.json                       # was: react_config.json
│
├── claude-skills/               # Component: shared Claude Code skills
│   ├── README.md                        # NEW
│   ├── INSTALL.md                       # source of truth for skills install
│   ├── manifest.json                    # NEW — explicit index
│   ├── agents/
│   ├── commands/
│   ├── skills/
│   ├── scripts/
│   └── tests/
│
└── docs/
    ├── workflows.md                     # single-file index (Ctrl-F friendly)
    ├── workflows/                       # NEW — per-workflow deep-dives (future)
    ├── renovate.md                      # NEW
    ├── claude-skills.md                 # NEW (thin — links to claude-skills/INSTALL.md)
    ├── migration-v2.md                  # NEW — old→new mapping for consumers
    └── reorganisation-plan.md           # THIS FILE
```

### Design rationale

| Change | Rationale |
|--------|-----------|
| Category prefix on workflow filenames (`test-`, `deploy-`, `release-`, `auto-`, `maint-`, `report-`, `ci-`) | GitHub forces a flat dir under `.github/workflows/`. Prefixes give "folders for free" via alphabetical sort + consistent grep. Matches how the README already groups them. |
| Dash over underscore | GitHub community + marketplace convention. One-time pain preserved behind `@v1`. |
| `renovate/scala.json` vs `scala_config.json` | `_config` is redundant inside `renovate/`. |
| `README.md` in each component dir | Makes each folder browsable standalone on GitHub. The stack philosophy is "each piece is a real component" — treat them that way. |
| `docs/workflows/` reserved subdir | Not populated now; home for deep-dives when a workflow is complex enough (e.g. `deploy-review-app` is already 314 lines). |
| No split of `workflows.md` yet | 319-line single file is still easier to Ctrl-F than 17 small files. Defer. |

### Deliberate non-changes

- **Not renaming `.github/`** — GitHub-mandated.
- **Not adopting per-component independent semver** — monorepo versioning (one `@v2` tag for the whole stack) is simpler for the portfolio's mental model ("pin the stack, not each piece"). Revisit only if one component churns much faster than the rest.
- **Not moving to `packages/` or `apps/` monorepo layout** — would obscure the flat "here are the reusable workflows" story that makes this repo easy to consume.

---

## Phase 0 — Pre-flight (no code changes)

**Goal:** make the rename reversible and communicate it.

- [ ] **0.1** Enumerate portfolio-repo consumers: `gh search code 'beyond-scale-group/bsg-workflows' --owner beyond-scale-group` (or grep across cloned portfolio repos).
- [ ] **0.2** Decide tag strategy: keep `v1` frozen, cut `v2` at the end of Phase 3. No retagging of `v1`.
- [ ] **0.3** Rename GitHub repo `beyond-scale-group/bsg-workflows` → `beyond-scale-group/bsg-stack`. GitHub installs a permanent redirect; `uses: beyond-scale-group/bsg-workflows/.github/workflows/scala_test.yaml@v1` keeps working.
- [ ] **0.4** Verify redirect: trigger one CI in a portfolio repo against `@v1` post-rename, confirm green.
- [ ] **0.5** Locally: `git remote set-url origin git@github.com:beyond-scale-group/bsg-stack.git` (auto after rename; verify).

**Rollback:** GitHub repo rename is reversible within 30 days by renaming back.

---

## Phase 1 — Additive structural changes (PR 1, non-breaking)

**Goal:** land the "stack of components" framing without touching existing consumers.

Single PR: `chore: adopt stack component layout (additive)`.

- [ ] **1.1** Add `renovate/README.md` — what each preset does, how to consume, how to add a new preset.
- [ ] **1.2** Add `claude-skills/README.md` — component overview linking to existing `INSTALL.md` (don't duplicate install steps).
- [ ] **1.3** Add `docs/renovate.md` and `docs/claude-skills.md` — thin pages linking back to the component dirs.
- [ ] **1.4** Add `stack.yaml` at repo root:
  ```yaml
  version: 1                 # manifest schema, not stack version
  stack_version: v1          # current stack tag
  components:
    workflows:
      path: .github/workflows
    renovate:
      path: renovate
      presets: [scala, react]
    claude-skills:
      path: claude-skills
      manifest: claude-skills/manifest.json
  ```
- [ ] **1.5** Update root `README.md` §"What's in the Box" to link each component's own README.
- [ ] **1.6** Root `INSTALL.md` already exists — cross-link from `README.md` Quick Start.
- [ ] **1.7** Extend `.github/workflows/claude_skills_test.yaml` (or add `ci-validate-stack.yaml`) to lint `stack.yaml` — sanity check that declared paths exist.

Merge & tag as `v1.x.y` via existing semantic-release — still backwards compatible.

---

## Phase 2 — Rename Renovate presets (PR 2, minor breaking)

**Goal:** smallest surface, isolate breakage.

Single PR: `refactor(renovate): rename presets, drop redundant _config suffix`.

- [ ] **2.1** `git mv renovate/scala_config.json renovate/scala.json`
- [ ] **2.2** `git mv renovate/react_config.json renovate/react.json`
- [ ] **2.3** Keep **stub files** `scala_config.json` and `react_config.json` for one release cycle, each with `{ "extends": ["./scala.json"] }` so existing callers don't break mid-rename.
- [ ] **2.4** Update `README.md`, `renovate/README.md`, `docs/renovate.md`, and root `INSTALL.md` with new names + "Deprecation: old names removed in `v2`" notice.
- [ ] **2.5** Update `stack.yaml` `presets` list if it references filenames.

Merge & tag as `v1.(next minor)`. Flag the `v2` removal in the PR body.

---

## Phase 3 — Workflow renames + `v2` cut (PR 3, breaking)

**Goal:** the breaking rename, done all at once behind a `v2` tag so callers opt in.

Single PR: `feat!: reorganise workflows with category prefixes (v2)`.

### 3.1 File renames

All via `git mv` so history follows. `.github/workflows/` (flat — GitHub constraint):

| Old name | New name |
|----------|----------|
| `scala_test.yaml` | `test-scala.yaml` |
| `react_vite_test.yaml` | `test-react-vite.yaml` |
| `cobertura_report.yaml` | `report-cobertura.yaml` |
| `junit_report.yaml` | `report-junit.yaml` |
| `semantic_release.yaml` | `release-semantic.yaml` |
| `semantic_pull_request.yaml` | `release-pr-lint.yaml` |
| `create_release_branch.yaml` | `release-branch-create.yaml` |
| `clever_cloud_deploy.yaml` | `deploy-clever-cloud.yaml` |
| `docker_build_and_push.yaml` | `deploy-docker.yaml` |
| `review_app_deploy.yaml` | `deploy-review-app.yaml` |
| `sync_branches.yaml` | `auto-sync-branches.yaml` |
| `sync_branches_with_ai.yaml` | `auto-sync-branches-ai.yaml` |
| `github_pull_request.yaml` | `auto-pr-create.yaml` |
| `pr_auto_add_project.yaml` | `auto-pr-add-project.yaml` |
| `discord_notifier.yaml` | `auto-notify-discord.yaml` |
| `cleanup_artifacts.yaml` | `maint-cleanup-artifacts.yaml` |
| `claude_skills_test.yaml` | `ci-claude-skills-test.yaml` _(internal; optional)_ |

### 3.2 Cross-reference updates in this repo

- [ ] `docs/workflows.md` — rewrite every `uses:` example to the new path.
- [ ] `README.md` — Quick Start block + §"What's in the Box" tables.
- [ ] `INSTALL.md` — `uses:` snippet.
- [ ] `stack.yaml` — bump `stack_version: v2`.
- [ ] `claude-skills/scripts/update-bsg-skills.py` — grep for hard-coded workflow names.
- [ ] Any workflow that `uses:` a sibling workflow in this repo — grep `uses: ./` and `uses: beyond-scale-group/`.

### 3.3 Migration doc

- [ ] Create `docs/migration-v2.md` with the exact old→new table above plus the copy-pasteable find/replace recipe for consumer repos:
  ```
  beyond-scale-group/bsg-workflows → beyond-scale-group/bsg-stack
  /scala_test.yaml@v1               → /test-scala.yaml@v2
  … (full table)
  ```
- [ ] Link from root `README.md` above the Quick Start.

### 3.4 Release

- [ ] Use a conventional commit with `!` (e.g. `feat!: …`) or a `BREAKING CHANGE:` footer so semantic-release cuts `v2.0.0`.
- [ ] Verify the `v2` moving tag exists (default semantic-release creates `v2.0.0`; may need a small workflow to maintain `v2` / `v1` majors — check `semantic_release.yaml`, add if missing).

**Rollback:** `v1` tag still points at old filenames — consumers stay on `@v1` until they migrate.

---

## Phase 4 — Portfolio sweep (out of this repo)

**Goal:** migrate callers off `@v1`/old names.

- [ ] **4.1** Enumerate callers: `gh search code 'beyond-scale-group/bsg-workflows' --owner beyond-scale-group` (or grep across cloned portfolio repos).
- [ ] **4.2** Per repo: open a PR updating `uses:` paths and tags to `@v2` with new names. Small, mechanical PRs — one per repo.
- [ ] **4.3** Track migration progress in a checklist issue on `beyond-scale-group/bsg-stack`.

---

## Phase 5 — Cleanup (PR 4, once portfolio is on `v2`)

**Goal:** remove the Phase 2 stub files now that nothing references them.

- [ ] **5.1** Delete `renovate/scala_config.json`, `renovate/react_config.json` stubs.
- [ ] **5.2** Remove deprecation notices from docs.
- [ ] **5.3** Tag as `v2.x.y`.

---

## Risks & mitigations

| Risk | Mitigation |
|------|------------|
| Portfolio repo builds break mid-rename | GitHub redirect + `@v1` frozen → zero-break until the consumer opts in to `@v2`. |
| Missed internal cross-reference in Phase 3 | Before merging PR 3, manually trigger each workflow with `workflow_dispatch` where possible; run `claude_skills_test` end-to-end. |
| `v2` moving tag not maintained | Check current `semantic_release.yaml` — if it doesn't update major aliases, add a small step to force-push `v2` after each release. |
| Someone later adds a workflow without a category prefix | Lint step in Phase 1.7: validate each `.github/workflows/*.yaml` name matches `^(test\|report\|release\|deploy\|auto\|maint\|ci)-`. |

---

## Open questions

1. Is there a canonical list of portfolio repos consuming `bsg-workflows`, or do we discover via `gh search` in Phase 0.1?
2. `v2` moving-tag job — add in Phase 1 or defer to Phase 3?
3. Are internal-only workflows (`claude_skills_test.yaml`) in scope for the rename, or leave as-is since they have no external callers?

---

## Current status

- [x] Root `INSTALL.md` created (Phase 1.6 prerequisite).
- [x] This plan document saved (`docs/reorganisation-plan.md`).
- [ ] Phase 0 pending.
