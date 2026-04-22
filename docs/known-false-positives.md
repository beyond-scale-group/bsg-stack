# Known false-positives in BSG agent ticks

Findings that repeatedly surface during `/tick-all` sweeps but do not
represent real issues. Track them here so new contributors aren't
surprised and so we remember to patch the underlying skills rather
than re-diagnose each tick.

When an entry is fixed upstream (in `claude-skills/`), close it out by
moving the row to a "Resolved" subsection with the PR that fixed it.

## Active

### security-report flags its own pattern examples

- **Where:** `claude-skills/skills/security-report/references/secrets.md`
  contains `AKIAIOSFODNN7EXAMPLE` and other AWS / token placeholders used
  as *illustrations* of the patterns the skill scans for.
- **Why it fires:** `secrets.sh` has no default exclusion for the skill's
  own reference docs.
- **Mitigation:** Repo-level `.securityignore` lists
  `claude-skills/skills/security-report/references/**`.
- **Upstream fix owed:** bake the exclusion into the skill itself so
  every host repo gets it without bootstrapping.

### seo-report flags sitemap / robots on tooling repos

- **Where:** `bsg-stack` (and any other command/skill/agent repo with no
  web surface).
- **Why it fires:** `@seo` silence-breakers for missing `sitemap.xml` /
  `robots.txt` default to "always" rather than "only if pages exist."
- **Mitigation:** `claude-skills/agents/seo.md` now scopes both
  silence-breakers to `pages | length > 0`.
- **Upstream fix owed:** teach `generate-report.sh` to suppress the
  whole technical section when no pages are scanned so the agent
  doesn't have to filter after the fact.

## Resolved

### open-report-pr.sh rejected sibling-agent untracked dirs

- **Where:** Any `/tick-all` sweep where multiple report agents ran in
  parallel and wrote their output directories (`marketing/`, `qa/`,
  `security/`, …) before the helper ran.
- **Why it fired:** sibling agents shared a single working tree, so
  untracked output dirs collided with each other's clean-tree checks.
- **Resolution:** `/tick-all` now spawns each agent with
  `isolation: "worktree"`, so siblings run in separate trees and
  can't contaminate each other at all. The strict clean-tree guard
  in `open-report-pr.sh` has been restored — tracked *and*
  untracked stragglers now fail the guard.
